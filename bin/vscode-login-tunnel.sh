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
# your laptop); the credential then caches under ~/.vscode-cli for next time.
set -uo pipefail
export VSCODE_CLI_DISABLE_KEYCHAIN_ENCRYPT=1   # no system keychain on clusters
CODE="$HOME/.local/bin/code"

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
