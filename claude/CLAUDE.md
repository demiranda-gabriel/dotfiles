# User-scoped instructions

Loaded for every Claude Code session under this home directory,
regardless of project.

## Plotting conventions

Defaults for every figure/plot I generate (matplotlib or otherwise),
unless a specific request says otherwise:

- **No figure suptitle.** Don't add `fig.suptitle`. Put context in the
  per-panel titles, axis labels, legend, and the surrounding
  notes/README instead.
- **Keep the canvas compact.** Prefer a smaller `figsize` so the text
  (titles, ticks, value labels, legend) renders large and legible
  relative to the figure, rather than small on a sprawling canvas. Err
  toward a tight figure and let the fonts read clearly.

## Equations in chat

My chat client renders **display** LaTeX but does **not** render inline LaTeX.

- **Default: put every equation on its own line** as a display block
  (`$$ ... $$`). Do this even for short expressions — prefer breaking the
  sentence over inlining the math.
- **Inline math only when unavoidable, and then code-style with text
  symbols**: `erfc(alpha*r)/r`, `exp(-k^2 / 4 alpha^2)`, `O(N log N)`.
  Never inline `$...$` — it shows up as raw markup.
- Applies to prose, tables, and reports written into chat. Files that are
  rendered elsewhere (notes, papers, md-view PDFs) keep normal LaTeX.

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
| `md-view`  | Markdown → PDF (pandoc + **typst**) → doc-view. Body face Cantarell, maths New Computer Modern Math. Env: `MDVIEW_FONTSIZE` (default `14pt`; valid `10|11|12|14|17|20`), `MDVIEW_FONT` (default `sans`), `MDVIEW_MATHFONT`, `MDVIEW_THEME` (`light`/`dark`), `MDVIEW_COLUMNS`, `MDVIEW_JUSTIFY`, `MDVIEW_ENGINE` (default `typst`) | `dotfiles/bin/` + `config/mdview/mdview.typ` |
| `img-view` | `kitten icat` wrapper, fits image in terminal box, clears before display | `dotfiles/bin/` |
| `doc-view` | Multi-page PDF / epub / djvu / cbz viewer. PyMuPDF renders, `kitten icat` displays, so it works inside tmux. Keys: `j`/`k` page, `w` fit-width, `+`/`-` zoom, `<n>g` goto, `r` reload, `q` | `dotfiles/bin/` |
| `termpdf`  | Upstream viewer, fallback outside tmux only — it emits raw kitty APC with no tmux passthrough, so inside tmux it draws nothing | upstream py, fetched |
| `tectonic` | Modern XeTeX engine, bundles TeX, auto-fetches packages — bypasses incomplete cluster TeX | binary, fetched |
| `pandoc`   | Newer (3.9.0.2) — system pandoc on RHEL/Rocky 8 is too old for tectonic | binary, fetched |

**Inside `lf`:** `<enter>` dispatches by extension (md → md-view, pdf →
doc-view, image → img-view). `B`/`H` for big/huge font markdown, `P` for
first-page pdf peek, `yK` for kitty transfer download to local Mac, `R`
to reload config. Quit drops parent shell into last-visited dir.

**Kitty graphics over SSH — do not set `--transfer-mode` to `file` or
`memory`.** Those modes send the terminal a *path* (a temp file, or a
`/dev/shm` object) instead of the image bytes. The terminal is on the Mac and
the path exists only on the cluster, so nothing renders — silently, with no
error. Every icat call in this stack passes `--transfer-mode=stream`, and
`ICAT_TRANSFER_MODE` overrides it on a host where kitty is local.

**lf previews: the image data must bypass lf.** lf parses a previewer's stdout
for colouring and drops APC and DCS sequences — precisely where kitty's pixels
travel. It keeps the Unicode placeholder cells and the 24-bit foreground colour
naming the image, so the terminal is told to paint an image it was never sent
and the pane stays blank. `config/lf/preview` therefore pipes icat through
`tee /dev/tty`: the tty copy carries the pixels past lf's filter, the stdout
copy becomes the pane text so lf repaints the placeholders itself. It also pins
`--image-id` below 2^24 — icat otherwise picks a random 32-bit id whose top byte
has nowhere to travel, leaving the placeholder naming an id the terminal lacks.
The cleaner writes to `/dev/tty` for the same reason. Don't "simplify" either
back to plain stdout.

**Python-dependent viewers get a pinned interpreter.** `doc-view` and `termpdf`
need PyMuPDF. Under `#!/usr/bin/env python3` they broke with
`ModuleNotFoundError: fitz` whenever any project venv was active. Both now run
from `~/.local/share/pdfview/venv`, built by `install/install-pdfview.sh` and
touched by nothing else. Don't "fix" a viewer by pip-installing into a project
venv.

