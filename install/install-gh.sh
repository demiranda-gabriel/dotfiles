#!/usr/bin/env bash
# Install the GitHub CLI (gh). Single static Go binary + man pages.
#
# Needed for anything the git remote cannot do over SSH: changing a
# repository's default branch, PR/issue work, and API calls that would
# otherwise require hand-managing a token. Auth is per-cluster and
# interactive (`gh auth login`) — the credential lands in
# ~/.config/gh/hosts.yml and is NOT part of the dotfiles repo.
set -euo pipefail

VERSION="2.100.0"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software/gh"

if command -v gh >/dev/null 2>&1 && [[ -e "$LOCAL_BIN/gh" ]]; then
    echo "✓ gh already installed: $(command -v gh) ($(gh --version | head -1))"
    exit 0
fi

arch="$(uname -m)"
case "$arch" in
    x86_64) asset="gh_${VERSION}_linux_amd64.tar.gz"; dir="gh_${VERSION}_linux_amd64" ;;
    aarch64|arm64) asset="gh_${VERSION}_linux_arm64.tar.gz"; dir="gh_${VERSION}_linux_arm64" ;;
    *) echo "✗ unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$SOFTWARE" "$LOCAL_BIN"
cd "$SOFTWARE"
echo "→ fetching gh $VERSION ($asset)"
curl -sL -o gh.tar.gz "https://github.com/cli/cli/releases/download/v${VERSION}/${asset}"
tar xzf gh.tar.gz
rm -f gh.tar.gz
ln -sf "$SOFTWARE/$dir/bin/gh" "$LOCAL_BIN/gh"

# Man pages, if the user keeps a private MANPATH tree.
if [[ -d "$SOFTWARE/$dir/share/man/man1" ]]; then
    mkdir -p "$HOME/.local/share/man/man1"
    cp -f "$SOFTWARE/$dir"/share/man/man1/*.1 "$HOME/.local/share/man/man1/" 2>/dev/null || true
fi

echo "✓ gh installed: $("$LOCAL_BIN/gh" --version | head -1)"
echo "  authenticate with: gh auth login"
