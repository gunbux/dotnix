"""Claude Code Stop hook: block a work-repo reply that hands Chun infra apply commands without a wizard.

Chun applies Terraform, Terragrunt and OpenTofu changes on work infra himself, and wants each such handoff as a
wizard script (the `wizard` skill), never as raw commands pasted in the reply.
"""

import json
import re
import sys
from pathlib import Path

WORK_REPO = re.compile(r"/(repo/greptilia|worktrees/greptilia/)")
FENCE = re.compile(r"```[^\n]*\n(.*?)```", re.S)
APPLY = re.compile(r"\b(terragrunt|terraform|tofu)\b[^\n]*\b(apply|destroy)\b")
WIZARD_SCRIPT = re.compile(r"wizard[^\s`]*\.sh\b")

REASON = (
    "This reply hands Chun raw Terraform/Terragrunt apply commands. He wants a wizard for every manual "
    "procedure: load the `wizard` skill, write the script (each apply as a confirmed stage, after the plan "
    "summary in words), run `bash -n` on it, and give him the script path and the one command to run it."
)


def last_reply(transcript: Path) -> str:
    reply = ""
    for line in transcript.read_text().splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        if isinstance(content, str):
            text = content
        else:
            text = "\n".join(block.get("text", "") for block in content if block.get("type") == "text")
        if text.strip():
            reply = text
    return reply


def needs_wizard(reply: str) -> bool:
    handed_over = any(APPLY.search(block) for block in FENCE.findall(reply))
    return handed_over and not WIZARD_SCRIPT.search(reply)


def main() -> None:
    hook = json.load(sys.stdin)
    if hook.get("stop_hook_active") or not WORK_REPO.search(hook.get("cwd", "")):
        return
    transcript = Path(hook.get("transcript_path", ""))
    if transcript.is_file() and needs_wizard(last_reply(transcript)):
        print(json.dumps({"decision": "block", "reason": REASON}))


if __name__ == "__main__":
    main()
