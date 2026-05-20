#!/usr/bin/env bash
# Install termpdf.py (dsanson/termpdf.py) + Python dependencies.
# Tracks master branch (script changes rarely; pin commit if needed).
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
TARGET="$LOCAL_BIN/termpdf"
URL="https://raw.githubusercontent.com/dsanson/termpdf.py/master/termpdf.py"

mkdir -p "$LOCAL_BIN"

if [[ ! -e "$TARGET" ]]; then
    echo "→ fetching termpdf.py"
    curl -sL -o "$TARGET" "$URL"
    chmod +x "$TARGET"
    echo "✓ termpdf installed at $TARGET"
else
    echo "✓ termpdf already present at $TARGET"
fi

# Python deps (lazy-imported by termpdf.py).
DEPS=(pymupdf roman pyperclip pdfrw pagelabels pybtex pynvim)
echo "→ pip install --user (idempotent): ${DEPS[*]}"
pip install --user --quiet "${DEPS[@]}" 2>&1 | tail -5 || {
    echo "✗ pip install failed — check Python env"
    exit 1
}
echo "✓ termpdf Python deps satisfied"
