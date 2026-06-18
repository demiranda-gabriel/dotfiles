#!/usr/bin/env bash
# Install the VS Code CLI ('code') — the standalone tunnel/serve client behind
# the login-node remote-tunnel workflow (see docs/alcf-vscode-tunnel.md).
# Alpine static build: a single self-contained binary with no glibc version
# coupling, so the same artefact runs on Rocky 8 (Polaris) and SLES (Aurora).
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/vscode-cli"

if command -v code >/dev/null 2>&1 && [[ -e "$LOCAL_BIN/code" ]]; then
    echo "✓ VS Code CLI already installed: $(command -v code)"
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
ln -sf "$SOFTWARE/code" "$LOCAL_BIN/code"
echo "✓ VS Code CLI installed: $("$LOCAL_BIN/code" --version | head -1)"
echo "  Start a login-node tunnel with:  vscode-tunnel   (docs/alcf-vscode-tunnel.md)"
