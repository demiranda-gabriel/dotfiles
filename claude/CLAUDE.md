# User-scoped instructions

Loaded for every Claude Code session under this home directory,
regardless of project.

## Answer style

I run several agents in parallel and read each answer cold, after a
context switch. Write every answer so it stands on its own — I should be
able to act on it without scrolling back through the conversation.

### Self-contained answers

- **Lead with the result.** First line = the number, verdict, or what
  changed. Reasoning after it, not before.
- **Restate specifics instead of referring back.** Name the run, tag,
  path, config key and value explicitly — never "the earlier run", "that
  config", "as discussed", or a bare "it". Repeating a value I already
  saw is cheap; making me hunt for it is not.
- **Plain English, full sentences.** Explain the mechanism and the *why*,
  not just the *what*. Avoid bullet fragments that only parse if the
  previous turn is still in my head.
- **Detailed, not padded.** Length should come from context I need —
  assumptions made, what was verified vs. assumed, caveats, what is still
  pending — never from restating my question or listing paths not taken.
  A short answer that names the run and the number is already
  self-contained.
- **Surface decisions explicitly.** If something needs my call, say so in
  its own line with a recommendation and the trade-off; don't bury it.
- **Close with state:** done and verified / running (with job or run IDs)
  / blocked and on what.

### Equations

- **Default to display blocks.** Every equation goes on its own full line
  as `$$ … $$`, in LaTeX, with blank lines around it. Split multi-part
  statements into separate blocks rather than chaining them.
- **Inline math is unicode, never LaTeX.** Inline `$…$` does not render in
  my chat — it shows as raw source. To reference a variable or small term
  mid-sentence, write unicode text: ρ(z), Δφ, ε₀, r_max = 7 Å, E_lr, ∇E,
  →. Use `_` for subscripts that have no unicode form. Same rule inside
  markdown table cells; if a cell needs a real equation, pull it out into
  a display block below the table.
- **Base LaTeX2e inside display blocks.** I copy them straight into my own
  `.tex`, compiled without extra packages: `\mathrm` not `\text`, `\frac`
  not `\tfrac`/`\dfrac`, no `\;` `\,` `\!` spacing macros, no `\boxed`,
  and no literal unicode inside the math (`\times`, `\neq`, `\mathrm{A}`).
  The unicode rule above is for prose only.

## Subagents and parallel tasks

**Hard cap: never run more than 3 parallel subagents / background tasks
without my express consent.** Set 2026-09-05 after a research session spawned
9 agents across three rounds and burned ~2.5M tokens, pushing me into my usage
limit mid-task.

- Subagent tokens bill against my limits and I cannot see them accumulating
  while the agents run. A fan-out that is free to you is expensive to me.
- Sequential rounds count cumulatively: three rounds of three is nine, not
  three.
- Above the cap, say in chat what you want to spawn and roughly what it costs,
  then wait for an explicit OK.
- Default to doing the work inline. Web research, file reading and citation
  checking are usually cheaper done directly than delegated.
- Prefer one broad agent over several narrow ones; resume an existing agent
  (SendMessage) rather than spawning a fresh one.
- Scope agent prompts tightly — open-ended "find and verify 8-14 sources"
  briefs are what make them expensive.
- **Nested agents are the hidden multiplier.** A general-purpose subagent can
  spawn its own subagents, and stopping a parent does NOT stop its children.
  After any stop, run `ListAgents` and kill every remaining running entry, then
  confirm with a second `ListAgents`. Prefer read-only agent types that cannot
  fan out, and tell general-purpose agents not to spawn subagents.

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
| `nvim`     | Editor. `$EDITOR`/`$VISUAL` when installed (`shell/60-lf.sh`), else system vim | static tarball, fetched |
| `md-view`  | Markdown → PDF (pandoc + **typst**) → doc-view. Body face Cantarell, maths New Computer Modern Math. Env: `MDVIEW_FONTSIZE` (default `14pt`; valid `10|11|12|14|17|20`), `MDVIEW_FONT` (default `sans`), `MDVIEW_MATHFONT`, `MDVIEW_THEME` (`light`/`dark`), `MDVIEW_COLUMNS`, `MDVIEW_JUSTIFY`, `MDVIEW_ENGINE` (default `typst`) | `dotfiles/bin/` + `config/mdview/mdview.typ` |
| `img-view` | `kitten icat` wrapper, fits image in terminal box, clears before display. `exec`s `iip-view` when `TERM_PROGRAM=vscode` | `dotfiles/bin/` |
| `iip-view` | iTerm2 inline-image protocol (OSC 1337) emitter — the VS Code lane (xterm.js speaks sixel + iTerm2, never the kitty protocol). Requires `terminal.integrated.enableImages`; `--place=WxH@XxY` as in `kitten icat`; no-tmux workflow | `dotfiles/bin/` |
| `doc-view` | Multi-page PDF / epub / djvu / cbz viewer. PyMuPDF renders, `kitten icat` displays, so it works inside tmux. Keys: `j`/`k` page, `w` fit-width, `+`/`-` zoom, `<n>g` goto, `r` reload, `q` | `dotfiles/bin/` |
| `termpdf`  | Upstream viewer, fallback outside tmux only — it emits raw kitty APC with no tmux passthrough, so inside tmux it draws nothing | upstream py, fetched |
| `tectonic` | Modern XeTeX engine, bundles TeX, auto-fetches packages — bypasses incomplete cluster TeX | binary, fetched |
| `pandoc`   | Newer (3.9.0.2) — system pandoc on RHEL/Rocky 8 is too old for tectonic | binary, fetched |