**md-view renders through typst, not TeX.** Same note, 0.25s instead of 9.5s,
with maths that survives the trip: pandoc's typst writer handles fractions,
sums, matrices, integrals, `\mathcal`, `\mathbf` and `aligned`. The page is
sized to the terminal's aspect ratio rather than to paper, so one page is one
screenful in doc-view. That aspect comes from TIOCGWINSZ, which reports the
window in pixels as well as in cells, and is computed against the box doc-view
actually draws into — not the whole window, since doc-view keeps the bottom row
for its status line and shaves a column under tmux. Guessing the cell shape
instead ("about twice as tall as wide"; real cells run nearer 1:2.2) left a
band of terminal background under every page. Three defects in what pandoc emits are patched in
`md-view` before compiling (bare `∥…∥` norms, empty `sqrt()`, and a one-letter
script glued to a spacing macro), citations are disabled so "@270 epochs" stays
prose, and relative image paths are made absolute. If typst still fails on a
note, md-view says so and falls back to tectonic rather than showing nothing.
Verified across all 107 notes in the nequiph repo: 106 render under typst; the
only failure is the marp deck, whose YAML frontmatter pandoc itself rejects on
either engine (read decks with `M` in lf instead).

**Cluster TeX caveat:** the system TeX install on FASRC (Rocky 8) is
incomplete — `xelatex`/`lualatex` missing `ucharcat.sty`, xcolor broken.
The `tectonic` fallback bypasses this entirely. Don't try to "fix" by
switching to system pdflatex unless explicitly working ASCII-only.

## Job submission on Polaris (ALCF) — HyperQueue workflow

**Polaris-only section** (PBS Pro; other clusters ignore). All compute jobs
go through **HyperQueue** (`hq`, `~/.local/bin/`), NOT raw `qsub`. A
standing fleet of 2 nodes / 8 A100s is kept attached at all times; tasks
submitted to the HQ server start within seconds on whatever workers are up.

### Submitting work

```bash
hq submit --resource gpus/nvidia=1 -- python train.py  # 1 GPU; HQ sets CUDA_VISIBLE_DEVICES
hq submit --cpus 16 -- ./analysis.sh                   # CPU-only
hq job list / hq job info <id> / hq job cat <id> stdout
hq-fleet status                                        # fleet at a glance
```

Tasks are cheap (~ms overhead) — submit many small ones; HQ packs them
(e.g. 4 single-GPU tasks per node). Tasks interrupted by preemption retry
automatically (default `--crash-limit 5`).

### Architecture (set up 2026-06-12; do not re-invent)

To replicate this fleet on another cluster, the tracked reference scripts +
installer + full guide live in the dotfiles: `scripts/hq/` and
`~/dotfiles/docs/hyperqueue-fleet.md` (PBS reference; SLURM-adaptation section
included).

| Piece | What / where |
|-------|--------------|
| HQ server | `polaris-login-01`, tmux session `hq`, journal `~/.hq/journal`, log `~/.hq/server.log` |
| `hq-server-up` | THE ONLY way to (re)start the server — applies LD_PRELOAD shim + taskset (see cgroup note) |
| `hq-fleet` | orchestrator, tmux session `hq-fleet`; subcommands `status/up/down/tick`, `DRY_RUN=1` to preview; log `~/.hq/fleet.log` |
| Primary allocation | 2-node/168h `capacity` job `hq-capacity` (`~/.hq/capacity-workers.pbs`) |
| Bridge allocation | 2-node/72h `preemptable` job `hq-bridge` (`~/.hq/preempt-bridge.pbs`), ensured when no capacity job runs or <24h remains; auto-cancelled when capacity is healthy AND no HQ task is running |
| Autoalloc queues | `debug` (1n/1h) and `preempt` (1n/72h) — HQ auto-qsubs only when tasks wait uncovered; safety net, normally silent |

The fleet self-heals: each tick re-runs `hq-server-up` (idempotent), resubmits
capacity when the project slot frees, resubmits the bridge if preempted.
`shell/41-polaris.sh` re-ups the fleet from any login-01 shell after reboots.

**Notifications**: the fleet pushes state transitions (allocation start/end,
submissions, bridge handover) to a Slack DM via incoming webhook, plus
ntfy.sh while it remains configured. Secrets (`SLACK_WEBHOOK`, `NTFY_TOPIC`)
live in `~/.hq/fleet.env` (per-host — never commit it). Detection latency
≤ one tick (10 min).

**Resizing the fleet**: `qalter -l select=...` is BLOCKED by ALCF's
account_check hook — resizing requires resubmission. Edit `select=` in both
`~/.hq/*.pbs` scripts, then `hq-fleet down`, `qdel` the queued `hq-capacity`
/ `hq-bridge` jobs, `hq-fleet tick` (resubmits at the new size), `hq-fleet up`.

### Login-node cgroup trap (affects EVERYTHING, not just hq)

Login nodes confine each user to `/sys/fs/cgroup/users/$USER/`:
**8 cores, 8 GB RAM, 256 pids — and pids count THREADS.** At the cap, every
new `fork()`/`pthread_create()` in any process fails (crashes Claude/Node
sessions). `taskset` does NOT constrain libraries that read raw core count
via `get_nprocs()` (the HiGHS solver inside hq spawned 128 threads this way).
Fix: `LD_PRELOAD=~/.hq/shim/nproc8.so` (fakes 8 CPUs; source alongside).
Apply shim + `taskset -c 0-7` to ANY long-lived daemon on login nodes.
Diagnose with `cat /sys/fs/cgroup/users/$USER/pids.{current,events}`.

