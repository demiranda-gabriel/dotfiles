# Keep the system terminfo database reachable.
# Some terminals (notably the VSCode integrated terminal) export a
# TERMINFO_DIRS that omits the system database; ncurses then honours that list
# verbatim and every curses program sees "missing or unsuitable terminal".
# Only append when TERMINFO_DIRS is already set — when it is unset, ncurses
# uses its own (correct) compiled-in search path.
#
# The AppImage tmux had the same symptom for a different reason (its bundled
# libncurses points at the build machine's terminfo dir); that is fixed in the
# ~/.local/bin/tmux wrapper written by install/install-tmux.sh, not here.
if [[ -n "${TERMINFO_DIRS:-}" && ":${TERMINFO_DIRS}:" != *":/usr/share/terminfo:"* ]]; then
    export TERMINFO_DIRS="${TERMINFO_DIRS}:/etc/terminfo:/usr/share/terminfo"
fi
