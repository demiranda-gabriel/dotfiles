# HyperQueue standing fleet — setup & mirroring guide

How to stand up the always-on HyperQueue (HQ) fleet we run on Polaris on
another cluster, from these dotfiles. The goal: a meta-scheduler where you
`hq submit` tasks that **start within seconds** on a pool of nodes HQ keeps
attached for you — instead of waiting in the batch queue per job.

Reference implementation lives in `scripts/hq/`. It is **PBS-specific**
(Polaris, Aurora, and other ALCF PBS Pro systems); a SLURM-adaptation section
is at the end.

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

- **Capacity (primary):** a long job (`168h` on Polaris) on the `capacity`
  queue, named `hq-capacity`. ALCF allows only **2 capacity slots per project**
  (queued+running, *held jobs count*), so next week's job usually can't be
  queued until the current one ends.
- **Bridge (gap filler):** a `preemptable` job (`72h`), named `hq-bridge`,
  submitted whenever no capacity job is **running** or the running one has
  `< LEAD_HOURS` (24h) left. It can be preempted any time; HQ's default
  `--crash-limit 5` reruns interrupted tasks on surviving workers. Once
  capacity is healthy *and* no HQ task is running, the fleet `qdel`s the bridge.

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
  -A <proj> -q debug       -l filesystems=<fs> -l place=scatter
hq alloc add pbs --name preempt --time-limit 3days -- \
  -A <proj> -q preemptable -l filesystems=<fs> -l place=scatter
hq alloc list
```

(HQ injects `select=`/worker resources itself and auto-detects GPUs.)

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

## Adapting to a SLURM cluster (e.g. FASRC)

The server, workers, shim, and `hq alloc` autoalloc concepts are scheduler-
agnostic. What must be rewritten is the **direct-submission layer** in
`hq-fleet` and the `.pbs` scripts:

| PBS (this repo) | SLURM equivalent |
|---|---|
| `qsub script.pbs` | `sbatch script.sbatch` |
| `qstat -f <id>` / `qselect -s QRH` | `squeue -j <id>` / `squeue -u $USER -t PD,R` |
| `qdel <id>` | `scancel <id>` |
| `#PBS -A/-q/-l select=/-l walltime=` | `#SBATCH -A/-p/-N/-t` |
| `$PBS_NODEFILE` | `$SLURM_JOB_NODELIST` (or `srun` directly) |
| `mpiexec --ppn 1 hq worker start` | `srun --ntasks-per-node=1 hq worker start` |
| `hq alloc add pbs ...` | `hq alloc add slurm ...` |
| state codes `Q/R/H` | `PD/R/...` |

Easiest path: fork `hq-fleet`'s `job_lookup`/`act`/`tick` to call
`squeue/sbatch/scancel` and parse SLURM states, and write `.sbatch` workers
using `srun`. The orchestration *logic* (two lanes, lead-time bridge, idle
drain, server supervision) ports unchanged.

---

## Files in this repo

| File | Installs to | Role |
|---|---|---|
| `scripts/hq/hq-server-up` | `~/.local/bin/` | start the server, cgroup-pinned + shimmed |
| `scripts/hq/hq-fleet` | `~/.local/bin/` | the orchestrator (tick/run/up/down/status) |
| `scripts/hq/shim/nproc8.c` | `~/.hq/shim/` (compiled to `.so`) | fakes `get_nprocs()=8` |
| `scripts/hq/*.pbs.tmpl` | `~/.hq/*.pbs` (rendered) | capacity + bridge worker allocations |
| `scripts/hq/fleet.env.example` | `~/.hq/fleet.env` (seeded) | secrets/notifications — **never committed** |
| `scripts/hq/install.sh` | — | renders + links the above |

`~/.hq/fleet.env`, `~/.hq/journal`, logs, and `~/.hq-server/` are runtime state
— per-host, never in git.
