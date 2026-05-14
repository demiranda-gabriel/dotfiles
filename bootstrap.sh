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

# State flags consumed by the "Next steps" section.
BASHRC_CHANGED=0
RCLONE_MISSING=0
PIGZ_MISSING=0
GDRIVE_MISSING=0

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
    BASHRC_CHANGED=1
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

# 3b. Symlink user-scoped CLAUDE.md (always-loaded instructions)
CLAUDE_MD_SRC="$DOTFILES/claude/CLAUDE.md"
CLAUDE_MD_TARGET="$HOME/.claude/CLAUDE.md"
if [[ -f "$CLAUDE_MD_SRC" ]]; then
    if [[ -L "$CLAUDE_MD_TARGET" || -e "$CLAUDE_MD_TARGET" ]]; then
        if [[ "$(readlink -f "$CLAUDE_MD_TARGET" 2>/dev/null)" == "$CLAUDE_MD_SRC" ]]; then
            echo "✓ ~/.claude/CLAUDE.md already linked"
        else
            echo "⚠ $CLAUDE_MD_TARGET exists and points elsewhere — skipping"
        fi
    else
        ln -s "$CLAUDE_MD_SRC" "$CLAUDE_MD_TARGET"
        echo "✓ linked ~/.claude/CLAUDE.md → $CLAUDE_MD_SRC"
    fi
fi

# 4. Toolchain probe
echo
echo "=== Toolchain ==="
for tool in rclone pigz tar; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool: $(command -v "$tool")"
    else
        echo "✗ $tool: MISSING"
        case "$tool" in
            rclone) RCLONE_MISSING=1 ;;
            pigz)   PIGZ_MISSING=1 ;;
        esac
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
        GDRIVE_MISSING=1
    fi
else
    GDRIVE_MISSING=1  # can't even probe without rclone
fi

# 6. Next steps — render a checklist conditional on detected state.
echo
echo "=== Next steps ==="

step=1
say() { printf "  %d. %s\n" "$step" "$1"; step=$((step+1)); }

if (( BASHRC_CHANGED )); then
    say "Reload shell so PATH and aliases take effect:"
    echo "       source $BASHRC      # or just open a new terminal"
else
    say "Shell already wired up — nothing to reload."
fi

if (( RCLONE_MISSING )); then
    say "Install rclone (required for any gdrive operation):"
    echo "       # cluster-specific: module load rclone, dnf install rclone,"
    echo "       # or curl https://rclone.org/install.sh | sudo bash"
fi

if (( PIGZ_MISSING )); then
    say "Install pigz for faster gdrive-archive (gzip is used as fallback):"
    echo "       # e.g. dnf install pigz, apt install pigz, or skip for now"
fi

if (( GDRIVE_MISSING )); then
    say "Configure the 'gdrive' rclone remote:"
    echo "       rclone config        # n → name=gdrive → type=drive →"
    echo "       # use default OAuth client; on a headless cluster run"
    echo "       # 'rclone authorize drive' on a machine with a browser"
    echo "       # and paste the JSON token back here."
    echo "       Reference template: $DOTFILES/rclone/rclone.conf.example"
fi

if (( ! RCLONE_MISSING && ! GDRIVE_MISSING )); then
    say "Smoke-test the round trip:"
    echo "       echo hello > /tmp/_gdrive_smoke.txt"
    echo "       gdrive-push /tmp/_gdrive_smoke.txt _smoketest -p \$(whoami)-smoke -n   # dry-run first"
    echo "       gdrive-push /tmp/_gdrive_smoke.txt _smoketest -p \$(whoami)-smoke"
    echo "       gdrive-pull _smoketest/_gdrive_smoke.txt /tmp/_back -p \$(whoami)-smoke"
    echo "       diff /tmp/_gdrive_smoke.txt /tmp/_back/_gdrive_smoke.txt"
fi

say "Open a Claude Code session anywhere — the 'backup-to-gdrive' skill"
echo "       and ~/.claude/CLAUDE.md are now picked up globally."

echo
echo "Done."
