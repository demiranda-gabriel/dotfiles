#!/usr/bin/env bash
# Install tectonic (XeTeX-based PDF engine, bundles its own TeX, auto-fetches packages).
# Bypasses cluster TeX installs that are missing ucharcat.sty / xcolor.
set -euo pipefail

VERSION="0.16.9"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/tectonic"

if command -v tectonic >/dev/null 2>&1 && [[ -e "$LOCAL_BIN/tectonic" ]]; then
    echo "✓ tectonic already installed: $(command -v tectonic)"
    exit 0
fi

arch="$(uname -m)"
case "$arch" in
    x86_64) asset="tectonic-$VERSION-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) asset="tectonic-$VERSION-aarch64-unknown-linux-musl.tar.gz" ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"
echo "→ fetching tectonic $VERSION"
curl -sL -o tectonic.tar.gz "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%40$VERSION/$asset"
tar xzf tectonic.tar.gz
rm -f tectonic.tar.gz
ln -sf "$SOFTWARE/tectonic" "$LOCAL_BIN/tectonic"
echo "✓ tectonic installed: $("$LOCAL_BIN/tectonic" --version)"
echo "  (first run downloads TeX packages to ~/.cache/Tectonic/ — needs internet)"
