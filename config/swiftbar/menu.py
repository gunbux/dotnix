"""Desktop, clock, media and AI quota menus for SwiftBar."""

import argparse
from datetime import datetime
import json
import math
from pathlib import Path
import shlex
import subprocess
from zoneinfo import ZoneInfo


CODEXBAR = "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"


def remaining_quota(window):
    used = window.get("usedPercent") if isinstance(window, dict) else None
    if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used) or used < 0:
        return None
    return max(0, 100 - used)


def usage_menu(payload, notice=""):
    entries = {
        entry.get("provider"): entry for entry in payload
        if isinstance(entry, dict) and entry.get("provider") in ("claude", "codex")
    } if isinstance(payload, list) else {}
    titles, details = [], []
    for provider, name, short in (("claude", "Claude", "C"), ("codex", "Codex", "O")):
        entry = entries.get(provider, {})
        usage = entry.get("usage")
        if not isinstance(usage, dict) or entry.get("error"):
            usage = {}
        remaining = remaining_quota(usage.get("primary"))
        titles.append(f"{short} {remaining:.0f}%" if remaining is not None else f"{short} ?")
        details.append(f"{name}: remaining quota" if usage else f"{name}: unavailable")
        updated = usage.get("updatedAt")
        if isinstance(updated, str):
            try:
                updated_at = datetime.fromisoformat(updated.replace("Z", "+00:00"))
                if updated_at.tzinfo is not None:
                    if datetime.now().timestamp() - updated_at.timestamp() > 600:
                        titles[-1] += " (stale)"
                    details.append(f"Updated {updated_at.astimezone():%a %d %b, %H:%M %Z}")
            except ValueError:
                pass
        for key, label in (("primary", "Session"), ("secondary", "Weekly")):
            window = usage.get(key)
            if isinstance(window, dict) and window.get("windowMinutes") == 10080:
                label = "Weekly"
            remaining = remaining_quota(window)
            details.append(f"{label}: {remaining:.0f}% left" if remaining is not None else f"{label}: unknown")
            reset = window.get("resetsAt") if isinstance(window, dict) else None
            if isinstance(reset, str):
                try:
                    reset_at = datetime.fromisoformat(reset.replace("Z", "+00:00"))
                    if reset_at.tzinfo is not None:
                        details.append(f"Resets {reset_at.astimezone():%a %d %b, %H:%M %Z}")
                except ValueError:
                    pass
        details.append("---")
    rows = [" · ".join(titles) + " | tooltip='Claude / OpenAI Codex: remaining quota'", "---",
            "C = Claude · O = OpenAI Codex; percentages remaining"]
    rows.extend(details)
    if notice:
        rows.append(safe_label(notice))
    rows.extend([
        "Refresh usage | refresh=true",
        "Configure CodexBar | " + action("/usr/bin/open", "-a", "CodexBar"),
    ])
    return "\n".join(rows)


def current_usage(executable=CODEXBAR):
    try:
        # Explicit OAuth reuses CLI logins without scraping browsers or launching agents.
        # A failed provider can make the CLI exit nonzero alongside valid JSON for the other.
        result = subprocess.run(
            [executable, "usage", "--provider", "both", "--source", "oauth", "--format", "json"],
            capture_output=True, text=True, timeout=45, check=False,
        )
        payload = json.loads(result.stdout)
        if not isinstance(payload, list):
            raise ValueError("Unexpected payload")
        return usage_menu(payload)
    except FileNotFoundError:
        return usage_menu([], "CodexBar is not installed yet. Apply the Mac configuration.")
    except (OSError, subprocess.SubprocessError, ValueError):
        # Raw provider errors may contain account details or credentials.
        return usage_menu([], "Could not read usage. Check your Claude/Codex login and CodexBar settings.")


