# Repair terminfo lookup for the AppImage tmux.
# Some terminals (notably the VSCode integrated terminal) launch with a
# TERMINFO_DIRS that doesn't include the system database, so `tmux a` fails
# with "missing or unsuitable terminal: xterm-256color". If the current TERM
# can't be resolved, prepend the standard system terminfo location.
if ! infocmp "$TERM" >/dev/null 2>&1; then
    export TERMINFO_DIRS="/usr/share/terminfo:${TERMINFO_DIRS}"
fi
