# Ensure ~/.local/bin (where bootstrap symlinks dotfiles scripts) is on PATH.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
