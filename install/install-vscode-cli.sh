#!/usr/bin/env bash
# Install the VS Code CLI — the standalone tunnel/serve client behind the
# login-node remote-tunnel workflow (see docs/alcf-vscode-tunnel.md).
#
# It installs as ~/.local/bin/code-tunnel-cli, NOT as `code`: that binary
# cannot open a file in an attached window (it looks for a *desktop* VS Code
# and reports "No installation of Visual Studio Code stable was found").
# ~/.local/bin/code is bin/code, the wrapper that dispatches file opens to
# the running server's remote-cli and subcommands here.
# Alpine static build: a single self-contained binary with no glibc version
# coupling, so the same artefact runs on Rocky 8 (Polaris) and SLES (Aurora).
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/vscode-cli"

if [[ -x "$LOCAL_BIN/code-tunnel-cli" ]]; then
    echo "✓ VS Code CLI already installed: $LOCAL_BIN/code-tunnel-cli"
    exit 0
fi

arch="$(uname -m)"
case "$arch" in
    x86_64)        os="cli-alpine-x64" ;;
    aarch64|arm64) os="cli-alpine-arm64" ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"
echo "→ fetching VS Code CLI ($os)"
curl -sL -o code.tar.gz "https://code.visualstudio.com/sha/download?build=stable&os=$os"
tar xzf code.tar.gz          # yields a single 'code' binary
rm -f code.tar.gz
chmod +x code
ln -sf "$SOFTWARE/code" "$LOCAL_BIN/code-tunnel-cli"
echo "✓ VS Code CLI installed: $("$LOCAL_BIN/code-tunnel-cli" --version | head -1)"
echo "  Start a login-node tunnel with:  vscode-tunnel   (docs/alcf-vscode-tunnel.md)"
