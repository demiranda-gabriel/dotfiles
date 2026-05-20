#!/usr/bin/env bash
# Install lf (terminal file manager). Single Go binary.
set -euo pipefail

VERSION="r41"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/lf"

if command -v lf >/dev/null 2>&1 && [[ -e "$LOCAL_BIN/lf" ]]; then
    echo "✓ lf already installed: $(command -v lf)"
    exit 0
fi

arch="$(uname -m)"
case "$arch" in
    x86_64) asset="lf-linux-amd64.tar.gz" ;;
    aarch64|arm64) asset="lf-linux-arm64.tar.gz" ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"
echo "→ fetching lf $VERSION ($asset)"
curl -sL -o lf.tar.gz "https://github.com/gokcehan/lf/releases/download/$VERSION/$asset"
tar xzf lf.tar.gz
rm -f lf.tar.gz
ln -sf "$SOFTWARE/lf" "$LOCAL_BIN/lf"
echo "✓ lf installed: $("$LOCAL_BIN/lf" -version)"
