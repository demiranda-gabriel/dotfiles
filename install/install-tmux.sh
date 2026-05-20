#!/usr/bin/env bash
# Install tmux from nelsonenzo/tmux-appimage static build.
# AppImage is extracted (--appimage-extract) so FUSE is not required —
# HPC compute nodes typically disable FUSE.
set -euo pipefail

VERSION="3.5a"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/tmux"

if command -v tmux >/dev/null 2>&1 && [[ -e "$LOCAL_BIN/tmux" ]]; then
    echo "✓ tmux already installed: $(command -v tmux) ($(tmux -V))"
    exit 0
fi

arch="$(uname -m)"
case "$arch" in
    x86_64) ;;
    aarch64|arm64)
        echo "✗ tmux-appimage has no arm64 build."
        echo "  Install via your cluster's package manager, or:"
        echo "    micromamba install -n base -c conda-forge tmux"
        exit 1
        ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"

url="https://github.com/nelsonenzo/tmux-appimage/releases/download/${VERSION}/tmux.appimage"
echo "→ fetching tmux $VERSION AppImage"
curl -fsSL -o tmux.appimage "$url"
chmod +x tmux.appimage

# Extract: FUSE is unavailable on most cluster compute nodes.
rm -rf squashfs-root
./tmux.appimage --appimage-extract >/dev/null
rm -f tmux.appimage

inner="$SOFTWARE/squashfs-root/usr/bin/tmux"
if [[ ! -x "$inner" ]]; then
    echo "✗ extracted AppImage missing $inner"
    exit 1
fi

ln -sf "$inner" "$LOCAL_BIN/tmux"
echo "✓ tmux installed: $("$LOCAL_BIN/tmux" -V)"
