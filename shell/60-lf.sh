# lf integration: editor + cd-on-exit wrapper.

# Prefer nvim if installed, fallback to vim.
if command -v nvim >/dev/null 2>&1; then
    export EDITOR=nvim
    export VISUAL=nvim
elif command -v vim >/dev/null 2>&1; then
    export EDITOR=vim
    export VISUAL=vim
fi

# `lf` wrapped so quitting drops parent shell into last-visited directory.
lfcd () {
    local tmp dir
    tmp="$(mktemp)"
    command lf -last-dir-path="$tmp" "$@"
    if [[ -f "$tmp" ]]; then
        dir="$(cat "$tmp")"
        rm -f "$tmp"
        [[ -d "$dir" && "$dir" != "$PWD" ]] && cd "$dir"
    fi
}
alias lf='lfcd'