def workspace_menu(state):
    current = state.get("current") if isinstance(state, dict) else None
    if not isinstance(current, int) or isinstance(current, bool):
        return "PaperWM | sfimage=rectangle.split.3x1\n---\nWaiting for Hammerspoon"
    title = f"Desk {current}" if state.get("running", True) else "PaperWM paused"
    rows = [f"{title} | sfimage=rectangle.split.3x1", "---"]
    for space in state.get("spaces", []):
        number = space.get("index")
        count = space.get("windows", 0)
        if not isinstance(number, int) or isinstance(number, bool) or not 1 <= number <= 99:
            continue
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            count = 0
        label = f"Desktop {number}"
        if state.get("running", True):
            label += f" · {count} {'window' if count == 1 else 'windows'}"
        checked = "true" if number == current else "false"
        rows.append(f"{label} | href=hammerspoon://paperwm?action=switch&index={number} checked={checked}")
        if state.get("running", True):
            rows.append(f"Move window to desktop {number} | href=hammerspoon://paperwm?action=send&index={number} alternate=true")
    if state.get("running", True):
        rows.append("Hold Option to send the focused window | color=gray")
    rows.append("Pause / resume PaperWM | href=hammerspoon://paperwm?action=toggle")
    return "\n".join(rows)


def clock_menu(now):
    sg = now.astimezone(ZoneInfo("Asia/Singapore"))
    us = now.astimezone(ZoneInfo("America/Los_Angeles"))
    rows = [
        f"SG {sg:%H:%M} · LA {us:%H:%M}",
        "---",
        f"Singapore: {sg:%a %d %b, %H:%M}",
        f"Los Angeles: {us:%a %d %b, %H:%M}",
    ]
    if now.utcoffset() not in (sg.utcoffset(), us.utcoffset()):
        rows.append(f"Local: {now:%a %d %b, %H:%M}")
    rows.append('Date & Time settings | href=x-apple.systempreferences:com.apple.Date-Time-Settings.extension')
    return "\n".join(rows)


def safe_label(value):
    # Track metadata is text, never SwiftBar separators, submenus, or actions.
    return " ".join(value.replace("|", "¦").split()).lstrip("-").strip()


def action(executable, *params):
    properties = [f"bash={shlex.quote(executable)}"]
    properties.extend(f"param{index}={shlex.quote(param)}" for index, param in enumerate(params, 1))
    return " ".join(properties) + " terminal=false refresh=true"


def media_menu(app, state, artist, title):
    if app not in ("Spotify", "Music") or state not in ("playing", "paused"):
        return ""
    label = safe_label(artist) + " · " + safe_label(title)
    status = "Playing" if state == "playing" else "Paused"
    rows = [
        f"{label} | sfimage=music.note length=28 symbolize=false emojize=false",
        "---",
        f"{status} in {app}",
        f"{label} | symbolize=false emojize=false",
    ]
    for text, verb in (("Play / pause", "playpause"), ("Next track", "next track"), ("Previous track", "previous track")):
        rows.append(f"{text} | " + action("/usr/bin/osascript", "-e", f'tell application "{app}" to {verb}'))
    rows.append(f"Open {app} | " + action("/usr/bin/open", "-a", app))
    return "\n".join(rows)


def command(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def current_media():
    paused = ""
    for app in ("Spotify", "Music"):
        if not command("/usr/bin/pgrep", "-x", app):
            continue
        output = command("/usr/bin/osascript", "-e", f'''tell application "{app}"
if player state is not stopped then
return (player state as text) & (character id 31) & artist of current track & (character id 31) & name of current track
end if
end tell''')
        fields = output.split("\x1f", 2)
        if len(fields) != 3:
            continue
        menu = media_menu(app, *fields)
        if fields[0] == "playing":
            return menu
        paused = paused or menu
    return paused


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("widget", choices=("clock", "media", "workspaces", "usage"))
    parser.add_argument("--state-file")
    args = parser.parse_args()
    if args.widget == "usage":
        print(current_usage())
    elif args.widget == "workspaces":
        try:
            path = Path(args.state_file)
            state = json.loads(path.read_text()) if datetime.now().timestamp() - path.stat().st_mtime < 10 else {}
        except (OSError, ValueError, TypeError):
            state = {}
        print(workspace_menu(state))
    else:
        print(clock_menu(datetime.now().astimezone()) if args.widget == "clock" else current_media())
