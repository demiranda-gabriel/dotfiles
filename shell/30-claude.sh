#!/usr/bin/env bash
# Claude Code aliases: the primary account, plus one alias per extra profile.
#
# The primary account uses Claude Code's default config home (~/.claude).
# Additional accounts live in ~/.claude-<name>, created by
# `claude-profile-init <name>`. Each one gets a `claude-<name>` alias below,
# so adding a profile needs no edit here — only a line in claude/profiles.
#
# CLAUDE_CONFIG_DIR must be an absolute path and must be set in the
# environment: Claude Code rejects a relative path outright, and warns and
# asks for a restart if it changes after start-up, so it cannot live in
# settings.json. The alias bakes in the expanded $HOME for that reason.
#
# `command` is not decoration — it suppresses the `claude` alias below, which
# would otherwise re-expand inside the profile alias and duplicate the flag.

command -v claude >/dev/null 2>&1 || return 0

alias claude='command claude --dangerously-skip-permissions'
alias cld='tmux new -A -s claude "claude agents; exec bash"'

# Profiles come from claude/profiles, never from globbing ~/.claude-*: other
# tools keep directories there too (~/.claude-code-ui), and those must not
# turn into aliases that launch Claude against someone else's data.
_cc_list="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/claude/profiles"
if [[ -r "$_cc_list" ]]; then
    while read -r _cc_name; do
        _cc_name="${_cc_name%%#*}"
        _cc_name="${_cc_name//[[:space:]]/}"
        [[ -n "$_cc_name" && -d "$HOME/.claude-$_cc_name" ]] || continue
        alias "claude-$_cc_name"="CLAUDE_CONFIG_DIR='$HOME/.claude-$_cc_name' command claude --dangerously-skip-permissions"
    done < "$_cc_list"
fi
unset _cc_list _cc_name
