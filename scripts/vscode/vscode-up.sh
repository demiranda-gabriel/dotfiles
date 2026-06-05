#!/bin/bash
# Convenience launcher: (re)start the VSCode alloc inside a detached tmux
# session named 'vscode' on this login node. Idempotent.
#
#   vscode-up.sh          # start/attach
#   vscode-up.sh status   # show node + job
#   vscode-up.sh down     # cancel allocation + kill tmux session
set -euo pipefail
SESS=vscode
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOC="$DIR/vscode-ssh-alloc.sh"
NODEFILE="$HOME/.vscode_ssh_node"

case "${1:-up}" in
  status)
    if [[ -s "$NODEFILE" ]]; then echo "node: $(cat "$NODEFILE")"; else echo "node: (none)"; fi
    squeue -u "$USER" --name=vscode-ssh -o "%i %j %N %T %L" 2>/dev/null
    tmux has-session -t "$SESS" 2>/dev/null && echo "tmux '$SESS': running" || echo "tmux '$SESS': absent"
    ;;
  down)
    scancel --name=vscode-ssh -u "$USER" 2>/dev/null || true
    tmux kill-session -t "$SESS" 2>/dev/null || true
    rm -f "$NODEFILE"
    echo "vscode alloc + tmux session torn down."
    ;;
  up)
    if tmux has-session -t "$SESS" 2>/dev/null; then
      echo "tmux '$SESS' already running. Attach: tmux attach -t $SESS"
    else
      tmux new-session -d -s "$SESS" "bash '$ALLOC'"
      echo "Started tmux '$SESS'. Waiting for node allocation..."
      for i in $(seq 1 60); do
        [[ -s "$NODEFILE" ]] && { echo "node: $(cat "$NODEFILE")"; break; }
        sleep 2
      done
      [[ -s "$NODEFILE" ]] || echo "Still pending after 120s; check: tmux attach -t $SESS"
    fi
    ;;
  *) echo "usage: vscode-up.sh [up|status|down]"; exit 1 ;;
esac
