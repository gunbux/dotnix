#!/usr/bin/env bash
# Add the template's context sections to a new sprint or subgoal.
# Usage: seed.sh sprint            (the sprint in $SPRINT, or the only open one)
#        seed.sh subgoal <key>
# Sections that already exist are left alone (--if-missing).
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
scope=${1:?usage: seed.sh sprint | seed.sh subgoal <key>}
sub=${2:-}
case $scope in
  sprint) scope_args=() ;;
  subgoal) [[ -n $sub ]] || { echo "usage: seed.sh subgoal <key>" >&2; exit 2; }; scope_args=(--subgoal "$sub") ;;
  *) echo "usage: seed.sh sprint | seed.sh subgoal <key>" >&2; exit 2 ;;
esac
now="$(TZ=Asia/Singapore date '+%Y-%m-%d %H:%M') SGT"
for f in "$dir/$scope"/*.md; do
  name=$(basename "$f" .md)
  key=${name#*-}
  title=$(head -n 1 "$f" | sed 's/^# //')
  tail -n +3 "$f" | sed "s/{{now}}/$now/g" \
    | sprint context set "$key" --title "$title" "${scope_args[@]}" --if-missing --file -
done
