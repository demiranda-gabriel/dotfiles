<!-- Append this section to the PROJECT CLAUDE.md (near the top). Fill
placeholders. RETIRE OR REPOINT it the moment the cycle ends — a stale
ground-truth pointer is worse than none. -->

## Active workflow: {{CYCLE_SLUG}} plan discipline ({{START_DATE}} →)

`{{MASTER_PLAN_PATH}}` is the **GROUND TRUTH** for current work
(master index + status dashboard; per-track checklists in
`{{PLAN_DIR}}/track_{X}.md`). If you were spawned to work on a track
("You are the Track X agent" or similar), read the master plan AND your track
file before doing anything. If you were spawned as the **supervisor** or the
**archivist**, read §Agent roles in the master plan: the supervisor is
read-only everywhere except `{{PLAN_DIR}}/supervisor_reports.md` and its
dashboard line — it cross-checks claimed progress vs artifacts/jobs and
reports to {{USER}}, never fixing discrepancies itself; the archivist is
mechanical-only — it pushes/commits/gdrive-pushes per its runbook, logs to
`{{PLAN_DIR}}/archive_log.md`, and flags anything ambiguous instead of acting.

Rules for track agents:

- Work your track's tasks **sequentially**. Before each step: propose it to
  {{USER}} and wait for approval. Exception: tasks that are clear, low-risk,
  and already fully specified in the plan (read-only analysis, parity checks,
  submitting a job whose config the plan already fixes) — do them directly
  and notify.
- **Always-ask list** (never notify-only): {{PROJECT ALWAYS-ASK LIST — e.g.
  launching (re)training, regenerating datasets, code changes beyond
  build/config, anything not in the plan, anything consuming a large share
  of {{COMPUTE_POOL}}}}.
- Update your track file as you go: check off done items; new items go under
  "Proposed adjustments" until {{USER}} approves; after each task append a
  short dated report (what / result / key numbers / artifact paths).
- **Editing rules (parallel agents share this working tree):** you own ONLY
  your track file + your one line in the master's status dashboard. Use Edit
  (never Write) on plan files, and re-read the file immediately before
  editing. Never touch another track's file or the master's shared sections.
- Commit your own plan file after each update:
  `git add {{PLAN_DIR}}/track_X.md && git commit -m "plan(trackX): ..."`.
  Commit **and push** before submitting any job, per the normal workflow.
- Long-form documentation stays in {{PROJECT DOC CONVENTION}} per the normal
  workflow; track reports link to it.
