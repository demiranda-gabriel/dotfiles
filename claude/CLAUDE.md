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
