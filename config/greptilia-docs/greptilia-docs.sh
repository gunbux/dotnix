# Switch which greptilia worktree the greptilia-docs launchd agent serves.
#   greptilia-docs            show what is being served
#   greptilia-docs <name>     serve a registered Git worktree
#   greptilia-docs main       serve ~/repo/greptilia
#   greptilia-docs --list     list worktrees as "<name><TAB><branch>" (used by completion)

main="$HOME/repo/greptilia"
link="${XDG_STATE_HOME:-$HOME/.local/state}/greptilia-docs/root"
label="gui/$(id -u)/org.nix-community.home.greptilia-docs"
log="$HOME/Library/Logs/greptilia-docs.log"

worktrees() {
  local entry wt
  while IFS= read -r -d '' entry; do
    if [[ "$entry" == worktree\ * ]]; then
      wt="${entry#worktree }"
      [[ "$wt" != "$main" && -d "$wt" ]] && printf '%s\n' "$wt"
    fi
  done < <(git -C "$main" worktree list --porcelain -z)
}

describe() {
  local root="$1" name
  if [[ "$root" == "$main" ]]; then name=main; else name="${root##*/}"; fi
  echo "$name ($(git -C "$root" branch --show-current 2>/dev/null || echo detached)) $root"
}

case "${1:-}" in
  "")
    root="$(readlink "$link" 2>/dev/null || true)"
    [[ -d "$root/docs" ]] || root="$main"
    echo "Serving $(describe "$root")"
    echo "http://localhost:3333  logs: $log"
    exit 0
    ;;
  --list)
    while read -r wt; do
      printf '%s\t%s\n' "${wt##*/}" "$(git -C "$wt" branch --show-current 2>/dev/null)"
    done < <(worktrees)
    exit 0
    ;;
  -h | --help)
    echo "usage: greptilia-docs [<worktree> | main | --list]"
    echo "Switch which greptilia worktree http://localhost:3333 serves."
    echo "With no argument, show what is being served."
    exit 0
    ;;
  main)
    root="$main"
    ;;
  *)
    mapfile -t matches < <(worktrees | grep "/$1\$" || true)
    if ((${#matches[@]} == 0)); then
      echo "greptilia-docs: no registered greptilia worktree named '$1'" >&2
      echo "Run 'greptilia-docs --list' to see the available worktrees." >&2
      exit 1
    elif ((${#matches[@]} > 1)); then
      echo "greptilia-docs: '$1' matches more than one worktree:" >&2
      printf '  %s\n' "${matches[@]}" >&2
      exit 1
    fi
    root="${matches[0]}"
    ;;
esac

if [[ ! -d "$root/docs" ]]; then
  echo "greptilia-docs: $root has no docs/ directory" >&2
  exit 1
fi

mkdir -p "$(dirname "$link")"
if [[ "$root" == "$main" ]]; then rm -f "$link"; else ln -sfn "$root" "$link"; fi
launchctl kickstart -k "$label"

echo "Serving $(describe "$root")"
echo "http://localhost:3333 (first start runs bun install)  logs: $log"
