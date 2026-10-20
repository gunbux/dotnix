# Switch which greptilia worktree the greptilia-docs launchd agent serves.
#   greptilia-docs            show what is being served
#   greptilia-docs <name>     serve a Paseo worktree (~/.paseo/worktrees/*/<name>)
#   greptilia-docs main       serve ~/repo/greptilia
#   greptilia-docs --list     list worktrees as "<name><TAB><branch>" (used by completion)

main="$HOME/repo/greptilia"
link="${XDG_STATE_HOME:-$HOME/.local/state}/greptilia-docs/root"
label="gui/$(id -u)/org.nix-community.home.greptilia-docs"
log="$HOME/Library/Logs/greptilia-docs.log"

# Paseo worktrees whose .git file points back at the main greptilia checkout.
worktrees() {
  shopt -s nullglob
  local wt
  for wt in "$HOME"/.paseo/worktrees/*/*/; do
    wt="${wt%/}"
    [[ -f "$wt/.git" ]] && grep -q "^gitdir: $main/.git/worktrees/" "$wt/.git" && echo "$wt"
  done
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
      echo "greptilia-docs: no greptilia worktree named '$1' under ~/.paseo/worktrees" >&2
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
