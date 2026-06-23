# dotfiles

Cross-cluster shell utilities and Claude Code skills. Single source of
truth for the backup workflow that mirrors bulk project data to Google
Drive.

## Bootstrap on a new cluster

```bash
git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

The bootstrap script is idempotent. It:

1. Symlinks every file in `bin/` into `~/.local/bin/`.
2. Appends a `source ~/dotfiles/shell/*.sh` line to `~/.bashrc` (only if
   absent).
3. Symlinks `claude/skills/*` into `~/.claude/skills/`.
4. Per-file symlinks `config/<app>/*` into `~/.config/<app>/` (currently
   `lf`, `tmux`). For `tmux` also creates `~/.tmux.conf` as a fallback
   for tmux <3.1 (which doesn't honor the XDG path).
5. Probes for `rclone`, `pigz`, `tmux`, `lf`, `tectonic`, `pandoc`,
   `termpdf`, `pdftoppm`, and a configured `mir-backup:` remote; reports missing.

Pass `--viewers` to also fetch the tool stack
(`lf`, `tmux`, `tectonic`, `pandoc`, `termpdf.py` + Python deps) into
`~/.local/bin/` and `~/software/`:

```bash
~/dotfiles/bootstrap.sh --viewers
```

After bootstrap, open a new shell (or `source ~/.bashrc`).

## Terminal viewer stack

For reading documents over SSH+kitty without leaving the terminal.

| Tool      | Role                                                          |
|-----------|---------------------------------------------------------------|
| `tmux`    | Terminal multiplexer. Config in `config/tmux/tmux.conf`. Installed from `nelsonenzo/tmux-appimage` (extracted, no FUSE needed) |
| `lf`      | Terminal file manager (replaces ranger). Config in `config/lf/` |
| `md-view` | `pandoc → tectonic → PDF → termpdf` for markdown notes. Font size via `MDVIEW_FONTSIZE=14pt\|17pt\|20pt`, engine via `MDVIEW_ENGINE` |
| `img-view`| `kitten icat` wrapper, scales image to fit terminal box       |
| `termpdf` | Multi-page PDF/epub/djvu viewer using kitty graphics protocol |
| `tectonic`| Modern XeTeX engine. Bundles its own TeX, auto-fetches packages — bypasses incomplete cluster TeX installs |

Inside `lf`: `<enter>` dispatches by extension (md → md-view, pdf →
termpdf, image → img-view). `B` / `H` for big/huge font markdown, `P`
for first-page PDF peek, `yK` for kitty transfer download to local Mac.
`R` reloads the lf config.

## tmux config

`config/tmux/tmux.conf` is symlinked to `~/.config/tmux/tmux.conf` (and
`~/.tmux.conf` for tmux <3.1). Beyond the keybinding tweaks and the
TPM/minimal-tmux-status plugins (auto-installed on first run), it wires
up a set of helper scripts that **must be present in `~/.local/bin/`** —
`bootstrap.sh` symlinks them there from `bin/`:

| Binding / hook        | Helper (in `bin/`)   | What it does                                                            |
|-----------------------|----------------------|-------------------------------------------------------------------------|
| `prefix + g` / `G`    | `tmux-merge`         | Gather first N windows into one tiled window / restore them exactly     |
| `M-j`                 | `tmux-window-fzf`    | fzf window chooser popup (list left, live pane preview right)           |
| `prefix + S`          | `claude-tmux-set`    | Menu to manually override this window's Claude-state glyph              |
| `run-shell -b` (auto) | `claude-tmux-watch`  | Background fallback that scrapes panes to keep the glyph current        |
| (called by the above) | `claude-tmux-extwait`| Detects a live Claude-spawned background shell (e.g. a SLURM poll)      |
| Claude Code hooks     | `claude-tmux-state`  | Precise glyph driver, invoked by `~/.claude/settings.json` hooks        |

### tmux Claude-state glyph

Each window tab (and the `M-j` chooser) shows a coloured glyph for the
Claude session in that window — orange ● running, orange ○ waiting,
green ● your turn — read from a per-window `@claude_state` tmux option.
There are two ways that option gets set:

- **Polling fallback** — `claude-tmux-watch` is started automatically by
  `tmux.conf` and scrapes each Claude pane every few seconds. This needs
  **no extra wiring**: once the scripts are on `PATH`, the glyph works.
- **Precise hooks** *(optional)* — `claude-tmux-state` is invoked by
  Claude Code hooks and distinguishes `running` / `bg` / `ext` / `you`
  exactly (the fallback can't tell `bg` from `ext`). Because
  `~/.claude/settings.json` is per-host (model, plugins, statusLine
  paths differ per cluster), it is **not** auto-installed. To enable the
  precise path, merge the `hooks` block from
  `claude/settings.hooks.json` into your `~/.claude/settings.json` —
  e.g. with `jq`:

  ```bash
  jq -s '.[0] * {hooks: .[1].hooks}' \
     ~/.claude/settings.json ~/dotfiles/claude/settings.hooks.json \
     > /tmp/settings.merged && mv /tmp/settings.merged ~/.claude/settings.json
  ```

### External dependencies (install via your cluster's package manager)

These are *not* fetched by the repo — install them yourself:

- **`fzf`** — required for the `M-j` window chooser (`tmux-window-fzf`).
- **`jq`** — used by `claude-tmux-state` to read the hook payload; it
  degrades gracefully if absent (the `ext`-marker arming is skipped), so
  it is optional but recommended for the precise hooks.
- **`tmux` ≥ 3.2** — for `display-popup` (`M-j`) and `display-menu`
  (`prefix + S`). The bundled `install-tmux.sh` ships 3.5a.

## Backup workflow

All bulk data lives under
`mir-backup:Current_members/Gabriel/projects/<project>/<subpath>/<file>`
on the **MIR-backup shared (Team) drive** (research group, not a personal
account). Code stays in GitHub; only datasets, raw artefacts, and
processed outputs that need a long-term home off-cluster go to Drive.

| Command                                       | Behavior                                                                                |
|-----------------------------------------------|-----------------------------------------------------------------------------------------|
| `gdrive-push <local> [<sub>]`                 | `rclone copy <local> mir-backup:Current_members/Gabriel/projects/<proj>/<sub>/`         |
| `gdrive-pull <sub> [<dest>]`                  | inverse, into `<dest>` (default `.`)                                                    |
| `gdrive-archive <dir> [<sub>] [--rm] [-n]`    | tar + pigz, upload, **keep local by default** (`--rm` deletes after a successful copy)  |

`<proj>` is resolved from (first hit wins) the `-p` flag, the
`PROJECT_NAME` environment variable, or `basename(git rev-parse
--show-toplevel)`. Pass `-n` to any script to dry-run.

`gdrive-archive` honours an `ignore_list.txt` in the target directory
(`tar -X ignore_list.txt`) and uses `pigz` if available, gzip otherwise.

The shell snippet `shell/50-backup.sh` provides legacy aliases
`backup` / `restore` / `cloudsave` over the new scripts, so existing
muscle memory keeps working.

## Layout

```
dotfiles/
├── bin/                                 ← scripts symlinked into ~/.local/bin
│   ├── gdrive-{push,pull,archive}
│   ├── md-view                          ← markdown → pandoc/tectonic → termpdf
│   ├── img-view                         ← image filling terminal via kitten icat
│   ├── tmux-merge                       ← gather/restore windows as panes (prefix g/G)
│   ├── tmux-window-fzf                  ← fzf window chooser popup (M-j; needs fzf)
│   ├── vscode-login-tunnel.sh           ← `code tunnel` on an ALCF login node (cgroup-pinned)
│   ├── vscode-tunnel                    ← tmux up/attach/status/down for the tunnel
│   └── claude-tmux-{state,watch,set,extwait}  ← Claude-state tab glyph (see "tmux config")
├── config/                              ← per-file symlinks into ~/.config/<app>
│   ├── lf/{lfrc,preview,cleaner}
│   └── tmux/tmux.conf                   ← also symlinked to ~/.tmux.conf (legacy fallback)
├── install/                             ← idempotent fetchers (run with --viewers)
│   ├── install-lf.sh
│   ├── install-tmux.sh
│   ├── install-tectonic.sh
│   ├── install-pandoc.sh
│   ├── install-termpdf.sh
│   └── install-vscode-cli.sh            ← VS Code CLI (`code`) for login-node tunnels
├── shell/                               ← sourced from ~/.bashrc by bootstrap
│   ├── 00-path.sh                       ← prepends ~/.local/bin to $PATH
│   ├── 40-fasrc.sh                      ← FASRC SLURM alloc helpers + vscode aliases (no-op off FASRC)
│   ├── 41-polaris.sh                    ← Polaris login helpers + HQ fleet auto-up (no-op off ALCF)
│   ├── 42-fasrc-hq.sh                   ← FASRC `hq` ssh-bridge wrapper (no-op off FASRC)
│   ├── 50-backup.sh                     ← backup / restore / cloudsave aliases
│   └── 60-lf.sh                         ← EDITOR=nvim + lfcd cd-on-exit wrapper
├── scripts/                             ← cluster-specific helper scripts
│   ├── vscode/                          ← FASRC VSCode-on-compute-node toolkit (→ ~/scripts/vscode)
│   └── hq/                              ← HyperQueue: PBS 24/7 fleet + slurm/ on-demand allocator (install.sh is scheduler-aware)
├── docs/                                ← long-form guides (read with md-view)
│   ├── alcf-vscode-tunnel.md            ← VS Code remote tunnel on Polaris/Aurora login nodes
│   └── hyperqueue-fleet.md              ← HyperQueue fleet setup + mirroring to another cluster
├── claude/                              ← Claude Code config
│   ├── skills/                          ← symlinked into ~/.claude/skills
│   │   └── backup-to-gdrive/SKILL.md
│   ├── CLAUDE.md                        ← symlinked into ~/.claude/CLAUDE.md
│   └── settings.hooks.json              ← hooks for the tmux glyph (merge by hand)
├── rclone/rclone.conf.example           ← template; real config is per-cluster
└── bootstrap.sh
```

## Adding a new cluster

1. Install `rclone` and (optionally) `pigz` via the cluster's package
   manager or modules.
2. `git clone … ~/dotfiles && ~/dotfiles/bootstrap.sh`.
3. `rclone config` and create a remote named `mir-backup` of type
   `drive`, scoped to the **MIR-backup shared drive**: set
   `team_drive = 0ABLkzStq5DREUk9PVA` (or pick it from the team-drive
   list `rclone config` offers). On a headless cluster, run
   `rclone authorize drive` on a machine with a browser and paste the
   JSON token. To clone an existing personal `gdrive` remote into a
   shared-drive one, copy its `[gdrive]` block in
   `~/.config/rclone/rclone.conf` to `[mir-backup]` and add the
   `team_drive` line.
4. Smoke-test:
   ```bash
   echo hello > /tmp/hello.txt
   gdrive-push /tmp/hello.txt _smoketest -n     # dry-run
   gdrive-push /tmp/hello.txt _smoketest
   gdrive-pull _smoketest/hello.txt /tmp/hello.back
   diff /tmp/hello.txt /tmp/hello.back
   ```

## Security

`~/.config/rclone/rclone.conf` contains an OAuth refresh token. It is
listed in `.gitignore` and must never be committed. The
`rclone/rclone.conf.example` in this repo is a redacted template.
