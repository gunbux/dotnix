"""Send WakaTime heartbeats for the minutes an AI agent was working.

`wakatime-cli --sync-ai-activity` sends a heartbeat only when you send a prompt
or the agent reads or edits a file. An agent that runs commands, or waits on
tools or subagents, sends nothing, and that time is lost once a gap passes the
timeout (10 minutes in Wakapi). This reads the same transcripts (Claude Code,
including subagents, and Codex, including .jsonl.zst archives) and sends one
app heartbeat per session and active minute, category "ai coding".

The heartbeats go through wakatime-cli, so ~/.wakatime.cfg (API URL, key and
hide settings) applies. Each run covers the time since the last run, with 15
minutes of overlap; the server drops the duplicate heartbeats.

Usage: wakatime-agent-activity [--since 2026-10-01T00:00:00+08:00] [--dry-run]
State: ~/.wakatime/agent-activity.json
"""

import argparse
import configparser
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".wakatime" / "agent-activity.json"
OVERLAP = 15 * 60
FIRST_RUN = 24 * 3600
BATCH = 500
CLI = os.environ.get("WAKATIME_CLI", "wakatime-cli")


def parse_ts(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def read_lines(path):
    """Yield decoded JSON lines from a .jsonl or .jsonl.zst file."""
    if path.name.endswith(".zst"):
        out = subprocess.run(["zstd", "-q", "-dc", str(path)], capture_output=True, check=False).stdout
        lines = out.decode("utf-8", "replace").splitlines()
    else:
        lines = path.open(encoding="utf-8", errors="replace")
    for line in lines:
        try:
            yield json.loads(line)
        except ValueError:
            continue


def recent_files(root, patterns, since):
    if not root.is_dir():
        return []
    files = []
    for pattern in patterns:
        for path in root.rglob(pattern):
            try:
                if path.is_file() and path.stat().st_mtime >= since:
                    files.append(path)
            except OSError:
                continue
    return files


def model_token(model):
    """claude-opus-5-5 -> opus/5-5, gpt-6.1-sol -> gpt/6.1-sol (as wakatime-cli writes it)."""
    model = (model or "").strip().lower()
    if not model or model.startswith("<"):
        return ""
    model = re.sub(r"^claude-", "", model)
    name, _, version = model.partition("-")
    return f"{name}/{version}" if version else f"{name}/unknown"


class Activity:
    """Active minutes per (entity, user agent plugin), with the session's working folder."""

    def __init__(self, start, end):
        self.start, self.end = start, end
        self.minutes = defaultdict(set)
        self.cwd = {}

    def add(self, entity, plugin, cwd, ts):
        if ts is None or not self.start <= ts <= self.end:
            return
        key = (entity, plugin)
        self.minutes[key].add(int(ts // 60) * 60)
        if cwd:
            self.cwd[key] = cwd


def scan_claude(activity, since):
    root = HOME / ".claude" / "projects"
    for path in recent_files(root, ["*.jsonl"], since):
        model, version = "", ""
        for line in read_lines(path):
            if not isinstance(line, dict) or line.get("type") not in ("user", "assistant"):
                continue
            message = line.get("message") or {}
            if line.get("type") == "assistant" and message.get("model"):
                model = model_token(message["model"]) or model
            version = line.get("version") or version
            session = line.get("sessionId")
            if not session:
                continue
            plugin = " ".join(x for x in (model, f"claude-code/{version or 'unknown'}") if x)
            activity.add(f"Claude {session}", plugin, line.get("cwd"), parse_ts(line.get("timestamp")))


def scan_codex(activity, since):
    home = Path(os.environ.get("CODEX_HOME") or HOME / ".codex")
    for sub in ("sessions", "archived_sessions"):
        for path in recent_files(home / sub, ["*.jsonl", "*.jsonl.zst"], since):
            entity = "Codex " + re.sub(r"\.jsonl(\.zst)?$", "", path.name)
            cwd, model, version = None, "", "unknown"
            for line in read_lines(path):
                if not isinstance(line, dict):
                    continue
                kind, payload = line.get("type"), line.get("payload") or {}
                if kind == "session_meta":
                    cwd = payload.get("cwd") or cwd
                    version = payload.get("cli_version") or version
                elif kind == "turn_context":
                    cwd = payload.get("cwd") or cwd
                    model = model_token(payload.get("model")) or model
                if kind not in ("response_item", "event_msg"):
                    continue
                plugin = " ".join(x for x in (model, f"codex/{version}") if x)
                activity.add(entity, plugin, cwd, parse_ts(line.get("timestamp")))


_projects = {}


def project_for(cwd):
    """The git repository's folder name for cwd, or the folder name itself."""
    if not cwd:
        return None
    if cwd not in _projects:
        path = Path(cwd)
        name = path.name
        for parent in [path, *path.parents]:
            git = parent / ".git"
            if git.is_dir():
                name = parent.name
                break
            if git.is_file():  # a worktree: name it after the main repository
                text = git.read_text(errors="replace")
                match = re.search(r"gitdir:\s*(.+?)/\.git/worktrees/", text)
                name = Path(match.group(1)).name if match else parent.name
                break
        _projects[cwd] = name or None
    return _projects[cwd]


def hides_projects():
    cfg = configparser.ConfigParser(strict=False, interpolation=None)
    try:
        cfg.read(HOME / ".wakatime.cfg")
        return cfg.getboolean("settings", "hide_project_names", fallback=False)
    except (configparser.Error, ValueError):
        return False


def send(plugin, heartbeats, dry_run):
    """Send heartbeats with one wakatime-cli call per batch. Returns True when all were accepted or queued."""
    ok = True
    for i in range(0, len(heartbeats), BATCH):
        batch = heartbeats[i:i + BATCH]
        first, rest = batch[0], batch[1:]
        cmd = [CLI, "--entity", first["entity"], "--entity-type", "app", "--category", "ai coding",
               "--time", str(first["time"]), "--plugin", plugin, "--heartbeat-rate-limit-seconds", "0",
               "--extra-heartbeats"]
        if first.get("project"):
            cmd += ["--project", first["project"]]
        if dry_run:
            continue
        result = subprocess.run(cmd, input=json.dumps(rest), text=True, capture_output=True, check=False)
        # 0: sent. 112: the API was unreachable and the heartbeats were queued offline.
        if result.returncode not in (0, 112):
            print(f"wakatime-cli exited {result.returncode}: {result.stderr.strip()[:300]}", file=sys.stderr)
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--since", help="ISO 8601 start time (backfill); default: the last run")
    parser.add_argument("--dry-run", action="store_true", help="count heartbeats, send nothing")
    args = parser.parse_args()

    now = time.time()
    state = {}
    if STATE.exists():
        try:
            state = json.loads(STATE.read_text())
        except ValueError:
            state = {}
    if args.since:
        start = parse_ts(args.since)
        if start is None:
            parser.error(f"bad --since: {args.since}")
    else:
        start = state.get("cutoff", now - FIRST_RUN) - OVERLAP

    activity = Activity(start, now)
    scan_claude(activity, start)
    scan_codex(activity, start)

    hide = hides_projects()
    by_plugin = defaultdict(list)
    for (entity, plugin), minutes in activity.minutes.items():
        project = None if hide else project_for(activity.cwd.get((entity, plugin)))
        for minute in sorted(minutes):
            hb = {"entity": entity, "type": "app", "category": "ai coding", "time": minute, "is_write": False}
            if project:
                hb["project"] = project
            by_plugin[plugin].append(hb)

    total = sum(len(v) for v in by_plugin.values())
    ok = all([send(plugin, hbs, args.dry_run) for plugin, hbs in by_plugin.items()])
    if total and not args.dry_run:
        # Batches over wakatime-cli's 10-heartbeat send limit wait in the offline queue.
        subprocess.run([CLI, "--sync-offline-activity", str(total + 100)], capture_output=True, check=False)
    print(f"{total} heartbeat(s) for {len(activity.minutes)} session(s) since "
          f"{dt.datetime.fromtimestamp(start).isoformat(timespec='seconds')}" + (" (dry run)" if args.dry_run else ""))

    if ok and not args.dry_run:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({"cutoff": now}))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
