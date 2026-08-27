#!/usr/bin/env bash
set -euo pipefail

SESSION="main"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -n dotnix -c "$HOME/dotnix"
  tmux new-window -t "$SESSION" -n work -c "$HOME/repo"
  tmux new-window -t "$SESSION" -n herald -c "$HOME" herald
  tmux select-window -t "$SESSION:dotnix"
fi

exec tmux attach-session -t "$SESSION"
