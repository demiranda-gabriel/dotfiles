#!/bin/bash
# Hold a CPU compute node for VSCode Remote-SSH.
# Run on a LOGIN node, inside tmux, so the allocation survives disconnects.
# Writes the granted node name to ~/.vscode_ssh_node ; the Mac-side ssh
# ProxyCommand reads that file and `nc`s straight to the node (no per-connection
# salloc, so VSCode's 15s ConnectTimeout never trips).
#
# Env overrides:
#   VSC_PART  partition    (default: test ; max 12h, CPU-only)
#   VSC_TIME  walltime      (default: 12:00:00)
#   VSC_MEM   memory        (default: 24G)
#   VSC_CPUS  cpus-per-task (default: 4)
set -euo pipefail

PART="${VSC_PART:-test}"
TIME="${VSC_TIME:-12:00:00}"
MEM="${VSC_MEM:-24G}"
CPUS="${VSC_CPUS:-4}"
NODEFILE="$HOME/.vscode_ssh_node"

cleanup() { rm -f "$NODEFILE"; echo "[vscode-ssh-alloc] released, removed $NODEFILE"; }
trap cleanup EXIT

exec salloc \
  --job-name=vscode-ssh \
  --partition="$PART" \
  --time="$TIME" \
  --cpus-per-task="$CPUS" \
  --mem="$MEM" \
  /bin/bash -c '
    echo "$SLURM_NODELIST" > "$HOME/.vscode_ssh_node"
    echo "[vscode-ssh-alloc] node=$SLURM_NODELIST job=$SLURM_JOB_ID time='"$TIME"'"
    echo "[vscode-ssh-alloc] connect VSCode to host fasrc-compute now. Ctrl-C here to release."
    exec sleep infinity'
