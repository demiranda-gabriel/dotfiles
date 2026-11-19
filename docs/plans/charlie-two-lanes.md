# Charlie two-lane plan (PARKED 2026-10-15)

Status: proposal only, nothing implemented. Parked by Gabriel on 2026-10-15;
resume on request.

## Goal

- Two charlie allocations running simultaneously, both always on (even when idle):
  - lane `m`: 25 nodes, prod -> medium, 6 h
  - lane `s`: 10 nodes, prod -> small, 3 h
- HQ should place tasks on medium-lane GPUs before small-lane GPUs (medium lives longer).

## 1. Lanes in one ticker (`scripts/hq/charlie-fleet`)

- `CHARLIE_LANES="m s"`; per-lane state dir `~/.hq/charlie/<lane>/` (size, waits.tsv,
  paused, last state). Waits are per lane: queues have different wait distributions.
- PBS names `charlie-m` / `charlie-s` (qselect -N per lane); `charlie-25n` is stale anyway.
- `cmd_tick` loops over lanes: per-lane running/queued, max_remaining_min, lead.
  One process in tmux `charlie-fleet` (256-pid login cgroup).
- `size|pause|resume|down [lane]`; no lane = both. Status/notify carry the lane.
- Small lane: seed lead 60 min (no history); clamp lead <= ~150 min (walltime 180 min
  minus margin), else every successor is queued the moment its predecessor starts.

## 2. Lane-scoped handover (`charlie-worker.pbs.tmpl`) — MUST land before lane s exists

`handover_decision` drains every older worker with the `fleet/charlie` marker. With two
lanes a new medium allocation would drain the small lane (and vice versa).
- Add marker `lane/charlie-m|s` at worker start; keep `fleet/charlie` (pins unchanged).
- Drain only older allocations of the SAME lane; demand()/max_remaining_min() per lane.

## 3. Medium-first placement

HQ v0.26.2 has no worker priority. Only lever: resource request variants (job-file only).
Docs: "If in a given moment more configuration are possible for a given task, the
configuration first defined has a higher priority." Unverified whether that holds ACROSS
workers (HQ's scheduler solves globally with HiGHS, so plausibly yes).

- 3a. Test first (~15 min, login node, no GPUs): scratch HQ server (+ nproc shim), two
  local workers with fake gpus, one with marker `lane_m`; 20 sleep tasks with variants
  `{gpus=1, lane_m=1}` then `{gpus=1}`; check the marked worker fills first.
- 3b. If it holds: medium workers advertise `lane_m=sum(1000)`; add the 2-variant request
  in hqx `build_job_file` and have `hq-fleet-wrap` turn GPU `submit`s into job files.
  `HQ_RESOURCE_VARIANT` shows the lane chosen.
- Fallback: small-lane workers on a THIRD HQ server; the hqx router spills waiting jobs
  there only when bravo is full (deterministic; costs a server, keys, server-up, a third
  hq-gpus-all section).
- Free in both: `--time-request` > small lane's remaining walltime keeps a task off it.
- No live migration small -> medium: small allocations end every 3 h and requeue anyway.

## 4. Display and docs

hq-gpus / hq-gpus-all label allocs charlie-m / charlie-s; `charlie-fleet status` per lane;
update docs/hyperqueue-fleet.md (charlie) and claude/CLAUDE.md (Charlie lane row).

## 5. Testing and rollout

DRY_RUN tick per lane; handover fixture test (mixed-lane worker list -> medium successor
never drains small). Rollout: pause ticker, deploy worker script, adopt existing medium
chain as lane m by PBS id, restart ticker, let lane s cold-start.

## Open decisions (as of 2026-10-15)

- Budget: 35 nodes always on = 840 node-h/day (3,360 GPU-h/day). Check `sbank` first;
  option `CHARLIE_S_ALWAYS_ON=0` (small lane only on demand).
- Whether to build 1, 2, 4, 5 regardless of the step-3a outcome.
