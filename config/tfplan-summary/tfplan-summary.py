#!/usr/bin/env python3
"""Say in words what a Terraform plan changes, not only how many resources.

  tfplan-summary plan.json                  # from `terraform show -json <plan>` (or terragrunt show -json)
  tfplan-summary --dashboard old.json new.json   # diff two Datadog dashboard definitions

For each resource: the action, and the attributes that change (old -> new for
short values). A Datadog dashboard (datadog_dashboard_json, datadog_dashboard)
gets a widget-level diff: groups and widgets added, removed, moved, changed.
"""
import json
import sys

SHORT = 60


def short(v):
    s = json.dumps(v) if not isinstance(v, str) else v
    return s if len(s) <= SHORT else s[: SHORT - 1] + "…"


def widgets(dash):
    """(group title, widget title, type, definition) for every widget, in order."""
    out = []

    def walk(ws, group):
        for w in ws or []:
            d = w.get("definition", {})
            if d.get("type") == "group":
                out.append((group, d.get("title") or "(untitled group)", "group", {k: v for k, v in d.items() if k != "widgets"}))
                walk(d.get("widgets"), d.get("title") or "(untitled group)")
            else:
                title = d.get("title") or (d.get("content", "")[:40] if d.get("type") == "note" else "") or "(untitled)"
                out.append((group, title, d.get("type"), {**d, "_layout": w.get("layout")}))

    walk(dash.get("widgets"), None)
    return out


def dashboard_diff(old, new):
    lines = []
    for key in ("title", "description", "layout_type", "reflow_type", "template_variables", "tags"):
        if old.get(key) != new.get(key):
            lines.append(f"dashboard {key}: {short(old.get(key))} -> {short(new.get(key))}")
    ow, nw = widgets(old), widgets(new)
    ok = {(g, t, ty): d for g, t, ty, d in ow}
    nk = {(g, t, ty): d for g, t, ty, d in nw}
    og = [t for g, t, ty, _ in ow if ty == "group"]
    ng = [t for g, t, ty, _ in nw if ty == "group"]
    if og != ng:
        lines.append(f"groups: {len(og)} -> {len(ng)}. Now, in order: " + "; ".join(ng))
        gone = [t for t in og if t not in ng]
        if gone:
            lines.append("groups removed: " + "; ".join(gone))
    count = lambda ws: sum(1 for _, _, ty, _ in ws if ty != "group")
    notes = lambda ws: sum(1 for _, _, ty, _ in ws if ty == "note")
    lines.append(f"widgets: {count(ow)} -> {count(nw)} (notes {notes(ow)} -> {notes(nw)})")
    added = [k for k in nk if k not in ok and k[2] != "group"]
    removed = [k for k in ok if k not in nk and k[2] != "group"]
    changed = [k for k in nk if k in ok and k[2] != "group" and ok[k] != nk[k]]
    bygroup = lambda ks: {g: [f"{t} ({ty})" for gg, t, ty in ks if gg == g] for g in dict.fromkeys(k[0] for k in ks)}
    for label, ks, whole in (("added", added, set(ng) - set(og)), ("removed", removed, set(og) - set(ng)), ("changed", changed, set())):
        if not ks:
            continue
        lines.append(f"widgets {label}: {len(ks)}")
        for g, items in bygroup(ks).items():
            if g in whole and label == "removed":
                lines.append(f"  whole group {g!r}: {len(items)} widgets")
            else:
                lines.append(f"  in {g or 'top level'}: " + "; ".join(items))
    return lines


def attr_diff(before, after, path="", out=None):
    out = [] if out is None else out
    if isinstance(before, dict) and isinstance(after, dict):
        for k in sorted(set(before) | set(after)):
            attr_diff(before.get(k), after.get(k), f"{path}.{k}" if path else k, out)
    elif before != after:
        out.append(f"{path}: {short(before)} -> {short(after)}")
    return out


def plan_summary(plan):
    lines = []
    changes = [rc for rc in plan.get("resource_changes", []) if rc["change"]["actions"] not in (["no-op"], ["read"])]
    if not changes:
        return ["No changes."]
    for rc in changes:
        acts = "+".join(rc["change"]["actions"])
        lines.append(f"{acts} {rc['address']}")
        b, a = rc["change"].get("before") or {}, rc["change"].get("after") or {}
        if rc["type"] in ("datadog_dashboard_json",) and (b.get("dashboard") or a.get("dashboard")):
            old = json.loads(b["dashboard"]) if b.get("dashboard") else {}
            new = json.loads(a["dashboard"]) if a.get("dashboard") else {}
            lines += ["  " + l for l in dashboard_diff(old, new)]
            rest = attr_diff({k: v for k, v in b.items() if k != "dashboard"}, {k: v for k, v in a.items() if k != "dashboard"})
        else:
            rest = attr_diff(b, a)
        unknown = rc["change"].get("after_unknown") or {}
        rest = [r for r in rest if r.split(":")[0] not in unknown]
        lines += ["  " + r for r in rest[:20]] + ([f"  … {len(rest) - 20} more attributes"] if len(rest) > 20 else [])
    return lines


def main(argv):
    if len(argv) == 4 and argv[1] == "--dashboard":
        print("\n".join(dashboard_diff(json.load(open(argv[2])), json.load(open(argv[3])))))
    elif len(argv) == 2:
        print("\n".join(plan_summary(json.load(open(argv[1]) if argv[1] != "-" else sys.stdin))))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
