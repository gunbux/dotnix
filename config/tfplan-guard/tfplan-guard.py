"""Stop a Terraform apply that would change anything the reviewed plan did not.

  tfplan-guard record plan.json > scope.json   # the agent's reviewed plan becomes the apply's scope
  tfplan-guard check scope.json plan.json      # exit 0 only when plan.json makes exactly those changes

plan.json comes from `terragrunt show -json <plan>`. A change is its action, its address, and each attribute it
changes with a hash of the new value. `check` fails when the new plan has a change the scope lacks (such as another
engineer's unapplied work, or a deletion of their resources), lacks a change the scope has, changes other
attributes, or sets a reviewed attribute to a different value (such as someone's later edit to the same file).
"""

import hashlib
import json
import sys

UNKNOWN = "(known after apply)"

USAGE = "usage: tfplan-guard record PLAN_JSON | tfplan-guard check SCOPE_JSON PLAN_JSON"


def unknown(value):
    if isinstance(value, dict):
        return any(unknown(v) for v in value.values())
    if isinstance(value, list):
        return any(unknown(v) for v in value)
    return value is True


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()[:16]


def changed_attrs(change):
    """{attribute: hash of its new value, or UNKNOWN} for every attribute the change sets."""
    before, after = change.get("before") or {}, change.get("after") or {}
    unknown_keys = {k for k, v in (change.get("after_unknown") or {}).items() if unknown(v)}
    keys = {k for k in set(before) | set(after) if before.get(k) != after.get(k)} | unknown_keys
    return {k: UNKNOWN if k in unknown_keys else digest(after.get(k)) for k in sorted(keys)}


def changes(plan):
    """{address: (action, attrs)} for every resource the plan creates, updates, replaces or deletes."""
    out = {}
    for rc in plan.get("resource_changes", []):
        actions = rc["change"]["actions"]
        if actions in (["no-op"], ["read"]):
            continue
        action = "replace" if len(actions) == 2 else actions[0]
        attrs = changed_attrs(rc["change"]) if action in ("update", "replace") else {}
        out[rc["address"]] = (action, attrs)
    return out


def load(path):
    with open(path) as f:
        return json.load(f)


def record(plan_path):
    scope = [{"action": a, "address": addr, "attrs": attrs} for addr, (a, attrs) in sorted(changes(load(plan_path)).items())]
    json.dump({"changes": scope}, sys.stdout, indent=2)
    print()
    return 0


def check(scope_path, plan_path):
    scope = {c["address"]: (c["action"], c["attrs"]) for c in load(scope_path)["changes"]}
    plan = changes(load(plan_path))
    problems = []
    for addr, (action, attrs) in sorted(plan.items()):
        if addr not in scope:
            problems.append(f"not reviewed: {action} {addr}" + (f" (changes {', '.join(attrs)})" if attrs else ""))
            continue
        want_action, want_attrs = scope[addr]
        if action != want_action:
            problems.append(f"different action: {addr} is now {action}, reviewed as {want_action}")
        extra = [a for a in attrs if a not in want_attrs]
        if extra:
            problems.append(f"more attributes: {action} {addr} also changes {', '.join(extra)}")
        moved = [a for a in attrs if a in want_attrs and attrs[a] != want_attrs[a] and UNKNOWN not in (attrs[a], want_attrs[a])]
        if moved:
            problems.append(f"different value: {action} {addr} now sets {', '.join(moved)} to a value nobody reviewed")
    for addr, (action, _) in sorted(scope.items()):
        if addr not in plan:
            problems.append(f"missing: reviewed {action} {addr} is no longer in the plan")
    for p in problems:
        print(p)
    return 1 if problems else 0


def main(argv):
    if len(argv) == 2 and argv[0] == "record":
        return record(argv[1])
    if len(argv) == 3 and argv[0] == "check":
        return check(argv[1], argv[2])
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
