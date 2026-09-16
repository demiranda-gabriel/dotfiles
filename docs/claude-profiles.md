# Two Claude accounts on one cluster

Claude Code stores everything for one account under a single directory, the
*config home*, named by `CLAUDE_CONFIG_DIR`. Point a second invocation at a
second directory and you get a second, fully independent account on the same
machine. Verified on FASRC with Claude Code 2.1.273.

## Setup

```bash
claude-profile-init harvard     # creates ~/.claude-harvard, records the name
source ~/.bashrc                # picks up the claude-harvard alias
claude-harvard                  # then /login with the second account
```

`bootstrap.sh` re-runs `claude-profile-init` for every name in
`claude/profiles`, so committing that file is what replicates the profile to
the next cluster. On a brand-new cluster, launch the primary account once
before bootstrapping (or re-run `claude-profile-init <name>` afterwards) —
`settings.json` can only be shared once the primary profile has written one.

## What is separate, what is shared

The split is deliberate: anything tied to an *account* is separate, anything
tied to the *host* is shared.

| Separate (per profile)                       | Shared (symlinked) |
|----------------------------------------------|--------------------|
| `.credentials.json` — each account logs in    | `CLAUDE.md` → `dotfiles/claude/CLAUDE.md` |
| `.claude.json` — project trust, MCP servers, prompt history | `skills/*` → `dotfiles/claude/skills/*` |
| `config.json` — including any API key         | `settings.json` → `~/.claude/settings.json` |
| `projects/` — transcripts and `--resume`      | |
| `projects/<hash>/memory/` — auto-memory       | |
| `plugins/` — re-cloned per profile (~73 MB)   | |

`.claude.json` does **not** stay at `$HOME/.claude.json`; it moves inside the
config home, which is why the separation is complete rather than partial.

MCP OAuth grants live in `.claude.json`, so the second profile reconnects
Docs / Gmail / Drive / Slack once. Auto-memory does not carry over: the second
profile starts empty and rebuilds from observation, like a new cluster.

Sharing `settings.json` by symlink is safe because Claude Code rewrites
settings in place rather than by atomic rename — a write from either profile
follows the link instead of replacing it. Verified by adding a marketplace
from a profile whose `settings.json` was a symlink: the link survived and the
change landed in the target. The consequence is that it works both ways —
`/model` or a plugin toggle from either profile changes the other.

## Two traps

**`CLAUDE_CONFIG_DIR` must be absolute and must be set in the environment.**
Claude Code rejects a relative path (*"the configuration home
(CLAUDE_CONFIG_DIR) is not an absolute path"*) and, if it changes after
start-up, refuses to continue with *"set it in the shell, not a settings file,
and restart"*. It cannot go in `settings.json`.

**`command claude` bypasses the `claude` alias, not just a function.** So a
profile alias written as `CLAUDE_CONFIG_DIR=… command claude` silently drops
whatever the base alias adds — here `--dangerously-skip-permissions`, which
would mean permission prompts on the second profile only. `shell/30-claude.sh`
therefore spells the flag out. `command` is still needed: without it the base
alias re-expands and the flag appears twice.

## Adding or removing a profile

Adding: `claude-profile-init <name>`, then commit `claude/profiles`.
`shell/30-claude.sh` reads that same file for the alias list, so nothing else
needs editing. It reads the file rather than globbing `~/.claude-*` on purpose:
unrelated tools keep directories there too (`~/.claude-code-ui`), and those must
not become aliases that launch Claude against another tool's data.

Removing: delete the line from `claude/profiles`, then `rm -rf
~/.claude-<name>` on each cluster. Nothing else references it.

## Disk

A profile costs roughly what the primary does: ~73 MB of plugin cache plus
transcripts, which reach ~80 MB after a few months of daily use. Keep them in
`$HOME` — scratch filesystems get purged.
