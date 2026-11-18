"""Run: python3 -I config/tfplan-guard/test_tfplan_guard.py (the Nix build runs it too)."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

GUARD = os.environ.get("TFPLAN_GUARD") or str(Path(__file__).with_name("tfplan-guard.py"))


def rc(address, actions, before=None, after=None, after_unknown=None):
    return {"address": address, "change": {"actions": actions, "before": before, "after": after, "after_unknown": after_unknown or {}}}


OWN = rc("datadog_dashboard_json.mine", ["update"], {"dashboard": "old", "url": "u"}, {"dashboard": "new", "url": "u"})
NOOP = rc("datadog_monitor_json.quiet", ["no-op"], {"monitor": "m"}, {"monitor": "m"})


def run(*args):
    cmd = [GUARD, *args] if os.access(GUARD, os.X_OK) and not GUARD.endswith(".py") else [sys.executable, "-I", GUARD, *args]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout


def write(tmp, name, data):
    path = Path(tmp, name)
    path.write_text(json.dumps(data))
    return str(path)


def scope_from(tmp, *changes):
    code, out = run("record", write(tmp, "reviewed.json", {"resource_changes": list(changes)}))
    assert code == 0, out
    return write(tmp, "scope.json", json.loads(out))


def check(tmp, scope, *changes):
    return run("check", scope, write(tmp, "plan.json", {"resource_changes": list(changes)}))


def main():
    with tempfile.TemporaryDirectory() as tmp:
        scope = scope_from(tmp, OWN, NOOP)

        code, out = check(tmp, scope, OWN, NOOP)
        assert (code, out) == (0, ""), "the reviewed plan itself passes"

        # The 16 Nov 2026 dashboard apply: the PR owned one dashboard update, and the plan also deleted another
        # engineer's monitors and Slack channel, which were not on main yet.
        code, out = check(
            tmp,
            scope,
            OWN,
            rc("datadog_monitor_json.others_detection[\"staging\"]", ["delete"], {"monitor": "m"}, None),
            rc("datadog_integration_slack_channel.alerts[\"others\"]", ["delete"], {"name": "c"}, None),
        )
        assert code == 1, "someone else's deletions stop the apply"
        assert 'not reviewed: delete datadog_monitor_json.others_detection["staging"]' in out, out
        assert 'not reviewed: delete datadog_integration_slack_channel.alerts["others"]' in out, out

        code, out = check(tmp, scope, rc("datadog_dashboard_json.mine", ["update"], {"dashboard": "a", "url": "u"}, {"dashboard": "b", "url": "v"}))
        assert code == 1 and "also changes url" in out, out

        code, out = check(tmp, scope, rc("datadog_dashboard_json.mine", ["update"], {"dashboard": "a"}, {"dashboard": "a"}, {"dashboard": True, "url": True}))
        assert code == 1 and "also changes url" in out, "an attribute known only after apply counts as changed"

        code, out = check(tmp, scope, rc("datadog_dashboard_json.mine", ["delete", "create"], {"dashboard": "a"}, {"dashboard": "b"}))
        assert code == 1 and "now replace, reviewed as update" in out, out

        code, out = check(tmp, scope)
        assert code == 1 and "missing: reviewed update datadog_dashboard_json.mine" in out, out

        code, out = check(tmp, scope, rc("datadog_dashboard_json.mine", ["update"], {"dashboard": "x", "url": "u"}, {"dashboard": "new", "url": "u"}))
        assert (code, out) == (0, ""), "live drift in the old value does not matter"

        code, out = check(tmp, scope, rc("datadog_dashboard_json.mine", ["update"], {"dashboard": "old"}, {"dashboard": "someone else's edit"}))
        assert code == 1 and "sets dashboard to a value nobody reviewed" in out, "a later edit to the same resource stops the apply"

        code, _ = run("check", scope)
        assert code == 2, "wrong arguments are a usage error, never a pass"
    print("tfplan-guard: all checks pass")


if __name__ == "__main__":
    main()
