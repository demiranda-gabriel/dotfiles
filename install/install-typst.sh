#!/usr/bin/env bash
# Install typst, the engine md-view renders notes through (pandoc -> typst ->
# PDF -> doc-view). The musl build is fully static, so the same binary runs on
# Polaris (SLES 15) and FASRC (Rocky 8) regardless of their glibc. Bumping
# VERSION upgrades in place.
set -euo pipefail

# Pinned to 0.14.x on purpose: pandoc 3.9's typst writer still emits symbol
# names typst 0.15 removed (e.g. times.circle -> times.o), so under 0.15 any
# note with such a symbol fails and md-view drops to the slow tectonic path.
# 0.14 accepts them with a deprecation warning. Re-test before bumping.
VERSION="v0.14.2"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software"

have="$("$LOCAL_BIN/typst" --version 2>/dev/null | awk '{print "v"$2}' || true)"
if [[ "$have" == "$VERSION" ]]; then
    echo "✓ typst $VERSION already installed"
    exit 0
fi

case "$(uname -m)" in
    x86_64)        triple=x86_64-unknown-linux-musl ;;
    aarch64|arm64) triple=aarch64-unknown-linux-musl ;;
    *) echo "✗ unsupported arch: $(uname -m)"; exit 1 ;;
esac

dir="typst-${triple}"
mkdir -p "$SOFTWARE" "$LOCAL_BIN"
echo "→ fetching typst $VERSION"
rm -rf "$SOFTWARE/$dir"
curl -fsSL "https://github.com/typst/typst/releases/download/${VERSION}/${dir}.tar.xz" \
    | tar xJ -C "$SOFTWARE"
ln -sf "$SOFTWARE/$dir/typst" "$LOCAL_BIN/typst"
echo "✓ $("$LOCAL_BIN/typst" --version)"
