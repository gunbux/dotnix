"""Claude Code PreToolUse hook: deny a Bash command that reads the macOS keychain until the agent has told Chun.

Reading a keychain item from another app (`security find-generic-password`, for example a Pup token) opens a macOS
dialog that waits for Chun to click Allow. Run silently, the command just hangs while he wonders why. The agent must
first say, in this turn's visible text, that it needs his keychain and that a dialog will appear.
"""

import json
import re
import sys
from pathlib import Path

KEYCHAIN_READ = re.compile(
    r"\bsecurity\s+(find-generic-password|find-internet-password|find-certificate|dump-keychain|unlock-keychain|export)\b"
)
ANNOUNCED = re.compile(r"\bkeychain\b", re.I)

REASON = (
    "This command reads Chun's macOS keychain, which opens a dialog he must approve. Before you run it, tell him "
    "explicitly in a visible message: that you need his keychain, which item and why, and that a macOS dialog will "
    "appear for him to click Allow. Then run the command again."
)


def turn_texts(transcript: Path) -> list[str]:
    """Assistant text since the last message Chun typed (tool results don't count as his messages)."""
    texts: list[str] = []
    for line in transcript.read_text().splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        content = entry.get("message", {}).get("content", [])
        if entry.get("type") == "user":
            typed = isinstance(content, str) or any(block.get("type") == "text" for block in content)
            if typed:
                texts = []
        elif entry.get("type") == "assistant" and not isinstance(content, str):
            texts += [block.get("text", "") for block in content if block.get("type") == "text"]
    return texts


def main() -> None:
    hook = json.load(sys.stdin)
    command = hook.get("tool_input", {}).get("command", "")
    if hook.get("tool_name") != "Bash" or not KEYCHAIN_READ.search(command):
        return
    transcript = Path(hook.get("transcript_path", ""))
    if transcript.is_file() and any(ANNOUNCED.search(text) for text in turn_texts(transcript)):
        return
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": REASON,
                }
            }
        )
    )


if __name__ == "__main__":
    main()