**Inside `lf`:** `<enter>` opens **any** file type in VS Code (`code -r`
over the integrated terminal's `$VSCODE_IPC_HOOK_CLI`; multi-selection
opens in one call). With no reachable VS Code socket it falls back to the
old extension dispatch, which `O` also invokes on demand (md → md-view,
pdf → termpdf, image → img-view) — use `O` or `P` for pdf/epub/djvu,
which VS Code cannot render without an extension. `B`/`H` for big/huge
font markdown, `P` for first-page pdf peek, `yK` for kitty transfer
download to local Mac, `R` to reload config. Quit drops parent shell into
last-visited dir. The preview pane renders images/PDFs inline in either
protocol — `config/lf/preview` and `config/lf/cleaner` both branch on
`TERM_PROGRAM=vscode`.

**Cluster TeX caveat:** the system TeX install on FASRC (Rocky 8) is
incomplete — `xelatex`/`lualatex` missing `ucharcat.sty`, xcolor broken.
`md-view` defaults to `tectonic` to bypass this entirely. Don't try to
"fix" by switching to system pdflatex unless explicitly working ASCII-only.

## Job submission on Polaris (ALCF) — HyperQueue workflow

**Polaris-only section** (PBS Pro; other clusters ignore). All compute jobs
go through **HyperQueue** (`hq`, `~/.local/bin/`), NOT raw `qsub`. Three
lanes on TWO servers (private bravo split 2026-08-20; charlie added
2026-09-30): **alpha** = `capacity`, 4 nodes / 16 A100s, group-shared, client
`hq`; **bravo** = `preemptable`, up to 20 staggered 1-node jobs (max 10 running
= 40 A100s, but the pool is 56 nodes machine-wide and delivered ~8 GPUs on
average in Sep 2026), PRIVATE — own server + keys, invisible to the
group-shared client — client `hqb` (usage identical to `hq`); **charlie** =
`prod`→`medium`, 25-node × 6 h allocations (100 A100s each), an ALWAYS-ON
CHAIN since 2026-10-12 (no idle shutdown; `charlie-fleet` submits each
successor one predicted queue wait — 80th pct of the last 10 — before the
current one ends, and a successor that starts early drains its predecessor;
`charlie-fleet pause` to stop); also feeds `hqb`. Default big training runs to `hqb`; treat alpha as the
shared/overflow lane and check `hq job list` for teammates' work before large
batches.
Because bravo workers can have <24 h left and may be preempted, and charlie
workers live 6 h, write long payloads re-entrant (auto-resume from
`last.ckpt`, checkpoint at least every epoch) and avoid `--time-request`
longer than a worker's remaining walltime (task WAITS forever, silently). A
worker hitting its time limit SIGINTs its tasks and kills them ~1 s later;
they return to WAITING with no crash-limit charge and resume on the next
worker (verified 2026-09-30). Put `%{INSTANCE_ID}` in task log paths or each
leg truncates the previous leg's log. Full mechanics:
`~/dotfiles/docs/hyperqueue-fleet.md` § *Three fleets: charlie*.
Since 2026-10-05 plain `hq submit` / `hqb submit` are unchanged and still the
normal way to submit: the `hqx` router moves your WAITING jobs to free GPU
slots on the other server automatically. Use `hqx submit --fleet <f>` only to
pin a job to a fleet. Give long jobs a `--time-request`, or the router may
place them on a worker about to hit its walltime.

