# Keep $XDG_RUNTIME_DIR pointing at a directory that exists.
#
# On ALCF login nodes systemd-logind deletes /run/user/$UID once your last
# logind session on the node ends, but the variable lives on in long-running
# shells and in the tmux server's global environment. Anything that puts a
# socket there then fails: `lf -remote` (lf's server socket), the VS Code IPC
# socket, and so on. When the inherited value is unset or dead, fall back to
# /tmp/xdg-$UID, the same fallback bin/vscode-login-tunnel.sh uses. Keep the
# path short: Unix socket paths are capped at 108 bytes.
__xdg_fix_runtime_dir() {
    local uid d
    uid=$(id -u)
    d=${XDG_RUNTIME_DIR:-}
    if [ -n "$d" ] && [ -d "$d" ] && [ -O "$d" ] && [ -w "$d" ]; then
        return 0
    fi
    d=/tmp/xdg-$uid
    if [ ! -d "$d" ]; then
        (umask 077 && mkdir -p "$d") 2>/dev/null || return 0
    fi
    # Refuse a directory someone else created or a symlink planted in /tmp.
    if [ -L "$d" ] || [ ! -O "$d" ]; then
        return 0
    fi
    chmod 700 "$d" 2>/dev/null
    export XDG_RUNTIME_DIR=$d
    # New tmux panes copy the server's global environment, which still holds
    # the dead path. Update it so they start correct too.
    if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
        tmux set-environment -g XDG_RUNTIME_DIR "$d" 2>/dev/null
    fi
}
__xdg_fix_runtime_dir
unset -f __xdg_fix_runtime_dir
