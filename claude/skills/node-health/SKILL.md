---
name: node-health
description: Inspect a login node's resource state (cgroup pid/memory/CPU budget, load vs. real saturation) and reap stale PIDs that leak from VS Code/Cursor tunnels. Use when the user says "check the node", "node health", "the login node is slow", "commands are hanging", "my shell froze", "clean up stale processes", "am I near the pid limit", or when a session dies with "fork: retry: Resource temporarily unavailable". Also run it proactively before launching anything thread-heavy on a login node.
---

# node-health

Wraps `node-health`, installed by `~/dotfiles/bootstrap.sh` into `~/.local/bin/`.

## The failure mode this exists for

Cluster login nodes confine each user to a cgroup with a hard pid cap **that
counts threads, not processes** (Polaris: 256 pids, 8 GB, 8 cores). When it
fills, every `fork()` and `pthread_create()` fails with `EAGAIN`. Bash does not
error out — it retries with exponential backoff, so the symptom is *"commands
run with extreme delay"* rather than a clean message. Node/Electron-based tools
(Claude Code, VS Code servers) simply freeze.

The trap is that login nodes report the machine's **raw core count** (256 on
Polaris), so any library that sizes a thread pool from `get_nprocs()` — ffmpeg,
torch, OpenBLAS, the HiGHS solver inside `hq` — tries to allocate a 256-thread
pool inside a 256-*pid* budget that is already two-thirds full.

Incident of record: 2026-08-13, an ffmpeg transcode wedged `polaris-login-01`
for hours. `hq`'s server on that node kept answering over TCP the whole time
(long-lived processes are unaffected) while nothing new could start — that
contrast is the fingerprint.

## Usage

```bash
node-health                      # report only — NEVER kills. The default.
node-health --clean              # reap the CONFIDENT stale set (SIGTERM)
node-health --clean --aggressive # also reap SUSPECT (read the list first)
node-health --min-age 30         # leaked-shell age threshold, minutes (default 60)
node-health --brief              # one line, for prompts/cron
```

Exit codes: `0` healthy, `1` warn (>60% pids, or the cap was hit before),
`2` critical (>85%), `3` usage error.

## How to drive it

1. **Always run bare first** and show the user the findings. It is report-only
   by default precisely so cleanup is a separate, consented step.
2. **Get approval before `--clean`.** It is low risk but it kills processes.
3. **Never reach for `--aggressive` on your own.** SUSPECT means "argless
   orphaned shell not traceable to a VS Code/Cursor CLI" — plausible but
   unproven. Show the list and let the user decide.
4. **Zombies are reported, never killed** — killing a zombie is a no-op; only
   the parent reaping (or dying) clears it.

## What it classifies as stale

**CONFIDENT** (what `--clean` reaps):

- *Leaked argless shells* — cmdline is exactly `/bin/sh`, zero children,
  single-threaded, older than `--min-age`, and parented by a VS Code/Cursor CLI
  process. `code tunnel` orphans roughly one per day and never reaps them; a
  month of uptime is ~30 pids of pure drift.
- *Orphaned CLI agent hosts* — `code --cli-data-dir DIR agent host` where no
  live process references `DIR`. This is the leftover after moving to per-node
  data dirs (`~/.vscode/cli` vs `~/.vscode/cli-polaris-login-02`).

**REPORTED, never killed — duplicate VS Code server stacks.** A VS Code update
installs a *new* server version, but windows opened before the update keep the
*old* server alive. Both run at once at 20–60 threads each, and it compounds
with every update — on 2026-08-15 the stale version was 58 threads, the single
largest consumer on the node, more than three Claude sessions combined. The
report names each running version, marks which one `lru.json` considers current,
and totals the cost of the stale ones. Fix by closing or reloading the windows
still bound to the old version; `node-health` will not kill them, because each
one backs a live editing session. It also lists installed-but-unused versions,
which are ~700 MB each on disk.

**Never killed:** anything not owned by you, anything with children, PID 1, the
tool itself, and every ancestor of the tool — so your shell, tmux server, and
Claude session are structurally safe.

The rule that matters for safety: a leaked shell has **no arguments**. The live
`code-server` wrapper is also a `sh`, but it carries arguments, so a naive
"kill all sh" would take down the running server while `node-health` will not.

## Reading the output

- **PID BUDGET** is the section that matters. `cap hit N times` comes from
  `pids.events` and is cumulative for the life of the cgroup — nonzero means
  this node has wedged you before.
- **Load average is a red herring.** A shared login node routinely shows load
  150+ while sitting 80–90% idle, because load counts `D`-state I/O waiters
  from other users. The report prints running vs. uninterruptible counts so you
  can tell real saturation from queue-depth noise. Only worry if *your* own
  processes are in `D`.
- **CPU** shows your cgroup quota against the node's core count — that gap is
  the thread-pool trap in one line.

## Prevention

Cap thread pools for anything run on a login node:

```bash
export OMP_NUM_THREADS=8 MKL_NUM_THREADS=8 OPENBLAS_NUM_THREADS=8
ffmpeg -threads 4 -filter_threads 2 -filter_complex_threads 2 ...
LD_PRELOAD=~/.hq/shim/nproc8.so <cmd>   # generic: fakes 8 CPUs (Polaris)
```

Better still, run real work through the batch system. See the Polaris/FASRC
HyperQueue sections of `~/.claude/CLAUDE.md`.

## When the node is already wedged

If `ssh` to the node produces **no output at all** and commands hang, `fork()`
is failing and you cannot start `node-health` (or any other binary). From an
**already-open** shell on that node, use bash builtins only — `kill`, `read`,
`[[ ]]` and globbing need no fork:

```bash
for d in /proc/[0-9]*; do
  [[ -O $d ]] || continue
  read -r c < "$d/comm" 2>/dev/null || continue
  [[ $c == sh ]] && kill "${d#/proc/}"
done
```

With no open shell on the node, it will **not** self-heal — the pid holders are
persistent (`code tunnel`, agent hosts, VS Code server workers). Move to another
login node and open a support ticket for the wedged one.

`node-health` itself is written to survive this: the scan and kill paths use
only bash builtins, no `ps`/`awk`/`grep`/`sort`/`date`. It has been verified to
produce a full report with `PATH` set to a nonexistent directory.

## Portability

Auto-detects the cgroup layout: ALCF-style `/sys/fs/cgroup/users/$USER`,
systemd cgroup v2 `user.slice/user-<uid>.slice`, and cgroup v1. Falls back to
`ulimit -u` with a thread count summed from `/proc` when no pid controller is
present. Requires bash 4.2+.
