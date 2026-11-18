"""Run: python3 -I config/require-wizard/test_require_wizard.py WIZARD_TEMPLATE (the Nix build runs it too)."""

import importlib.util
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("require_wizard", Path(__file__).with_name("require-wizard.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

TEMPLATE = Path(sys.argv[1]).read_text()
LIBRARY = TEMPLATE.split("run_wizard() {")[0]


def wizard(stages: str) -> str:
    return LIBRARY + "run_wizard() {\n" + stages + "\n}\n\nrun_wizard \"$@\"; exit\n"


def main() -> None:
    guarded = wizard('stage "Apply"\ntf_apply_reviewed "$UNIT" greptile-staging "$SCOPE" /tmp/x.tfplan')
    assert hook.unguarded_applies(guarded, TEMPLATE) == [], "an apply through tf_apply_reviewed passes"

    # The 17 Nov 2026 gate wizards applied with their own copy of the guard and a raw apply.
    raw = wizard('stage "Apply"\n(cd "$REPO/$UNITS/eks" && AWS_PROFILE=greptile-staging terragrunt apply "$PLAN")')
    problems = hook.unguarded_applies(raw, TEMPLATE)
    assert len(problems) == 1 and "terragrunt apply" in problems[0], problems

    weakened = guarded.replace('    exit 1\n  fi\n  say "${GREEN}✓', '  fi\n  say "${GREEN}✓', 1)
    assert weakened != guarded
    assert any("differs from" in p for p in hook.unguarded_applies(weakened, TEMPLATE)), "a weakened guard copy fails"

    commented = wizard("# never: terragrunt apply without a plan file\nsay hi")
    assert hook.unguarded_applies(commented, TEMPLATE) == [], "comments do not count"

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp, "gate-b-store-egress.sh")
        path.write_text(raw)
        assert hook.wizard_problems(f"Run `{path}` when #18980 merges.") != [], "any named .sh path is checked"
        assert hook.wizard_problems(f"Run {tmp}/missing.sh") == [], "a path that does not exist is skipped"

    assert hook.needs_wizard("```bash\ncd /x && terragrunt apply /tmp/p\n```"), "raw apply commands still block"
    print("require-wizard: all checks pass")


if __name__ == "__main__":
    main()
