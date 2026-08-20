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

## Job submission on Polaris (ALCF) — HyperQueue workflow

**Polaris-only section** (PBS Pro; other clusters ignore). All compute jobs
go through **HyperQueue** (`hq`, `~/.local/bin/`), NOT raw `qsub`. Two
standing fleets feed ONE server/task pool (2026-08-15 →): **alpha** =
`capacity`, 4 nodes / 16 A100s; **bravo** = `preemptable`, up to 20 staggered
1-node jobs (max 10 running = 40 A100s). Tasks submitted to the HQ server
start within seconds on whatever workers are up — you never pick a fleet.
Because bravo workers can have <24 h left and may be preempted, write long
payloads re-entrant (auto-resume from `last.ckpt`) and avoid `--time-request`
longer than a worker's remaining walltime (task WAITS forever, silently).

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
| Primary allocation | alpha: 4-node/168h `capacity` jobs `hq-capacity` (`~/.hq/capacity-workers.pbs`); `HQ_CAP_JOBS` in fleet.env sets how many are kept in flight (1 as of 2026-08) |
| Bravo lane | `bravo-fleet {up N\|tick\|run\|status\|down}` (`~/.hq/bravo/worker.pbs`): many 1-node `preemptable` jobs named `bravo-1n`, staggered 24-72 h walltimes; ticker = tmux `bravo-fleet` on login-01 (added 2026-08-15) |
| Bridge allocation | **DISABLED since 2026-07-27** (`HQ_NO_BRIDGE=1` in fleet.env; capacity-only policy for the group-shared fleet). The `preemptable` `hq-bridge` machinery (`~/.hq/preempt-bridge.pbs`) still exists — re-enable by removing the knob |
| Autoalloc queues | `debug` (1n/1h) and `preempt` (1n/72h) — HQ auto-qsubs only when tasks wait uncovered; safety net, normally silent |
| Group sharing | fleet is shared with all HetRxnEnergy members via `/lus/eagle/projects/HetRxnEnergy/hq-shared/` (client access file + `hq`/`hq-submit`/`hq-gpus` + user README). Tasks run as demiranda; server keys pinned via `~/.hq/access/full.json` |

The fleet self-heals: each tick re-runs `hq-server-up` (idempotent) and tops
capacity back up to `HQ_CAP_JOBS` in flight.
`shell/41-polaris.sh` re-ups the fleet from any login-01 shell after reboots.
On Polaris, `~/dotfiles` stays on branch `polaris-shared-fleet` (never `main`).

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
