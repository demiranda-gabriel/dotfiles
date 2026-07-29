---
name: plan-tracks-workflow
description: Scaffold and operate the plan-tracks multi-agent workflow — a versioned markdown plan as ground truth, parallel track agents with single-writer file ownership, a read-only supervisor, and an archivist for backups. Use when the user says "set up the plan-tracks workflow", "scaffold the track workflow", "plan discipline", "multi-agent plan for this project", or asks to organize a deadline/milestone push into parallel agent tracks. Also load it when spawned AS one of the roles ("you are the Track X agent / supervisor / archivist") in a project that lacks its own workflow section.
---

# plan-tracks-workflow

A discipline for running a deadline-driven body of work with multiple parallel
Claude Code sessions ("agents") coordinating **through files and git, not
shared memory**, with the human (Gabriel) as approval gate.

First proven on `multifidelity` (Polaris, Jul–Aug 2026 presentation push);
reference implementation: that repo's `notes/plans/aug06_presentation_plan.md`
+ `notes/plans/aug06/` + the "Active workflow" section of its `CLAUDE.md`.

## Core idea

1. **A markdown plan, versioned in git, is the single source of truth.**
   A master file is index + dashboard; per-track files hold the checklists.
2. **One writer per file.** Parallel agents share one working tree, so git
   branches do NOT isolate them — collisions happen at the filesystem level.
   Concurrency safety comes from ownership, not locking.
3. **Three-tier authorization** keeps the human in the loop without making
   them a bottleneck (see §Operating rules).
4. **Trust but verify:** track agents self-report; a read-only supervisor
   audits claims against artifacts; an archivist makes progress durable.
5. **Bootstrap via the project CLAUDE.md**, which every session auto-loads —
   so a one-line spawn prompt ("You are the Track B agent...") is enough.

## Roles

| Role | Writes | Job |
|---|---|---|
| **Track agent** (one per workstream) | its own `track_<X>.md` + its one dashboard line in the master | Execute its checklist sequentially; propose steps/adjustments; report per task |
| **Supervisor** | `supervisor_reports.md` + its dashboard line — read-only everywhere else | Cross-check claimed progress vs artifacts/jobs/git; watch timeline + shared-resource contention; flag violations and drift; **escalate, never fix** |
| **Archivist** | `archive_log.md` + git commits/pushes + gdrive pushes | Make progress durable: push track agents' commits, sweep clearly-owned stragglers, gdrive-push bulk artifacts, verify curation/classification rules; **mechanical only — no reports, no judgment calls** |
| **Human (Gabriel)** | master's shared sections; all approvals | Approve steps and adjustments; arbitrate escalations; staff/descope tracks; final assembly |

Role-purity rules that make the system trustworthy:
- The supervisor must stay read-only: its findings are credible precisely
  because it cannot mutate what it audits (its hygiene findings must never be
  self-audits). Detection = supervisor; remediation = archivist or tracks.
- The archivist must stay mechanical: if it grows report-writing duties it
  becomes a second supervisor *with* write access — the worst of both.
- Track agents never touch another track's file or the master's shared
  sections.

## Scaffolding procedure (what to do when asked to set this up)

0. **Prerequisites:** a git repo with a project `CLAUDE.md`; ideally
   `DATA_MANAGEMENT.md` + the gdrive scripts (bootstrap `~/dotfiles` first on
   a new cluster). Without gdrive, the archivist degrades to git-only.
1. **Devise the plan interactively** with the user in one session. Anchor the
   goal to an EXTERNAL success criterion (milestone text, deliverable date).
   Iterate: user annotates the draft (e.g. `->` arrow notes), you fold them
   in. Push for: concrete pass/fail criteria per task, explicit decision
   rules inside gates ("pick smallest N with mem ≤ 80% and wall ≤ 2.5 d"),
   a deliberate-cuts list, a fallback rule with a trigger date, and a
   shared-resources section (GPU/queue budget — see §Lessons).
2. **Create the file tree** from `templates/` in this skill dir
   (placeholders are `{{LIKE_THIS}}`):

   ```
   notes/plans/<cycle>_plan.md          ← templates/master_plan.md
   notes/plans/<cycle>/track_<X>.md     ← templates/track.md   (one per track)
   notes/plans/<cycle>/supervisor_reports.md ← templates/supervisor_reports.md
   notes/plans/<cycle>/archive_log.md   ← templates/archive_log.md
   ```

   `<cycle>` = short slug for the push (e.g. `aug06`). Move the agreed
   checklists verbatim into the track files; the master keeps only index,
   dashboard, roles, rules, and human-owned sections.
3. **Append the workflow section to the project `CLAUDE.md`** from
   `templates/claude-md-section.md`, filling placeholders (paths, resource
   pool, project-specific always-ask items).
