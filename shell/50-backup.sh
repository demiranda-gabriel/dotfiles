# Backwards-compatible aliases over the gdrive-* scripts.
# Heavy lifting lives in ~/dotfiles/bin/. These wrappers only exist so the
# old muscle memory ("backup foo", "cloudsave name") keeps working.

backup()    { gdrive-push    "$@"; }
restore()   { gdrive-pull    "$@"; }
cloudsave() { gdrive-archive "$@"; }
