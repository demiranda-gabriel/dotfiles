#!/bin/bash
# Serve a VS Code Remote Tunnel from an ALCF LOGIN node (Polaris / Aurora).
# Login nodes have direct outbound internet, so no proxy is needed: `code
# tunnel` registers with Microsoft, and your local VS Code ("Remote - Tunnels"
# in the desktop app, or vscode.dev in a browser) connects by selecting this
# machine from the list. See docs/alcf-vscode-tunnel.md for the full workflow.
#
# Run inside a detached tmux session so it survives SSH disconnects — use the
# `vscode-tunnel` launcher, or by hand:
#     tmux new -s vscode -d vscode-login-tunnel.sh
#
# First run triggers a GitHub device-code login (prints a URL + code to open on
# your laptop); the credential then caches under the CLI data dir for next time.
set -uo pipefail
export VSCODE_CLI_DISABLE_KEYCHAIN_ENCRYPT=1   # no system keychain on clusters
CODE="$HOME/.local/bin/code"

# Per-node CLI data dir. ALCF login nodes share $HOME over Lustre, but
# `code tunnel` keeps exactly ONE singleton lock + ONE machine registration per
# data dir. With the default shared dir all login nodes look like one machine:
# a tunnel started on a second node can't seize the first node's lock (the
# holder pid is alive on another host, so it looks dead but un-takeable) and
# loops "access singleton" forever, while the registered name flip-flops between
# whichever node last ran `code tunnel`. A dir per node makes each node's tunnel
# fully independent, so it always comes up cleanly and its name matches the node.
export VSCODE_CLI_DATA_DIR="${VSCODE_CLI_DATA_DIR:-$HOME/.vscode/cli-$(hostname -s)}"

# First run on a node: seed auth from the legacy shared dir so you don't redo
# the GitHub device-code login on every login node.
if [[ ! -f "$VSCODE_CLI_DATA_DIR/token.json" && -f "$HOME/.vscode/cli/token.json" ]]; then
  mkdir -p "$VSCODE_CLI_DATA_DIR"
  cp -p "$HOME/.vscode/cli/token.json" "$HOME/.vscode/cli/agent-host-token" \
        "$VSCODE_CLI_DATA_DIR/" 2>/dev/null || true
fi

# Tunnel/machine name. Defaults to <cluster>-<node-number> derived from the
# hostname (polaris-login-01 -> polaris-01, aurora-uan-0009 -> aurora-0009), so
# the machine list in VS Code never shows a stale or ambiguous entry. Override
# by passing an explicit name as $1.
host="$(hostname -s)"
num="$(printf '%s' "$host" | grep -oE '[0-9]+$' || true)"
NAME="${1:-${host%%-*}${num:+-$num}}"

# ALCF login-node cgroup: 8 cores, 8 GB, pids.max=256 per user (pids count
# THREADS). Pinning to 8 CPUs costs nothing (the cgroup throttles to 8 cores
# regardless) but stops tokio/node from sizing thread pools to the hundreds of
# hardware cores — the thing that blows the 256-pid cap and makes
# fork()/pthread_create() fail in every other session (Claude agents included).
PIN="taskset -c 0-7"

if [[ ! -x "$CODE" ]]; then
  echo "[vscode-login-tunnel] '$CODE' not found — install it with:" >&2
  echo "    ~/dotfiles/install/install-vscode-cli.sh" >&2
  exit 1
fi

# 'user login' always starts a fresh device-code flow, so only run it when
# there is no cached credential (~/.vscode-cli lives in home).
if ! $PIN "$CODE" tunnel user show >/dev/null 2>&1; then
  $PIN "$CODE" tunnel user login --provider github
fi
$PIN "$CODE" tunnel --accept-server-license-terms --name "$NAME"

# Keep the pane alive if the tunnel ever exits, so its output stays inspectable.
echo "[vscode-login-tunnel] tunnel process exited; dropping to a shell."
exec bash -l
