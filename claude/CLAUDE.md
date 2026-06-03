# User-scoped instructions

Loaded for every Claude Code session under this home directory,
regardless of project.

## Backup / cross-cluster data workflow

Bulk data (datasets, raw artefacts, run outputs that are too large for
git) lives on the **MIR-backup shared Google Drive** (research group)
under the layout
`mir-backup:Current_members/Gabriel/projects/<project>/<subpath>/<filename>`.
Code goes to GitHub; only files that need a durable off-cluster home go
to Drive. (`mir-backup:` is the shared Team drive; the legacy `gdrive:`
remote was the personal My Drive used before 2026-06-03.)

Three scripts implement the contract (installed by
`~/dotfiles/bootstrap.sh` into `~/.local/bin/`):

| Command          | Purpose                                                         |
|------------------|-----------------------------------------------------------------|
| `gdrive-push`    | `rclone copy` a path to `mir-backup:Current_members/Gabriel/projects/<proj>/<sub>/` |
| `gdrive-pull`    | inverse                                                         |
| `gdrive-archive` | tar + pigz a directory, upload, keep local by default (`--rm` to delete) |

Project name auto-resolves from `basename(git rev-parse --show-toplevel)`,
overridable via `-p` or `$PROJECT_NAME`. All three accept `-n` for
dry-run. Use dry-run first for anything large or when the destination
subpath is new.

Detailed policy (when to invoke, restore flow, ignore_list.txt rules)
lives in the `backup-to-gdrive` skill. The skill is the authoritative
source — this section is just a pointer.

The same dotfiles repo (`~/dotfiles`, `git@github.com:demiranda-gabriel/dotfiles.git`)
is the single source of truth across every cluster I work on. Run
`~/dotfiles/bootstrap.sh` once per cluster after cloning.

## Per-project `DATA_MANAGEMENT.md`

Every project root contains a `DATA_MANAGEMENT.md` that classifies every
top-level file and directory into exactly one of three categories:

- **git-tracked** — committed and synced with GitHub on the working branch.
- **gdrive-tracked** — bulk data under
  `mir-backup:Current_members/Gabriel/projects/<project>/<subpath>/`,
  moved with the `gdrive-push` / `gdrive-pull` / `gdrive-archive` scripts.
  Not committed.
- **local-only** — ephemeral, regenerable, or environment-specific. Not
  committed, not backed up.

Rules:

1. Anything listed in `.gitignore` is either gdrive-tracked or local-only.
2. Anything not in `.gitignore` is git-tracked.
3. When a new top-level entry appears, classify it in the same commit
   that introduces it.
4. Before deleting a local copy of a gdrive-tracked path, confirm a
   recent push exists (`gdrive-push -n` first).

When entering a project that lacks `DATA_MANAGEMENT.md`, create one by
listing `ls -A` at the project root, reading `.gitignore`, and grouping
entries under the three headings above.

## Terminal viewer stack (SSH + kitty workflow)

For reading documents and browsing files without leaving the terminal.
All wired up by `~/dotfiles/bootstrap.sh --viewers`.

| Tool       | Role                                                          | Source |
|------------|---------------------------------------------------------------|--------|
| `tmux`     | Terminal multiplexer. Config at `~/.config/tmux/tmux.conf` (+ legacy `~/.tmux.conf` symlink for tmux <3.1) | `nelsonenzo/tmux-appimage`, extracted (no FUSE needed) |
| `lf`       | File manager (replaces ranger). Config in `~/.config/lf/`     | binary, fetched |
| `md-view`  | Markdown → PDF (pandoc + tectonic) → termpdf. Env: `MDVIEW_FONTSIZE` (default `14pt`; valid `10|11|12|14|17|20`), `MDVIEW_ENGINE` (default `tectonic`) | `dotfiles/bin/` |
| `img-view` | `kitten icat` wrapper, fits image in terminal box, clears before display | `dotfiles/bin/` |
| `termpdf`  | Multi-page PDF / epub / djvu viewer using kitty graphics      | upstream py, fetched |
| `tectonic` | Modern XeTeX engine, bundles TeX, auto-fetches packages — bypasses incomplete cluster TeX | binary, fetched |
| `pandoc`   | Newer (3.9.0.2) — system pandoc on RHEL/Rocky 8 is too old for tectonic | binary, fetched |

**Inside `lf`:** `<enter>` dispatches by extension (md → md-view, pdf →
termpdf, image → img-view). `B`/`H` for big/huge font markdown, `P` for
first-page pdf peek, `yK` for kitty transfer download to local Mac, `R`
to reload config. Quit drops parent shell into last-visited dir.

**Cluster TeX caveat:** the system TeX install on FASRC (Rocky 8) is
incomplete — `xelatex`/`lualatex` missing `ucharcat.sty`, xcolor broken.
`md-view` defaults to `tectonic` to bypass this entirely. Don't try to
"fix" by switching to system pdflatex unless explicitly working ASCII-only.

## New-cluster recipe

```bash
git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh --viewers
source ~/.bashrc
```

That installs gdrive scripts, lf+viewer stack, shell snippets, Claude
skills, and symlinks this CLAUDE.md into `~/.claude/`. After that the
canonical references are:

- `~/dotfiles/README.md` — full repo doc
- `~/dotfiles/claude/skills/backup-to-gdrive/SKILL.md` — backup policy
- This file — global Claude instructions

Auto-memory at `~/.claude/projects/<dir-hash>/memory/` is **per-host and
not in the repo**. New cluster starts with empty memory; Claude rebuilds
it from observation.
