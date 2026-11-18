#!/usr/bin/env bash
# lint.sh WIZARD...: fails when a wizard drifts from template.sh in a way that has gone wrong before.
#   1. Its library (everything above the "# STAGES:" line) differs from the template's: a hand-edited or old library
#      lacks run_stage, so a failed run can't resume and an agent finishes the stages by hand (2026-11-17/18).
#   2. A stage runs without run_stage, so a re-run repeats it or the agent skips it by hand.
#   3. A stage asks the human to run checks from a README or in another terminal. The wizard runs its own checks;
#      a check left as prose got replaced with another gate's script (2026-11-18).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lib() { sed '/^# STAGES:/q' "$1"; }
status=0
for w in "$@"; do
  if ! diff -q <(lib "$here/template.sh") <(lib "$w") >/dev/null; then
    echo "$w: its library differs from $here/template.sh. Copy the template's library above '# STAGES:' unchanged; put helpers below it."
    status=1
  fi
  below=$(sed -n '/^# STAGES:/,$p' "$w")
  if grep -nE '^[[:space:]]*stage[[:space:]]+"' <<<"$below" | head -3 | grep -q .; then
    echo "$w: stages call stage directly. Wrap each stage in a function and call run_stage \"Name\" fn [done_fn]:"
    grep -nE '^[[:space:]]*stage[[:space:]]+"' <<<"$below" | head -3 | sed 's/^/    /'
    status=1
  fi
  if grep -niE '(say|step|note) .*(in another terminal|run .*README|README.*(step|section))' <<<"$below" | grep -q .; then
    echo "$w: a stage hands a check to the human as prose. Run the check in the stage, or call its script:"
    grep -niE '(say|step|note) .*(in another terminal|run .*README|README.*(step|section))' <<<"$below" | head -3 | sed 's/^/    /'
    status=1
  fi
done
exit $status
