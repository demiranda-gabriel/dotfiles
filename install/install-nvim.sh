#!/usr/bin/env bash
# Install Neovim from the upstream static release tarball.
#
# The tarball is used rather than the AppImage on purpose: AppImages need FUSE,
# which HPC compute nodes routinely disable (see install-tmux.sh, which has to
# work around exactly that with --appimage-extract). The tarball has no such
# dependency, so the same binary works on login and compute nodes alike.
#
# nvim finds its runtime files relative to its own resolved executable path, so
# the symlink into ~/.local/bin must point at the binary *inside* the extracted
# tree — moving or copying bin/nvim out on its own breaks :help, syntax and
# every bundled plugin.
set -euo pipefail

VERSION="v0.12.5"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/nvim"

# Version-aware guard: re-running after a VERSION bump upgrades in place.
# A bare "is it installed?" test would pin the host to whatever it first got.
if [[ -x "$LOCAL_BIN/nvim" ]]; then
    have="$("$LOCAL_BIN/nvim" --version 2>/dev/null | head -1 | awk '{print $2}')"
    if [[ "$have" == "$VERSION" ]]; then
        echo "✓ nvim $VERSION already installed: $LOCAL_BIN/nvim"
        exit 0
    fi
    echo "→ upgrading nvim ${have:-unknown} → $VERSION"
fi

arch="$(uname -m)"
case "$arch" in
    x86_64) asset="nvim-linux-x86_64.tar.gz"; dir="nvim-linux-x86_64" ;;
    aarch64|arm64) asset="nvim-linux-arm64.tar.gz"; dir="nvim-linux-arm64" ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"

echo "→ fetching nvim $VERSION ($asset)"
curl -fsSL -o nvim.tar.gz \
    "https://github.com/neovim/neovim/releases/download/${VERSION}/${asset}"

# Replace the old tree wholesale: extracting over it would leave runtime files
# from the previous version behind, which nvim would happily load.
rm -rf "$dir"
tar xzf nvim.tar.gz
rm -f nvim.tar.gz

inner="$SOFTWARE/$dir/bin/nvim"
if [[ ! -x "$inner" ]]; then
    echo "✗ extracted tarball missing $inner"
    exit 1
fi

ln -sf "$inner" "$LOCAL_BIN/nvim"
echo "✓ nvim installed: $("$LOCAL_BIN/nvim" --version | head -1)"
