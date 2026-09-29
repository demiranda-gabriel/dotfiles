#!/usr/bin/env bash
# Install the external tools behind config/nvim/init.lua's Python setup.
#
#   tree-sitter CLI   nvim-treesitter (main branch) compiles parsers with it;
#                     falls back to install/tree-sitter-shim on old glibc
#   ripgrep           fzf-lua live grep; the `rg` on these hosts is otherwise
#                     only Claude Code's shell function, absent in nvim's jobs
#   basedpyright      Python language server: go-to-definition, hover, types
#   ruff              Python linter + formatter, also served over LSP
#
# No node is needed anywhere: basedpyright's PyPI wheel bundles its own node
# runtime, and `uv tool install` fetches a managed Python (the system python3
# on these clusters is 3.6). Each tool is version-pinned and upgraded in place
# when its version below is bumped.
set -euo pipefail

TS_VERSION="v0.27.0"
RG_VERSION="15.2.0"
BASEDPYRIGHT_VERSION="1.40.1"
RUFF_VERSION="0.16.9"

LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software"
mkdir -p "$LOCAL_BIN" "$SOFTWARE"

case "$(uname -m)" in
    x86_64)        ts_arch=x64;   rg_triple=x86_64-unknown-linux-musl ;;
    aarch64|arm64) ts_arch=arm64; rg_triple=aarch64-unknown-linux-gnu ;;
    *) echo "✗ unsupported arch: $(uname -m)"; exit 1 ;;
esac

# --- tree-sitter CLI ---
# Upstream binaries need glibc 2.39 (Polaris has 2.38, FASRC 2.28). Try the
# real one; if it cannot run on this host, link the gcc shim instead, which
# covers `tree-sitter build` — all nvim-treesitter needs for python and most
# other grammars.
SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tree-sitter-shim"
have="$("$LOCAL_BIN/tree-sitter" --version 2>/dev/null | awk '{print "v"$2}' || true)"
if [[ "$have" == "$TS_VERSION" ]]; then
    echo "✓ tree-sitter $TS_VERSION already installed"
elif [[ "$(readlink -f "$LOCAL_BIN/tree-sitter" 2>/dev/null)" == "$SHIM" && -z "${TS_RETRY:-}" ]]; then
    echo "✓ tree-sitter gcc shim already linked (TS_RETRY=1 retries the prebuilt)"
else
    echo "→ fetching tree-sitter $TS_VERSION"
    rm -f "$LOCAL_BIN/tree-sitter"
    tmp="$SOFTWARE/tree-sitter-${TS_VERSION}"
    curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${TS_VERSION}/tree-sitter-linux-${ts_arch}.gz" \
        | gunzip > "$tmp"
    chmod +x "$tmp"
    if "$tmp" --version >/dev/null 2>&1; then
        ln -sf "$tmp" "$LOCAL_BIN/tree-sitter"
        echo "✓ $("$LOCAL_BIN/tree-sitter" --version)"
    else
        rm -f "$tmp"
        ln -sf "$SHIM" "$LOCAL_BIN/tree-sitter"
        echo "✓ tree-sitter: prebuilt needs a newer glibc; linked gcc shim ($SHIM)"
    fi
fi

# --- ripgrep (static musl build on x86_64) ---
have="$("$LOCAL_BIN/rg" --version 2>/dev/null | head -1 | awk '{print $2}' || true)"
if [[ "$have" == "$RG_VERSION" ]]; then
    echo "✓ ripgrep $RG_VERSION already installed"
else
    echo "→ fetching ripgrep $RG_VERSION"
    dir="ripgrep-${RG_VERSION}-${rg_triple}"
    rm -rf "$SOFTWARE/$dir"
    curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/${dir}.tar.gz" \
        | tar xz -C "$SOFTWARE"
    ln -sf "$SOFTWARE/$dir/rg" "$LOCAL_BIN/rg"
    echo "✓ $("$LOCAL_BIN/rg" --version | head -1)"
fi

# --- Python language tools via uv (isolated venvs under uv's tool dir) ---
if ! command -v uv >/dev/null 2>&1; then
    echo "✗ uv not on PATH — cannot install basedpyright/ruff"
    exit 1
fi
uv tool install --quiet "basedpyright==${BASEDPYRIGHT_VERSION}"
uv tool install --quiet "ruff==${RUFF_VERSION}"
echo "✓ $(basedpyright --version 2>/dev/null | head -1)"
echo "✓ $(ruff --version)"