4. **Commit the baseline** (plan files + CLAUDE.md, nothing else) with
   message `plan: <cycle> plan + multi-agent workflow baseline`, and push —
   the baseline must be on the remote before any agent submits jobs.
5. **Hand the user the kickoff prompts** (`templates/kickoff-prompts.md`) and
   remind them of cadence: spawn tracks now or descope them deliberately;
   supervisor on demand or ~daily; archivist at end of day (candidate for a
   scheduled/cron run since it is time-triggered and mechanical).

## Operating rules (the contract every agent follows)

1. **Approval-first.** Propose each step to the user and wait. Exception —
   *notify-only*: tasks that are clear, low-risk, AND already fully specified
   in the plan (read-only analysis, parity checks, submitting a job whose
   config the plan fixes) → do directly, notify.
2. **Always-ask list** (never notify-only): launching (re)training or long
   jobs not in the plan, regenerating datasets, code changes beyond
   build/config, anything off-plan, anything consuming a large share of the
   shared compute pool. Extend per project.
3. **Single-writer editing.** Own files only. `Edit` (string-replacement),
   never `Write`, on any plan file; re-read the file immediately before
   editing — a stale edit must fail loudly, not clobber.
4. **Proposals are staged.** New items go under "Proposed adjustments" and
   enter the checklist only after user approval. Approved decisions get a
   dated **Approved decisions** block: what, rationale, accepted risks.
5. **Reports are short and link out.** One dated block per task
   (what / result / key numbers / artifact paths) in the track file;
   long-form documentation stays in the project's existing convention
   (e.g. `experiments/<N>-<name>/README.md`) and is linked, not duplicated.
6. **Commit your own file after each update:**
   `git add <your file> && git commit -m "plan(<role>): ..."`. Never
   `git add -A` (risks pinning another agent's mid-edit state).
7. **Dashboard hygiene:** each agent keeps its one master line current
   (single line, edited via `Edit` with the old line as `old_string`).

## Archivist runbook

Wraps existing dotfiles machinery — do not reinvent:
- Run the **`eod-sync` skill** where available (scans DATA_MANAGEMENT.md
  repos, skips active experiments, commits+pushes, gdrive-pushes, packages
  models via `package-nequip-model` where relevant).
- Project addendum each pass: push unpushed `plan(...)` commits (pushing
  others' commits is safe — repo-level, no file contention); commit stragglers
  ONLY when clearly owned by a finished task, else flag; `gdrive-push`
  keep-worthy bulk artifacts per the project's data tiers; verify curation
  registries (e.g. `best_checkpoint_paths.csv`) have rows for new artifacts;
  check new top-level dirs are classified in `DATA_MANAGEMENT.md`.
- Append a one-line receipt per action to `archive_log.md`; anything
  ambiguous → flag in the log + tell the user, do not act.

## Supervisor runbook

Per review: read all plan files + dashboard; `git log`/`status`; job-queue
state (`hq job list`, `hq-fleet status`, `qstat`/`squeue` as applicable);
then **verify claims against artifacts** — checked boxes vs files on disk,
claimed numbers vs the READMEs they cite, claimed jobs vs the queue. Report
per track (done / in-flight / blocked-on-user), then cross-track: timeline
risk vs the deadline (with arithmetic, not vibes), shared-resource conflicts,
rule violations, plan drift, unstaffed tracks. Append to
`supervisor_reports.md`, update its dashboard line, summarize to the user
with concrete recommendations.

## Lifecycle & retirement

Cycle end (deadline passed or plan superseded): **retire or repoint the
CLAUDE.md workflow section immediately** — a stale ground-truth pointer is
worse than none, because every future session will dutifully follow it.
Keep the plan tree in git as the historical record.

## Lessons learned (bake these in; earned on multifidelity)

- **Cross-track resource contention must live in the MASTER.** Track files
  that are each locally coherent can still be mutually exclusive on the
  shared GPU pool; only a master-level shared-resources section (or the
  supervisor) surfaces it.
- **The plan doesn't staff itself.** Unspawned tracks sit at zero while the
  deadline burns. Staffing/descoping is an explicit user decision the
  supervisor should force, not drift.
- **Quantified gates pay off.** Decision rules written into the plan let
  agents act autonomously without scope creep; vague tasks bounce back as
  questions.
- **Speed/feasibility numbers don't transfer across hardware.** Flag every
  extrapolated benchmark (different GPU memory, inter-node vs single-node)
  as unvalidated until re-measured — a supervisor catch that saved a
  schedule.
- **Repo-hygiene rules interact with the workflow** (commit+push before job
  submission; classify new top-level dirs on introduction) — state them in
  the CLAUDE.md section so the supervisor can enforce them.
- **Bank cheap deliverables early** (e.g. a minutes-long controlled speed
  benchmark) before betting the calendar on long runs.
