#!/usr/bin/env bash
# Bootstrap this dotfiles checkout on the current cluster.
#
#   git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
#   ~/dotfiles/bootstrap.sh
#
# Idempotent: safe to re-run.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
CLAUDE_SKILLS="$HOME/.claude/skills"
BASHRC="$HOME/.bashrc"
SOURCE_LINE="for f in $DOTFILES/shell/*.sh; do source \"\$f\"; done  # dotfiles"

echo "=== Bootstrapping dotfiles from $DOTFILES ==="

# 1. Symlink scripts into ~/.local/bin
mkdir -p "$LOCAL_BIN"
for src in "$DOTFILES"/bin/*; do
    [[ -f "$src" ]] || continue
    chmod +x "$src"
    target="$LOCAL_BIN/$(basename "$src")"
    if [[ -L "$target" || -e "$target" ]]; then
        if [[ "$(readlink -f "$target" 2>/dev/null)" == "$src" ]]; then
            echo "✓ $target already linked"
            continue
        fi
        echo "⚠ $target exists and points elsewhere — skipping"
        continue
    fi
    ln -s "$src" "$target"
    echo "✓ linked $target → $src"
done

# 2. Wire shell/* into ~/.bashrc
if ! grep -qF "# dotfiles" "$BASHRC" 2>/dev/null; then
    printf '\n# Source dotfiles shell snippets (added by bootstrap.sh)\n%s\n' "$SOURCE_LINE" >> "$BASHRC"
    echo "✓ appended source line to $BASHRC"
else
    echo "✓ $BASHRC already sources dotfiles"
fi

# 3. Symlink Claude skills
mkdir -p "$CLAUDE_SKILLS"
for src in "$DOTFILES"/claude/skills/*; do
    [[ -d "$src" ]] || continue
    target="$CLAUDE_SKILLS/$(basename "$src")"
    if [[ -L "$target" || -e "$target" ]]; then
        if [[ "$(readlink -f "$target" 2>/dev/null)" == "$src" ]]; then
            echo "✓ skill $(basename "$src") already linked"
            continue
        fi
        echo "⚠ $target exists and points elsewhere — skipping"
        continue
    fi
    ln -s "$src" "$target"
    echo "✓ linked skill $(basename "$src")"
done

# 4. Toolchain probe
echo
echo "=== Toolchain ==="
for tool in rclone pigz tar; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool: $(command -v "$tool")"
    else
        echo "✗ $tool: MISSING (gdrive-archive will fall back to gzip if pigz absent; rclone is required)"
    fi
done

# 5. rclone remote probe
echo
echo "=== rclone remotes ==="
if command -v rclone >/dev/null 2>&1; then
    if rclone listremotes 2>/dev/null | grep -qx "gdrive:"; then
        echo "✓ remote 'gdrive:' configured"
    else
        echo "✗ remote 'gdrive:' NOT configured"
        echo "  Run: rclone config   # name the remote 'gdrive', type 'drive'"
        echo "  Template: $DOTFILES/rclone/rclone.conf.example"
    fi
else
    echo "✗ rclone missing — install it before continuing"
fi

echo
echo "Done. Open a new shell or 'source $BASHRC' to pick up PATH and aliases."
