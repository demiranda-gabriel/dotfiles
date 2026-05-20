#!/usr/bin/env bash
# Install newer pandoc statically. System pandoc on RHEL/Rocky 8 is often 2.0.x
# which lacks --pdf-engine=tectonic support.
set -euo pipefail

VERSION="3.9.0.2"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/pandoc"
TARGET="$SOFTWARE/pandoc-$VERSION/bin/pandoc"

if [[ -e "$LOCAL_BIN/pandoc" ]] && [[ "$(readlink -f "$LOCAL_BIN/pandoc" 2>/dev/null)" == "$TARGET" ]]; then
    echo "✓ pandoc $VERSION already installed: $("$LOCAL_BIN/pandoc" --version | head -1)"
    exit 0
fi

arch="$(uname -m)"
case "$arch" in
    x86_64) asset="pandoc-$VERSION-linux-amd64.tar.gz" ;;
    aarch64|arm64) asset="pandoc-$VERSION-linux-arm64.tar.gz" ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"
echo "→ fetching pandoc $VERSION (~30MB, extracts ~150MB)"
curl -sL -o pandoc.tar.gz "https://github.com/jgm/pandoc/releases/download/$VERSION/$asset"
tar xzf pandoc.tar.gz
rm -f pandoc.tar.gz
ln -sf "$TARGET" "$LOCAL_BIN/pandoc"
echo "✓ pandoc installed: $("$LOCAL_BIN/pandoc" --version | head -1)"
