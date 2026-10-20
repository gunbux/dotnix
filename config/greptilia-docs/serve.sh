# Run by the greptilia-docs launchd agent. Serves the worktree that
# `greptilia-docs` linked, or the main checkout if the link is unset or stale.

main="$HOME/repo/greptilia"
link="${XDG_STATE_HOME:-$HOME/.local/state}/greptilia-docs/root"

root="$(readlink "$link" 2>/dev/null || true)"
[[ -d "$root/docs" ]] || root="$main"

echo "greptilia-docs: serving $root"
cd "$root/docs"
bun install --frozen-lockfile
exec bun run dev