### Submitting work

```bash
hq submit --resource gpus/nvidia=1 -- python train.py  # 1 GPU; HQ sets CUDA_VISIBLE_DEVICES
hq submit --cpus 16 -- ./analysis.sh                   # CPU-only
hq job list / hq job info <id> / hq job cat <id> stdout
hq-fleet status                                        # fleet at a glance
hqx list                                               # ONE queue over both servers (+ free GPUs per fleet)
hqx submit --fleet charlie --resource gpus/nvidia=1 -- python train.py   # pin; omit --fleet = run anywhere
hq-gpus-all                                            # per-GPU view, BOTH servers, one "alloc" line per PBS job (demiranda-only; hq-gpus = alpha only)
charlie-fleet status                                   # medium lane: jobs, demand, workers
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
| Primary allocation | alpha: 4-node/168h `capacity` jobs `hq-capacity` (`~/.hq/capacity-workers.pbs`); `HQ_CAP_JOBS` in fleet.env sets how many are kept in flight (2 since 2026-10-03 = one running + one queued back-to-back, both project slots; was 1 from 2026-08, which left 13 h-3.7 d queue gaps after every allocation end). Changing it needs `hq-fleet down` + `hq-fleet up` on login-01 |
| Bravo lane | `bravo-fleet {up N\|tick\|run\|status\|down}` (`~/.hq/bravo/worker.pbs`): many 1-node `preemptable` jobs named `bravo-1n`, staggered 24-72 h walltimes; ticker = tmux `bravo-fleet` on login-01 (added 2026-08-15) |
| Charlie lane | `charlie-fleet {tick\|run\|status\|waits\|size [N [--wall W] [--now]]\|up N\|pause\|resume\|down\|down-queued}` (`~/.hq/charlie/worker.pbs`): 25-node × 6 h `prod`→`medium` jobs named `charlie-25n`, ALWAYS-ON CHAIN since 2026-10-12: every allocation runs full walltime (idle watchdog removed); successor submitted when the last allocation has ≤ lead + 5 min left, lead = `CHARLIE_WAIT_Q`=0.8 quantile of the last `CHARLIE_WAIT_N`=10 observed waits (`~/.hq/charlie/waits.tsv`) in [30, 360] min; a successor that starts early `hq worker stop`s the predecessor's workers once nothing waits and it can absorb them (tasks resume from last.ckpt). PBS `-a`/`-h`/`depend` can't time starts (no eligible_time accrual → wait starts at release). `down` also pauses. Ticker = tmux `charlie-fleet` on login-01, restart it after editing fleet.env. Size is runtime-adjustable since 2026-10-14: `charlie-fleet size N` writes `~/.hq/charlie/size`, read on every submit (no restart); 10-24 nodes -> small/3 h, 25-99 -> medium/6 h, 100-496 -> large/24 h; `--now` replaces the queued successor. Not autoalloc: `prod` rejects <10 nodes and autoalloc sizes to demand |
| One queue: `hqx` | (2026-10-05) `hqx list` = both servers as one queue (ids `a<id>` shared / `b<id>` private); `hqx submit [--fleet alpha\|bravo\|charlie[,…]\|any]`, `hqx move <id> --to <fleet> [--running]`, `hqx pin <id> <fleets>\|any`. Router = tmux `hq-router` on login-01 (`hqx router status\|up\|down`): every 60 s moves YOUR waiting jobs (cancel + resubmit from the server's JSON) to free GPU slots on the other server, never teammates' jobs, never to create demand. Pinning = worker marker resources `fleet/<name>` added at `worker start` by the wrapper `~/.local/bin/hq` -> `scripts/hq/hq-fleet-wrap`; REAL binary is `~/.local/libexec/hq/hq` (must stay named `hq`: hq-server-up uses `pgrep -x hq`). State in `~/.hq-router/` |
| Bravo server (PRIVATE) | since 2026-08-20 bravo workers attach to a second server: tmux `hq-bravo`, started ONLY via `hq-bravo-server-up`, server-dir `~/.hq-bravo-server`, journal/log under `~/.hq-bravo/`, pinned ports 36152/44986. Client = `hqb`. Keys in `~/.hq-bravo/access/` are demiranda-only — NEVER copy them into `hq-shared/` |
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
