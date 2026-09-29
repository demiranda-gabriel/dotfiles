# Ensure ~/.local/bin (where bootstrap symlinks dotfiles scripts) is on PATH.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Standalone tmux (install/install-tmux.sh) as a PATH *fallback*. On Polaris
# ~/.local/bin/tmux -> /usr/bin/tmux, which exists on login nodes but not on
# compute nodes; there the symlink dangles, PATH lookup skips it, and this
# appended dir supplies tmux. Appended (not prepended) so login nodes keep the
# system tmux their long-lived hq/fleet servers run under — a different client
# version can fail to attach with a protocol mismatch.
_tmux_fallback="$HOME/software/tmux/squashfs-root/usr/bin"
if [ -x "$_tmux_fallback/tmux" ]; then
    case ":$PATH:" in
        *":$_tmux_fallback:"*) ;;
        *) export PATH="$PATH:$_tmux_fallback" ;;
    esac
fi
unset _tmux_fallback
