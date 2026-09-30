# HyperQueue standing fleet — setup & mirroring guide

How to stand up the always-on HyperQueue (HQ) fleet we run on Polaris on
another cluster, from these dotfiles. The goal: a meta-scheduler where you
`hq submit` tasks that **start within seconds** on a pool of nodes HQ keeps
attached for you — instead of waiting in the batch queue per job.

Two implementations live in `scripts/hq/`:
- **PBS/ALCF** (Polaris, Aurora, …) — the 24/7 standing fleet described below.
  This is the bulk of the guide.
- **SLURM/FASRC** (`scripts/hq/slurm/`) — an **on-demand** allocator, not a
  standing fleet. FASRC's login↔compute firewall forces a different topology;
  see [Running it on FASRC (SLURM)](#running-it-on-fasrc-slurm) at the end.

---

## TL;DR — mirror to another ALCF PBS cluster

```bash
# 0. hq on PATH (see "Install HyperQueue" below)
# 1. render scripts + build shim into ~/.hq, symlink orchestrators onto PATH
HQ_SYSTEM=aurora HQ_FILESYSTEMS=home:flare \
  ~/dotfiles/scripts/hq/install.sh        # edit the knobs for your cluster

# 2. pick ONE stable login node and start the server there
ssh <that-login-node>
HQ_SERVER_HOST=$(hostname -s) hq-server-up

# 3. (optional) autoalloc safety-net queues — see step 5 of install.sh output
# 4. start the standing fleet (resubmits capacity + bridge, supervises server)
HQ_SERVER_HOST=$(hostname -s) HQ_FLEET_LABEL=aurora hq-fleet up
hq-fleet status
```

After this, from anywhere that can reach the server host:

```bash
hq submit --resource gpus/nvidia=1 -- python train.py
hq job list
```

---

## Architecture

Four cooperating pieces, all living in the user's space (no admin needed):

| Piece | Where it runs | Role |
|---|---|---|
| **HQ server** | one login node, tmux session `hq` | the meta-scheduler; clients/workers dial the host recorded in `~/.hq-server/`. Started **only** via `hq-server-up`. |
| **Workers** | compute nodes (inside PBS jobs) | one `hq worker` per node; attach to the server and run tasks for the job's lifetime. |
| **`hq-fleet`** | login node, tmux session `hq-fleet` | orchestrator: keeps allocations attached, supervises the server, pushes notifications. |
| **Autoalloc** | inside the server | HQ's own safety net: auto-`qsub`s short allocations *only* when tasks wait uncovered. Normally silent. |

```
  you ──hq submit──> HQ server (login node, tmux 'hq', cpu-pinned)
                         │  dispatches tasks
                         ▼
            workers on compute nodes  ◄── PBS jobs submitted & maintained by:
                                            hq-fleet (login node, tmux 'hq-fleet')
                                              ├─ capacity job  (long, primary)
                                              ├─ bridge job    (preemptable, gap filler)
                                              └─ autoalloc     (debug/preempt, safety net)
```

### The two allocation lanes the fleet maintains

- **Capacity (primary):** long jobs (`168h` on Polaris) on the `capacity`
  queue, named `hq-capacity`. The fleet keeps `HQ_CAP_JOBS` of them in flight
  (running + queued; default 1). ALCF allows only **2 capacity slots per
  project** (queued+running, *held jobs count*).
- **Bridge (gap filler):** a `preemptable` job (`72h`), named `hq-bridge`,
  submitted whenever no capacity job is **running** or the running one has
  `< LEAD_HOURS` (24h) left. It can be preempted any time; HQ's default
  `--crash-limit 5` reruns interrupted tasks on surviving workers. Once
  capacity is healthy *and* no HQ task is running, the fleet `qdel`s the
  bridge. `HQ_NO_BRIDGE=1` disables the lane entirely (leftover bridge jobs
  are drained and qdel'd).

> **Current Polaris policy (2026-07-27, group-shared fleet):** capacity-only —
> `HQ_CAP_JOBS=2` (one running + one queued back-to-back, using both project
> slots) and `HQ_NO_BRIDGE=1`, set in `~/.hq/fleet.env`. The weekly handover
> may leave a short worker gap (PBS start latency); crash-limit reruns cover
> tasks cut off at the walltime edge.

Each `tick` (every 10 min) the fleet also re-runs `hq-server-up` (idempotent),
so a crashed/rebooted server self-heals; the journal restores jobs + autoalloc.

---

## Why it's built this way (the non-obvious constraints)

These are the things that will bite you on a new cluster if you don't carry
them over:

1. **Login-node cgroup cap.** ALCF login nodes confine each user to **8 cores /
   8 GB / `pids.max=256`, and pids count THREADS.** The HQ server is fine at 8
   cores, but unpinned it sizes thread pools to the *hundreds* of hardware
   cores the node reports and blows the 256-pid cap — after which every
   `fork()`/`pthread_create()` in *any* of your processes fails. Two defenses,
   both applied by `hq-server-up`:
   - `taskset -c 0-7` — pins scheduling to 8 CPUs.
   - **`LD_PRELOAD` shim** (`nproc8.so`) — `taskset` does *not* lower the count
     that `glibc get_nprocs()` reports, and the HiGHS LP solver inside hq sizes
     a global pool from that (128 threads here, half the budget; can SIGABRT the
     server near the cap). The shim forces `get_nprocs()` to return 8.
   Diagnose with `cat /sys/fs/cgroup/users/$USER/pids.{current,events}`. If a
   cluster has no such cap, the shim/taskset are harmless.
2. **Server host is sticky.** Clients and workers connect to the host recorded
   in `~/.hq-server/`. Always start the server on the **same** login node
   (`HQ_SERVER_HOST`) and always `ssh` to that node — on Polaris it's
   `polaris-login-01`; on Aurora, pick one `aurora-uan-NNNN` and use it
   consistently (you may be routed elsewhere by default).
3. **Tasks are cheap, jobs are not.** HQ task overhead is ~ms, so submit many
   small tasks — HQ packs them onto the standing workers (e.g. 4 single-GPU
   tasks per 4-GPU node). The expensive thing (a batch allocation) is amortized
   across all of them.

---

## Step-by-step on a new PBS/ALCF cluster

### 1. Install HyperQueue

Single static Rust binary. Grab the release for your arch into `~/.local/bin`:

```bash
mkdir -p ~/.local/bin ~/software/hq && cd ~/software/hq
curl -sL -o hq.tar.gz \
  https://github.com/It4innovations/hyperqueue/releases/download/v0.26.2/hq-v0.26.2-linux-x64.tar.gz
tar xzf hq.tar.gz && ln -sf "$PWD/hq" ~/.local/bin/hq
hq --version
```

(Match the version we run, `v0.26.2`, unless you have a reason to move — the
journal format and `hq alloc` flags can change across releases.)

### 2. Render the fleet into place

```bash
# defaults are Polaris; override the knobs that differ on your cluster
HQ_SYSTEM=<sys> HQ_ACCOUNT=<proj> HQ_FILESYSTEMS=<fs> ~/dotfiles/scripts/hq/install.sh
```

This symlinks `hq-server-up`/`hq-fleet` onto PATH, builds `~/.hq/shim/nproc8.so`
(needs `gcc` — `module load gcc` first if absent), renders
`~/.hq/{capacity-workers,preempt-bridge}.pbs` from the templates, and seeds
`~/.hq/fleet.env`. It never clobbers existing `.pbs`/`fleet.env` (use `--force`).
Then review the two `.pbs` files and `fleet.env`.

### 3. Start the server (on your chosen login node)

```bash
ssh <stable-login-node>
HQ_SERVER_HOST=$(hostname -s) hq-server-up      # idempotent
```

### 4. (Optional) autoalloc safety-net queues

A backstop that auto-submits short allocations only when tasks wait uncovered:

```bash
hq alloc add pbs --name debug   --time-limit 1h    -- \
  -A <proj> -q debug       -l filesystems=<fs> -l place=scatter -m n
hq alloc add pbs --name preempt --time-limit 3days -- \
  -A <proj> -q preemptable -l filesystems=<fs> -l place=scatter -m n
hq alloc list
```

(HQ injects `select=`/worker resources itself and auto-detects GPUs. `-m n`
suppresses PBS's default abort mail — the fleet reports via Slack instead.)

### 5. Start the standing fleet

```bash
HQ_SERVER_HOST=$(hostname -s) HQ_FLEET_LABEL=<sys> hq-fleet up
DRY_RUN=1 hq-fleet tick     # preview one pass without submitting
hq-fleet status
```

### 6. Wire it to re-up after login-node reboots

Mirror Polaris's `shell/41-polaris.sh`: from any shell on the server host,
re-up the fleet (idempotent). Add a cluster guard analogous to the `/lus/eagle`
one, e.g. for Aurora:

```bash
if [[ -d /lus/flare && "$(hostname -s)" == aurora-uan-0009 ]] \
    && command -v hq-fleet >/dev/null 2>&1; then
  HQ_SERVER_HOST=aurora-uan-0009 HQ_FLEET_LABEL=aurora hq-fleet up >/dev/null 2>&1
fi
```

---

## Per-cluster knobs

What changes between clusters (everything else is portable):

| Knob | Polaris | What it is |
|---|---|---|
| `HQ_SERVER_HOST` | `polaris-login-01` | the one login node the server lives on |
| `HQ_ACCOUNT` | `HetRxnEnergy` | `#PBS -A` project/allocation |
| `HQ_SYSTEM` | `polaris` | `select=N:system=<sys>` |
| `HQ_NODES` | `2` | fleet size (`select=`) |
| `HQ_FILESYSTEMS` | `home:eagle` | `-l filesystems=` |
| `HQ_CAP_QUEUE` / `HQ_CAP_WALL` | `capacity` / `168:00:00` | primary lane |
| `HQ_BRIDGE_QUEUE` / `HQ_BRIDGE_WALL` | `preemptable` / `72:00:00` | gap-filler lane |
| `HQ_FLEET_LABEL` | `Polaris` | tag in notifications |
| `LEAD_HOURS` | `24` | resubmit bridge when capacity has < this left |
| `HQ_CAP_JOBS` | `2` | capacity jobs kept in flight (running+queued); default 1 |
| `HQ_NO_BRIDGE` | `1` | disable the bridge lane; default 0 (enabled) |

`#PBS` directives can't read shell vars, so the queue/account/walltime live as
literal lines in the rendered `~/.hq/*.pbs` — `install.sh` substitutes them, or
edit by hand. Verify the queue rules for your cluster (walltime caps, node
limits, jobs-per-project) before trusting the defaults.

---

## Using the fleet day-to-day

```bash
hq submit --resource gpus/nvidia=1 -- python train.py   # 1 GPU; HQ sets CUDA_VISIBLE_DEVICES
hq submit --cpus 16 -- ./analysis.sh                     # CPU-only
hq submit --array 1-100 -- ./run.sh                      # 100 tasks, packed onto workers
hq job list / hq job info <id> / hq job cat <id> stdout
hq worker list                                           # what's attached
hq-fleet status                                          # fleet at a glance
```

(On Polaris, a shell wrapper in `shell/41-polaris.sh` routes `hq submit` task
logs into `<git-root>/runs/_hq_logs/`; that's a convenience, not part of the
fleet — carry it over only if you want it.)

---

## Operations

- **Resize the fleet.** `qalter -l select=` is blocked by ALCF's account_check
  hook — resizing means resubmission. Change `HQ_NODES` and re-render
  (`install.sh --force`), then `hq-fleet down`, `qdel` the queued
  `hq-capacity`/`hq-bridge` jobs, `hq-fleet tick` (resubmits at the new size),
  `hq-fleet up`.
- **Pause everything** (budget/maintenance): `hq-fleet down`, then `qdel` the
  `hq-capacity`/`hq-bridge` jobs.
- **Server looks dead** (`hq` says "no running instance"): `hq-server-up` on the
  server host (the fleet does this each tick anyway, within ≤10 min). The
  journal restores jobs + autoalloc queues.
- **No workers:** `hq-fleet status`; check `qstat -u $USER` and `~/.hq/fleet.log`.
- **Never** start the server bare (no shim/taskset) and **never** move it off
  the recorded host — clients dial the host in `~/.hq-server/`.

---

## Sharing the fleet with your project group

HQ has no user isolation — sharing is the documented "group of users that
trust each other" model. Anyone holding the **client** key can submit/query/
cancel *everything*, and tasks execute **as the fleet owner's account** on the
workers. Get your facility's blessing first (others executing under your UID
can conflict with account-sharing policy; a service account is the clean fix).

Mechanics (set up on Polaris 2026-07-27, `/lus/eagle/projects/HetRxnEnergy/hq-shared/`):

1. **Pin the server keys.** By default the server mints new keys+ports every
   restart, so any shared copy goes stale within one self-heal tick. Generate
   once:
   ```bash
   mkdir -p ~/.hq/access && chmod 700 ~/.hq/access
   hq server generate-access ~/.hq/access/full.json \
       --client-file=$HOME/.hq/access/client.json \
       --worker-file=$HOME/.hq/access/worker.json \
       --host <server-host> --client-port <p1> --worker-port <p2>
   chmod 600 ~/.hq/access/*.json
   ```
   `hq-server-up` auto-detects `~/.hq/access/full.json` and starts the server
   with `--access-file` (keys/ports then survive restarts). Restart the server
   to switch — do it while no workers are attached; note a clean `hq server
   stop` finalizes finished jobs (history no longer listed after restore) and
   **autoalloc pause state does not survive restarts** (re-`hq alloc pause` after).
2. **Publish the client half** (never the worker/full files) on the project
   filesystem, group-readable:
   `$SHARE/client/hq-current/access.json` (dirs 750, file 640, project group).
   Ship the matching `hq` binary in `$SHARE/bin` (access files are
   version-checked). Users set `HQ_SERVER_DIR=$SHARE/client`.
3. **Group-writable outputs.** Workers run `umask 002` (in the `.pbs` scripts)
   and users submit from setgid project dirs — task outputs (owned by the
   fleet owner) stay manageable by the submitter. Submitting from `$HOME`
   fails: the owner can't write there.
4. **Attribution convention.** The server can't distinguish submitters — job
   names carry a `<user>:` prefix instead. `$SHARE/bin/hq-submit` injects
   `--name "$USER:<cmd>"` for teammates; the operator's own clients apply it in
   `scripts/hq/hq-submit-hooks.sh` (sourced by the `hq()` shell function and by
   `hqb`), which also prefixes an *explicit* `--name` — without that, every
   named submit landed unowned. `hq-gpus` falls back to the job's submit
   directory for anything that still slips through, marking it `~`.
   Scheduling is FIFO + `--priority`; fairness is social, not enforced.

---

## Running it on FASRC (SLURM)

This is **implemented** in `scripts/hq/slurm/` and works today — but the
topology differs from Polaris, forced by one hard network constraint.

### The constraint that changes everything

FASRC **firewalls login↔compute on arbitrary ports, in BOTH directions**
(verified 2026-06-23). A worker on a compute node times out dialing an HQ
server on a login node, and a login-node client can't reach a compute-node
server's ports either. Only two paths are open:
- **compute↔compute** — workers reach a server that lives on a compute node;
- **ssh login→compute** — you can ssh to a node where you hold a job.

So the Polaris model (server on the login node, free and always-on) is
**impossible** here. Instead:

```
  you @ login ──ssh bridge──> hq server (compute node, in a small CPU alloc)
                                  │ dispatches over the open compute fabric
                                  ▼
                       hq workers (GPU compute nodes, sized on request)
```

### On-demand, not 24/7

FASRC GPU resources are shared (the lab owns only 2 `kozinsky_gpu` nodes), so
there is **no standing fleet**. You request an allocation sized to your needs,
attach workers, submit, and tear down. `hq-fleet` here is an *allocator*, not
the self-healing orchestrator.

### Install

```bash
# hq binary on PATH first (see "Install HyperQueue" above)
HQ_SCHED=slurm ~/dotfiles/scripts/hq/install.sh   # auto-detected anyway
# links hq-server-up + hq-fleet, renders ~/.hq/{server,worker}.sbatch
```

`shell/42-fasrc-hq.sh` (auto-sourced) defines the **`hq` ssh-bridge wrapper**:
every `hq …` runs on the server node via ssh, transparently.

### Day-to-day

```bash
hq-fleet up                                     # 1 GPU on gpu_requeue (polite default)
hq-fleet up -p kozinsky_gpu -g 4 -t 1-00:00:00  # a whole lab A100 node, guaranteed
hq-fleet up -p gpu_requeue  -N 2 -g 4           # +2 preemptable nodes (stacks)
hq submit --resource gpus/nvidia=1 -- python train.py
hq job list ; hq-fleet status
hq-fleet down            # stop workers
hq-fleet down --all      # stop workers + server
```

`hq-fleet up` auto-starts the server (idempotent — reused across calls) and
**stacks**: call it repeatedly to mix lanes (e.g. one guaranteed
`kozinsky_gpu` node + several preemptable `gpu_requeue` nodes), all attached to
the same server.

### Partition map (FASRC)

| Lane | Partition | Notes |
|---|---|---|
| server | `sapphire` (3-day) | tiny CPU alloc; **self-chains** — queues a dependent successor at startup, so it's effectively immortal despite the 3-day cap. sapphire is the only instant, non-preempting CPU partition (kozinsky/intermediate jam, unrestricted preempts). `HQ_SRV_*` knobs switch it |
| guaranteed GPUs | `kozinsky_gpu` (7-day) | lab-owned, only 2× (4×A100-80GB) nodes — don't monopolize |
| preemptable GPUs | `gpu_requeue` (3-day) | plentiful A100 pool; preempted tasks rerun (`--crash-limit`) |
| quick test | `gpu_test` (12h) | stricter: needs `-c <8` and `-m <64000M` per GPU |

### FASRC gotchas

- **No constraint directive** in `worker.sbatch`: `hq-fleet` passes
  `--constraint` (default `a100`) on the CLI so `-C ''` can actually drop it.
- **`hq` only works through the wrapper** (ssh to the server node). A bare
  `hq` with no server recorded prints how to start one.
- **No login-node shim/taskset** needed (FASRC's pid cap is effectively
  unlimited; the ALCF cgroup trap doesn't apply).
- **Server self-chains** past its 3-day walltime: each server queues a
  dependent successor (`sbatch --dependency=afterany`) that takes over at
  expiry. On handoff it lands on a new node, the access file + `~/.hq/server-node`
  update, the journal restores state, and workers reconnect via their retry loop
  (gap = seconds). `hq-fleet down --all` drops `~/.hq/server-stop` then scancels
  the chain; a successor released by that scancel sees the sentinel and exits.
  `HQ_NO_CHAIN=1` runs a single non-chaining server.

---

## PBS↔SLURM translation (reference)

| PBS | SLURM |
|---|---|
| `qsub script.pbs` | `sbatch script.sbatch` |
| `qstat -f <id>` / `qselect -s QRH` | `squeue -j <id>` / `squeue -u $USER -t PD,R` |
| `qdel <id>` | `scancel <id>` |
| `#PBS -A/-q/-l select=/-l walltime=` | `#SBATCH -A/-p/-N/-t` |
| `$PBS_NODEFILE` | `$SLURM_JOB_NODELIST` (or `srun` directly) |
| `mpiexec --ppn 1 hq worker start` | `srun --ntasks-per-node=1 hq worker start` |
| `hq alloc add pbs ...` | `hq alloc add slurm ...` |
| state codes `Q/R/H` | `PD/R/...` |

---

## Files in this repo

| File | Installs to | Role |
|---|---|---|
| **PBS / ALCF** | | |
| `scripts/hq/hq-server-up` | `~/.local/bin/` | start the server, cgroup-pinned + shimmed |
| `scripts/hq/hq-fleet` | `~/.local/bin/` | the 24/7 orchestrator (tick/run/up/down/status) |
| `scripts/hq/shim/nproc8.c` | `~/.hq/shim/` (compiled to `.so`) | fakes `get_nprocs()=8` |
| `scripts/hq/*.pbs.tmpl` | `~/.hq/*.pbs` (rendered) | capacity + bridge worker allocations |
| **SLURM / FASRC** | | |
| `scripts/hq/slurm/hq-server-up` | `~/.local/bin/` | ensure server in a compute-node CPU alloc |
| `scripts/hq/slurm/hq-fleet` | `~/.local/bin/` | on-demand allocator (up/status/down) |
| `scripts/hq/slurm/{server,worker}.sbatch.tmpl` | `~/.hq/*.sbatch` (rendered) | server + worker allocations |
| `shell/42-fasrc-hq.sh` | sourced by `.bashrc` | the `hq` ssh-bridge wrapper |
| **shared** | | |
| `scripts/hq/fleet.env.example` | `~/.hq/fleet.env` (seeded) | secrets/notifications — **never committed** |
| `scripts/hq/install.sh` | — | scheduler-aware; renders + links the above |

`~/.hq/fleet.env`, `~/.hq/journal`, `~/.hq/server-node`, logs, and
`~/.hq-server/` are runtime state — per-host, never in git.

## Two fleets: alpha (capacity) and bravo (preemptable)

Added 2026-08-15 after the `capacity` queue stalled every track for 44 h.

| | **alpha-fleet** (`hq-fleet`) | **bravo-fleet** (`bravo-fleet`) |
|---|---|---|
| queue | `capacity` | `preemptable` |
| shape | up to 4 nodes × 168 h | many **1-node** × ≤72 h |
| project limits | ~2 jobs (queued+running) | **10 running / 20 queued** |
| role | primary, stable | fills the gap when alpha is starved |

Both attach to the **same HQ server**, so they feed one task pool — task
submission does not change, only worker supply.

### Why bravo is many small jobs, staggered

- **The capacity limit is per *job*, not per node.** Two jobs is the whole
  project allowance on `capacity`; on `preemptable` it is ten. Narrow jobs
  therefore buy far more total capacity.
- **Backfill.** A 1-node job fits scheduling gaps a 4-node block cannot.
- **Decorrelated preemption.** Preemption kills a whole PBS job: losing one
  1-node allocation costs one node and HQ retries its tasks on the survivors;
  losing a 4-node allocation drops everything at once.
- **Staggered walltimes are essential.** Identical allocations submitted
  together *expire* together and recreate the gap the fleet exists to cover.
  `bravo-fleet` cycles `BRAVO_WALLTIMES` (default 72/60/48/36/24 h) so expiries
  land on different days, and tops up daily.

### Usage

```bash
bravo-fleet up 5      # seed: 5 one-node jobs, staggered walltimes
bravo-fleet run       # resident loop: +BRAVO_DAILY jobs/day, capped (tmux)
bravo-fleet status    # bravo + alpha jobs + HQ workers
bravo-fleet down      # qdel all bravo jobs
```

Knobs (env or `~/.hq/fleet.env`): `BRAVO_INITIAL`, `BRAVO_DAILY` (2),
`BRAVO_MAX_INFLIGHT` (10), `BRAVO_INTERVAL` (86400), `BRAVO_WALLTIMES`.
User crontabs are **denied** on Polaris, hence `run` as a tmux-resident loop —
re-run it after a login-node reboot, like `hq-fleet`.

### Two traps found while building it

1. **`hq-fleet` will qdel any job named `hq-bridge`.** With `HQ_NO_BRIDGE=1`
   the orchestrator drains leftover bridges, and `job_lookup` matches
   `Job_Name` exactly. A 4-node preemptable test submitted straight from
   `preempt-bridge.pbs` was cancelled within 6 minutes by our own fleet — it
   looked like a scheduler rejection but was self-inflicted. Bravo jobs are
   named `bravo-1n` precisely so they are invisible to that logic.
2. **`HQ_CAP_JOBS` changes need an orchestrator restart** — `hq-fleet` sources
   `fleet.env` once at startup, so editing the file under a running loop has no
   effect and it keeps topping up to the old target.

### Running the tickers: BOTH belong on `polaris-login-01`

`hq-fleet run` and `bravo-fleet run` are tmux-resident loops, and **tmux
sessions are per-node while login->login ssh is denied on Polaris**. A loop
started on login-02 therefore cannot be inspected, signalled or stopped from
login-01 — it just keeps submitting invisibly. Both loops belong in tmux on
**login-01**, next to the HQ server:

```bash
tmux new-session -d -s hq-fleet    '$HOME/.local/bin/hq-fleet run'
tmux new-session -d -s bravo-fleet '$HOME/.local/bin/bravo-fleet run'
```

`bravo-fleet run` takes a singleton lock (`~/.hq/bravo/run.lock`, host+PID) and
refuses to start a second loop on the same host; a stale lock is reclaimed.

**Reaching another login node.** `ssh polaris-login-02` works with the SHORT
hostname; the FQDN (`polaris-login-02.hsn.cm.polaris.alcf.anl.gov`) is refused
with `Permission denied (keyboard-interactive,hostbased)`. So a stranded loop
*can* be killed — use the short name:

```bash
ssh polaris-login-02 'tmux kill-session -t bravo-fleet; pkill -f "bravo-fleet run"'
```

If ssh is ever genuinely unavailable, a stranded loop still holds its PBS script
path in memory, so **retiring that path disarms it**: move the real script and
leave a stub whose queue does not exist — its `qsub` then fails at submit time
while the managed loop uses the new path. (Used once on 2026-08-15 before the
short-hostname ssh route was found; the stub has since been removed.) The bravo
worker lives at `~/.hq/bravo/worker.pbs`.

## Three fleets: charlie (prod/medium, on demand)

Added 2026-09-30. Polaris was full (2 of 560 nodes free) and bravo's
`preemptable` pool is only 56 nodes machine-wide: over Sep 15–30 bravo delivered
~690 node-hours, an average of 1.9 nodes (8 GPUs) against its 40-GPU ceiling,
with 44–136 h waits per 1-node job. `capacity` cannot grow (32 nodes total
across all projects, 1 running job per project). The only accessible queue that
reaches the 496-node production pool is the `prod` route: `small` (10–24 nodes,
3 h), `medium` (25–99 nodes, 6 h), `large` (100+, 24 h). Charlie uses `medium`.

| | **alpha** (`hq-fleet`) | **bravo** (`bravo-fleet`) | **charlie** (`charlie-fleet`) |
|---|---|---|---|
| queue | `capacity` | `preemptable` | `prod` → `medium` |
| shape | 4 nodes × 168 h | many 1-node × ≤72 h | 25 nodes × 6 h (100 A100s) |
| project limits | 1 running, 2 in flight | 10 running / 20 queued | 10 queued+running in `medium`, shared with teammates |
| HQ server | shared (`hq`) | PRIVATE (`hqb`) | PRIVATE (`hqb`) |
| supply policy | always on | always full queue | **on demand**, plus 1 standby |
| observed wait | 13 h gap per weekly handover | 44–136 h | 6–24 h |
| cost per allocation | 672 node-h | ≤72 node-h | 150 node-h |

### Why a ticker and not autoalloc

`hq alloc add` was the first choice: it submits only while tasks wait, ends idle
workers, and handles worker time limits natively. It works for debug-sized
lanes (the 2-node `debug-scaling` smoke on 2026-09-30, PBS 7670961 and 7671022,
came up cleanly with `pbsdsh`). It cannot drive `medium`: autoalloc sizes each
allocation to the waiting demand, one 2-GPU task produced `#PBS -l select=1`,
and `prod` rejects anything under 10 nodes. PBS keeps the **first** `-l select`
directive, so a trailing `-l select=25` in the extra args does not override it
(tested with a held job, PBS 7671494). Hence `charlie-fleet`: a `bravo-fleet`
clone that reads demand from the bravo server's JSON and submits fixed 25-node
jobs.

Policy per tick (every `CHARLIE_INTERVAL`, 300 s):

```
demand = tasks WAITING on hqb + tasks RUNNING on charlie workers
target = CHARLIE_MAX_QUEUED (2) if demand > 0 else CHARLIE_STANDBY (1)
submit until queued == target, never past CHARLIE_MAX_INFLIGHT (3)
```

Running tasks count as demand so the **next** allocation is already queued and
accruing eligible time while the current one runs. That is the whole answer to
"request the next allocation at the right time": on Polaris there is no way to
time a start, only to hold a place in line. `STANDBY=1` keeps one allocation
queued even when idle so work submitted later finds one close to starting; if
it starts empty its workers exit after `CHARLIE_IDLE` (20 min), about 8
node-hours, and the loop re-queues one. Nothing is ever auto-cancelled: a queued
job's eligible time is worth more than 8 node-hours.

```bash
charlie-fleet status        # jobs, demand, workers
DRY_RUN=1 charlie-fleet tick
charlie-fleet up 1          # force one allocation, ignoring demand
charlie-fleet down-queued   # drop the reserve; running allocations untouched
charlie-fleet down          # qdel everything charlie
```

The loop is `tmux charlie-fleet` on **login-01**, next to `hq-fleet` and
`bravo-fleet`. Worker script `~/.hq/charlie/worker.pbs` (rendered from
`scripts/hq/charlie-worker.pbs.tmpl`), job name `charlie-25n`, invisible to the
other two orchestrators (exact-name and `bravo-1n` prefix matches). Log
`~/.hq/charlie/fleet.log`; Slack on every submit, start and end.

### How a task survives an allocation boundary (verified 2026-09-30)

Nothing "transports" tasks between allocations. The HQ server on login-01 is the
durable queue; workers are disposable. Measured on the debug-scaling smoke with a
signal-trapping task, once via `hq worker stop` (PBS 7670961) and once via the
worker's `--time-limit` (PBS 7671022):

1. At the limit the worker sends **SIGINT** to each task and kills it about
   **1 s** later. There is no usable grace window; a graceful pre-expiry save is
   not possible.
2. The task returns to **WAITING**, not FAILED. `hq submit --help`: the crash
   counter is not incremented when the worker is stopped or reaches its time
   limit, so `--crash-limit 50` is never spent on chunk boundaries.
3. HQ re-places it on the next worker with enough time left. `--time-request 1h`
   (exp-26's submitter) keeps a task off a 6 h worker in its last hour; on a 22
   min test worker it would never be placed, so drills use `--time-request 5m`.
4. The task body resumes from `last.ckpt` (Lightning restores epoch, optimizer,
   LR schedule; the partial epoch is lost). With `save_last: true` on every
   validation epoch, G0's ~57 s epochs bound the training loss per boundary to
   under one epoch. The real cost is startup: **~10.5 min per leg** for the
   exp-26 body (attempt start → first training step), almost all of it the
   OpenEquivariance JIT compile, which both DDP ranks redo on every leg. That
   is 3 % of a 6 h charlie chunk and the first thing to shave if chunks ever
   get shorter (a persistent extension cache would remove most of it).
5. Lightning does log "Detected KeyboardInterrupt, attempting graceful
   shutdown" on the SIGINT, but the kill arrives before any checkpoint is
   written (`last.ckpt` mtime unchanged at the cut). Do not count on it.

Consequences for task bodies:

- Checkpoint at least once per epoch and never longer than ~15 min apart.
- HQ **truncates** a task's stdout/stderr when the task is requeued: the same
  `%{JOB_ID}`/`%{TASK_ID}` path is reopened. Use `%{INSTANCE_ID}` in the log
  path (`name.%{JOB_ID}.%{INSTANCE_ID}.out`) so every leg keeps its own file;
  exp-26's `submit_arm.sh` did not, so each preemption erased the previous
  leg's console log.
- A wandb id fixed to the run name (`resume: allow`) keeps one run across legs.

### Resume drill (2026-09-30, hqb job 959)

One real exp-26 G0 training task (2-GPU DDP, `--time-request 5m`, 28 epochs,
wandb offline, tag `drill`) on autoalloc `debug` workers with a 22-min time
limit, so it crossed boundaries every ~22 min:

| leg | node | allocation | ran | reached |
|---|---|---|---|---|
| 1 | x3004c0s13b1n0 | 7671734 (debug, 0 min wait) | 17:56–18:17 | epoch 9, step 1350; `last.ckpt` 36 s before the cut |
| 2 | x3001c0s7b0n0 | 7671923 (queued 5 s after the cut, 1 min wait) | 18:19–18:41 | resumed at epoch 10 from `last.ckpt`; epoch 20, step 2835 |
| 3 | x3001c0s7b0n0 | 7672112 (queued at the cut, 2 min wait) | 18:43–18:59 | resumed at epoch 21; finished epoch 27, step 3780; task FINISHED |

HQ reports one job, FINISHED, makespan 1 h 3 min. Each leg spent ~10.5 min in
startup (OEQ JIT) and the rest training at ~57 s/epoch; the three cuts cost
under a minute of training each.

Same wandb id across legs (`G0_graphene_ddp2_drill`, one offline dir per leg,
same id suffix), one continuous Hydra `train.log` in the run dir, per-leg HQ
logs `e26_G0_drill.959.{0,1,2}.out` thanks to `%{INSTANCE_ID}`. Two earlier
attempts (jobs 955, 957) failed on x3003c0s25b0n0, a debug-pool node with three
GPUs in `[GPU requires reset]` state; PBS handed the node back immediately after
it was freed, so the retry had to park a dummy task on it and use the `debug`
queue (separate per-user limit) to land elsewhere. `prod` nodes cannot be
MIG-toggled by users, so charlie is less exposed to this than the debug lanes.

The failed attempts also exposed a latent bug in exp-26's `hq_train_arm.sh`: the
body enables `set -e` after attempt 1, so on attempt 2 the checkpoint lookup
`CKPT=$(ls -1t "$OUTDIR"/last*.ckpt | head -1)` is fatal (exit 2) when no
checkpoint exists yet. It only bites when attempt 1 dies before the first
checkpoint; `|| true` on that line fixes it (applied to the drill's frozen copy
only).

### What the tests cost

Three debug-scaling allocations: 1 node × 1.3 min (probe), 2 nodes × 22 min,
1 node × ~22 min, plus one held job for the select test. Under 2 node-hours.