### Queue facts (verified empirically)

- `capacity`: ≤4 nodes, ≤168h, **2 jobs/project (queued+running, Held jobs
  count)** — check teammates' jobs (`qstat -f <id> | grep Account_Name`)
  before submitting.
- `preemptable`: 1–10 nodes, ≤72h, can be preempted by on-demand jobs.
- `debug`: ≤2 nodes, ≤1h. `prod` walltime is tiered by node count (10n→3h).
- Always pass `-A HetRxnEnergy -l filesystems=home:eagle -l place=scatter`.

### Troubleshooting

- Server dead / `hq` says "no running instance" → `hq-server-up` (journal
  restores jobs + autoalloc queues; fleet does this automatically within 10 min).
- No workers → `hq-fleet status`; check `qstat -u $USER` and `~/.hq/fleet.log`.
- Never start the server bare, never move it off `polaris-login-01`
  (clients dial the host recorded in `~/.hq-server/`).
- Pause everything (e.g. budget): `hq-fleet down`, then `qdel` the
  `hq-capacity` / `hq-bridge` jobs.

## Job submission on FASRC (Cannon) — HyperQueue (on-demand)

**FASRC-only section** (SLURM; other clusters ignore). Unlike Polaris, there is
**no 24/7 fleet** — usage is on-demand. Set up 2026-06-23; full guide in
`~/dotfiles/docs/hyperqueue-fleet.md` (§ Running it on FASRC).

**Why it differs:** FASRC firewalls login↔compute on arbitrary ports **both
ways**, so the HQ server can't live on a login node (Polaris's model). It runs
on a **compute node** (small CPU alloc); workers reach it compute↔compute; the
`hq` CLIENT is an **ssh bridge** to that node (wrapper in `shell/42-fasrc-hq.sh`,
reads `~/.hq/server-node`). `hq` only works through that wrapper.

```bash
hq-fleet up                                     # 1 GPU on gpu_requeue (polite default)
hq-fleet up -p kozinsky_gpu -g 4 -t 1-00:00:00  # whole lab A100 node, guaranteed
hq-fleet up -p gpu_requeue  -N 2 -g 4           # +2 preemptable nodes (stacks)
hq submit --resource gpus/nvidia=1 -- python train.py
hq job list ; hq-fleet status
hq-fleet down [--all]                           # workers (+ server with --all)
```

- `hq-fleet up` auto-starts the server (idempotent) and **stacks** (call again
  to add lanes). Server lane = `sapphire` (instant, no-preempt) and **self-chains**
  past its 3-day cap (queues a dependent successor → effectively immortal;
  `HQ_NO_CHAIN=1` to disable; `down --all` stops the chain). Guaranteed GPUs =
  `kozinsky_gpu` (only 2 nodes — don't monopolize); preemptable = `gpu_requeue`.
- Install/refresh: `HQ_SCHED=slurm ~/dotfiles/scripts/hq/install.sh` (links the
  `scripts/hq/slurm/` variants; auto-detected from `sbatch`). No login-node
  shim/taskset needed here (no ALCF pid cap).
- `gpu_test` is stricter: `-c <8` and `-m <64000M` per GPU.

## Claude Code profiles (two accounts)

Two Claude accounts run side by side on every cluster. The primary uses the
default config home (`~/.claude`) and plain `claude`; each extra account lives
in `~/.claude-<name>` and runs as `claude-<name>` — currently `claude-harvard`.
`CLAUDE_CONFIG_DIR` picks the home: it must be absolute and set in the shell,
never in `settings.json`.

Separate per account: credentials, `.claude.json` (project trust, MCP servers,
prompt history), transcripts, `--resume`, and auto-memory. Shared by symlink:
this file, `dotfiles/claude/skills/*`, and `settings.json` — so a `/model`
change or plugin toggle in one profile also changes the other.

Add one with `claude-profile-init <name>`, then commit
`dotfiles/claude/profiles`; `bootstrap.sh` recreates it on every other cluster
(each needs its own `/login`). Detail — what is shared and why, and the two
traps — lives in `~/dotfiles/docs/claude-profiles.md`. That file is the
authoritative source; this section is just a pointer.

## New-cluster recipe

```bash
git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh --viewers
source ~/.bashrc
```

That installs gdrive scripts, lf+viewer stack, shell snippets, Claude
skills, every extra Claude profile in `claude/profiles`, and symlinks this
CLAUDE.md into `~/.claude/`. After that the canonical references are:

- `~/dotfiles/README.md` — full repo doc
- `~/dotfiles/claude/skills/backup-to-gdrive/SKILL.md` — backup policy
- `~/dotfiles/docs/claude-profiles.md` — second-account profiles
- This file — global Claude instructions

Auto-memory at `~/.claude/projects/<dir-hash>/memory/` is **per-host and
not in the repo**. New cluster starts with empty memory; Claude rebuilds
it from observation.
