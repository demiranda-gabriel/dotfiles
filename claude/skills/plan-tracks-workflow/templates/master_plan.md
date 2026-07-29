# Plan: {{CYCLE_TITLE}} — MASTER

**This file is the ground truth for current work.** It is an index +
dashboard: the per-track checklists live in `{{PLAN_DIR}}/track_{X}.md`, each
owned by exactly one agent. Workflow rules: see §Workflow below and the
"Active workflow" section of the project CLAUDE.md.

**Goal / headline:** {{GOAL — one or two sentences, stated so that on the
deadline you can answer yes/no whether it was met}}

Context: {{EXTERNAL SUCCESS CRITERION — milestone text, deliverable, date;
quote it, don't paraphrase, so agents optimize the real target}}

Working days: ~{{N}}. {{SCHEDULE-CRITICAL PATH — what must launch first and
why}}

---

## Status dashboard

One line per role. **Each line is edited only by its owner** (use Edit with
the current line as `old_string`; keep it to one line).

- Track A ({{SCOPE_A}}): not started
- Track B ({{SCOPE_B}}): not started
- Track C ({{SCOPE_C}}): not started
- Supervisor: no reviews yet → `{{PLAN_DIR}}/supervisor_reports.md`
- Archivist: no passes yet → `{{PLAN_DIR}}/archive_log.md`

## Tracks (checklists live in the linked files)

| Track | File | Scope |
|---|---|---|
| A | [`{{PLAN_DIR}}/track_A.md`]({{PLAN_DIR}}/track_A.md) | {{SCOPE_A_LONG}} |
| B | [`{{PLAN_DIR}}/track_B.md`]({{PLAN_DIR}}/track_B.md) | {{SCOPE_B_LONG}} |
| C | [`{{PLAN_DIR}}/track_C.md`]({{PLAN_DIR}}/track_C.md) | {{SCOPE_C_LONG}} |

## Shared resources

<!-- Cross-track contention lives HERE, not in track files. Keep current. -->

- Compute pool: {{e.g. "standing HQ fleet, 12× A100-40GB; do not spill past
  the fleet"}}
- Standing reservations: {{e.g. "Track A holds 8/12 GPUs Jul 30–Aug 2 →
  B and C share 4; A's two runs cannot overlap (8+8 > 12)"}}
- Allocation expiry / walltime cliffs: {{e.g. "capacity job expires ~Aug 5 →
  restart files mandatory for any long run"}}

## Agent roles

- **Track agents (A, B, C):** work their track's tasks sequentially; propose
  each step to {{USER}} before executing (exception: clear, low-risk,
  fully-specified tasks → do + notify); maintain their track file (check off
  items, add proposals, append reports); own exactly one dashboard line.
- **Supervisor agent:** read-only across all track files, dashboard, git log,
  and job-queue state. Cross-checks claimed progress against artifacts,
  watches timeline risk and shared-resource contention, flags rule violations
  and plan drift. Writes dated reviews to `{{PLAN_DIR}}/supervisor_reports.md`
  (its only writable file besides its dashboard line) and reports the summary
  to {{USER}}. It never fixes discrepancies itself — it escalates them.
- **Archivist agent:** makes progress durable — pushes plan commits, sweeps
  clearly-owned stragglers, gdrive-pushes bulk artifacts, verifies curation/
  classification rules. Mechanical only; writable: its git/gdrive actions +
  `{{PLAN_DIR}}/archive_log.md` + its dashboard line. Ambiguity → flag,
  don't act.

## Workflow (summary — full rules in CLAUDE.md)

1. Approval-first: propose each step/adjustment to {{USER}} before executing.
   Notify-only exception for clear, low-risk, already-specified tasks.
2. Always-ask (never notify-only): {{PROJECT ALWAYS-ASK LIST — e.g.
   (re)training, dataset regeneration, code changes beyond build/config,
   off-plan work, large shares of the compute pool}}.
3. Single-writer files: agents edit only their own files + their one
   dashboard line. Use Edit (never Write) on plan files; re-read before edit.
4. Reports: short dated block per task in the track file; long-form docs go
   to {{PROJECT DOC CONVENTION — e.g. experiments/<N>-<name>/README.md}},
   linked from the report.
5. Commit your own plan file after each update:
   `git add {{PLAN_DIR}}/track_X.md && git commit -m "plan(trackX): ..."`.

## {{FINAL ASSEMBLY — slides / release / report}} (owned by {{USER}})

- [ ] {{assembly tasks and dates}}

## Deliberate cuts (mention as future work, do not start)

- {{explicit non-goals — scope creep becomes a visible decision}}

## Fallback rule

{{TRIGGER DATE + CONDITION → DOWNGRADED CLAIM. e.g. "If X stalls by <date>,
downgrade the claim to Y and let Z carry the narrative. Don't leave both
tracks half-finished."}}
