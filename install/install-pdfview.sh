#!/usr/bin/env bash
# Install the terminal document viewers: a dedicated Python venv holding
# PyMuPDF (plus the extras termpdf lazy-imports), and upstream termpdf.py.
#
# The venv exists because both viewers used to run under `#!/usr/bin/env
# python3`, which resolves to whatever project venv happens to be active. The
# deps were installed into one interpreter's user-site, so activating any
# project venv broke PDF viewing with ModuleNotFoundError: fitz. Pinning an
# interpreter that nothing else touches removes that failure mode.
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/pdfview"
VENV="$SHARE/venv"
TERMPDF_PY="$SHARE/termpdf.py"
URL="https://raw.githubusercontent.com/dsanson/termpdf.py/master/termpdf.py"
DEPS=(pymupdf roman pyperclip pdfrw pagelabels pybtex pynvim)

mkdir -p "$SHARE" "$LOCAL_BIN"

# 1. Venv. uv is much faster and is already part of the stack; fall back to
#    the stdlib module on a host without it.
if [[ ! -x "$VENV/bin/python" ]]; then
    echo "→ creating viewer venv at $VENV"
    if command -v uv >/dev/null 2>&1; then
        uv venv --python 3.12 "$VENV" >/dev/null
    else
        python3 -m venv "$VENV"
    fi
fi

echo "→ installing viewer deps: ${DEPS[*]}"
if command -v uv >/dev/null 2>&1; then
    VIRTUAL_ENV="$VENV" uv pip install --quiet "${DEPS[@]}"
else
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet "${DEPS[@]}"
fi

"$VENV/bin/python" -c 'import fitz' || {
    echo "✗ PyMuPDF not importable in $VENV"
    exit 1
}
echo "✓ viewer venv ready ($("$VENV/bin/python" -V))"

# 2. Upstream termpdf.py, kept out of ~/.local/bin so the tracked wrapper can
#    own that name.
if [[ ! -s "$TERMPDF_PY" ]]; then
    echo "→ fetching termpdf.py"
    curl -sL -o "$TERMPDF_PY" "$URL"
    chmod +x "$TERMPDF_PY"
fi
echo "✓ termpdf.py at $TERMPDF_PY"

# 3. Retire an old install: bootstrap.sh refuses to replace a real file with
#    its symlink, so move the pre-wrapper copy aside.
OLD="$LOCAL_BIN/termpdf"
if [[ -f "$OLD" && ! -L "$OLD" ]]; then
    if head -1 "$OLD" | grep -q 'python'; then
        mv "$OLD" "$OLD.pre-wrapper.bak"
        echo "✓ moved the old ~/.local/bin/termpdf aside (.pre-wrapper.bak)"
    fi
fi

# 4. Drop any stale interpreter choice cached by doc-view.
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/doc-view/python"

echo "✓ done — run ~/dotfiles/bootstrap.sh to link doc-view and termpdf"
