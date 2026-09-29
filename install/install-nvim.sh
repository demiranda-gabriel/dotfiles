#!/usr/bin/env bash
# Install neovim >= 0.12 plus what render-markdown.nvim needs to draw LaTeX:
# the pylatexenc converter (latex2text) and the tree-sitter latex parser.
# The config itself (config/nvim/) is linked by bootstrap.sh; the plugins it
# names are fetched by vim.pack on first start, which step 4 triggers.
set -euo pipefail

MIN_MINOR=12                      # vim.pack is new in 0.12
VERSION="v0.12.2"
LOCAL_BIN="$HOME/.local/bin"
SOFTWARE="$HOME/software"
SHARE="$HOME/.local/share/nvim-latex"
VENV="$SHARE/venv"
PARSER_DIR="$HOME/.local/share/nvim/site/parser"
mkdir -p "$LOCAL_BIN" "$SOFTWARE" "$SHARE"

nvim_ok() {  # $1 = nvim binary; true when it runs and is >= 0.MIN_MINOR
    local v
    v="$("$1" --version 2>/dev/null | head -1)" || return 1
    [[ "$v" =~ ^NVIM\ v0\.([0-9]+) ]] && (( BASH_REMATCH[1] >= MIN_MINOR ))
}

# 1. nvim. The upstream tarball needs glibc >= 2.34, so it fails on Rocky 8
#    (FASRC, 2.28) and SLES 15 (Polaris, 2.31). conda-forge builds against an
#    old glibc and runs on both, so fall back to a dedicated micromamba env.
if command -v nvim >/dev/null 2>&1 && nvim_ok nvim; then
    echo "✓ nvim already installed: $(command -v nvim) ($(nvim --version | head -1))"
else
    NVIM="$SOFTWARE/nvim-linux-x86_64/bin/nvim"
    if [[ "$(uname -m)" == x86_64 ]] && ! nvim_ok "$NVIM"; then
        echo "→ fetching nvim $VERSION release tarball"
        curl -sL "https://github.com/neovim/neovim/releases/download/$VERSION/nvim-linux-x86_64.tar.gz" \
            | tar xz -C "$SOFTWARE"
    fi
    if ! nvim_ok "$NVIM"; then
        echo "→ release binary does not run here (glibc too old); using conda-forge"
        ENV="$SOFTWARE/nvim-env"
        MM="$(command -v micromamba || command -v mamba || command -v conda || true)"
        [[ -n "$MM" ]] || { echo "✗ no micromamba/mamba/conda to install nvim from conda-forge"; exit 1; }
        [[ -x "$ENV/bin/nvim" ]] || "$MM" create -y -q -p "$ENV" -c conda-forge "nvim>=0.$MIN_MINOR"
        NVIM="$ENV/bin/nvim"
        nvim_ok "$NVIM" || { echo "✗ conda-forge nvim at $NVIM is not >= 0.$MIN_MINOR"; exit 1; }
    fi
    ln -sf "$NVIM" "$LOCAL_BIN/nvim"
    echo "✓ nvim installed: $LOCAL_BIN/nvim → $NVIM"
fi
NVIM_BIN="$(command -v nvim || echo "$LOCAL_BIN/nvim")"

# 2. latex2text in its own venv, so no project env can shadow it.
if [[ ! -x "$VENV/bin/latex2text" ]]; then
    echo "→ creating latex2text venv at $VENV"
    # stdlib venv: pylatexenc is pure python, so any python3 will do and
    # nothing needs downloading beyond the one wheel.
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check pylatexenc
fi
ln -sf "$VENV/bin/latex2text" "$LOCAL_BIN/latex2text"
echo '\alpha^2' | "$LOCAL_BIN/latex2text" >/dev/null && echo "✓ latex2text ready"

# 3. tree-sitter latex parser. nvim bundles markdown and markdown_inline but
#    not latex, and markdown_inline injects `latex` into every $...$ block;
#    render-markdown's latex handler runs on that injected tree. The grammar
#    repo ships no generated src/parser.c, so the tree-sitter CLI generates
#    one. Its npm build needs glibc >= 2.29, hence cargo.
if [[ -f "$PARSER_DIR/latex.so" ]]; then
    echo "✓ latex parser already at $PARSER_DIR/latex.so"
else
    TS="$(command -v tree-sitter || echo "$HOME/.cargo/bin/tree-sitter")"
    if [[ ! -x "$TS" ]] && command -v cargo >/dev/null 2>&1; then
        echo "→ cargo install tree-sitter-cli (a few minutes)"
        cargo install --quiet tree-sitter-cli --locked
        TS="$HOME/.cargo/bin/tree-sitter"
    fi
    if [[ ! -x "$TS" ]]; then
        echo "⚠ no tree-sitter CLI and no cargo — LaTeX will show as source."
        echo "  Install rust (https://rustup.rs), then re-run this script."
    else
        WORK="$(mktemp -d)"
        trap 'rm -rf "$WORK"' EXIT
        git clone --depth 1 --quiet https://github.com/latex-lsp/tree-sitter-latex "$WORK/latex"
        # nvim 0.12 loads ABI 13-15; pin 14 so a newer CLI default cannot
        # emit an ABI this nvim refuses.
        (cd "$WORK/latex" && "$TS" generate --abi 14 src/grammar.json)
        SRC=("$WORK/latex/src/parser.c")
        [[ -f "$WORK/latex/src/scanner.c" ]] && SRC+=("$WORK/latex/src/scanner.c")
        mkdir -p "$PARSER_DIR"
        cc -shared -fPIC -Os -I "$WORK/latex/src" -o "$PARSER_DIR/latex.so" "${SRC[@]}"
        echo "✓ built $PARSER_DIR/latex.so"
    fi
fi

# 4. Fetch the plugins named in init.lua (vim.pack installs missing ones on
#    startup). Only once the config is linked — bootstrap.sh does that first.
if [[ -e "$HOME/.config/nvim/init.lua" ]]; then
    "$NVIM_BIN" --headless +qa >/dev/null 2>&1 || true
    if "$NVIM_BIN" --headless +'lua io.write(tostring(pcall(require, "render-markdown")))' +qa 2>&1 | grep -q true; then
        echo "✓ render-markdown.nvim loads"
    else
        echo "⚠ render-markdown.nvim did not load — start nvim once and check :checkhealth"
    fi
else
    echo "⚠ ~/.config/nvim/init.lua missing — run ~/dotfiles/bootstrap.sh, then re-run this"
fi
