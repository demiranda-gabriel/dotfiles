---
name: eod-sync
description: End-of-day scan + backup across all research projects. Discovers every repo with a DATA_MANAGEMENT.md, skips experiments with active SLURM jobs, commits+pushes git-tracked changes, pushes gdrive-tracked data (packaging models as .nequip.zip first), and asks how to classify any new top-level entry not yet in the data-management plan — then updates the plan and proceeds. Use when the user says "end of day", "eod sync", "eod-sync", "daily backup", "scan and back up my projects", "wrap up for the day", or invokes /eod-sync.
---

# eod-sync

A daily scan-and-backup runbook for the research projects. The
per-project `DATA_MANAGEMENT.md` is the **contract**: it says, for every
top-level entry, whether it is git-tracked, gdrive-tracked, or local-only.
This skill enforces that contract — committing and backing up what is
already classified, and pausing only to ask you about anything new the
plan doesn't yet cover.

Default behaviour: **apply the safe, classified actions automatically;
ask about new/unclassified entries, record the answer in the plan, then
continue autonomously.** Make no irreversible change (deletion, history
rewrite) without explicit confirmation.

## Projects root

The directory holding the per-project repos. On FASRC this is
`/n/netscratch/kozinsky_lab/Lab/demiranda/projects` (override if run
elsewhere). **Skip `fm_benchmarks`** (excluded by the user) and any
directory without a `DATA_MANAGEMENT.md`.

## Procedure

### 1. Discover projects
List immediate subdirectories of the projects root that are git repos and
contain a `DATA_MANAGEMENT.md`. Process each in turn.

### 2. Active-job guard (do this once, up front)
`squeue -u "$USER"` to list running/pending jobs. For each, resolve its
working dir / submit script with `scontrol show job <id>` (grep
`WorkDir`/`Command`) and map it to a project + experiment directory.
Record the set of **active experiment dirs**. For the rest of the run:
never commit, move, push, or delete their in-flight outputs. List them as
"skipped (active job)" in the report. (Jobs in other projects, or
`fm_benchmarks`, just mean "don't touch that project's active dirs".)

### 3. Per project (one at a time)
Read the project's `DATA_MANAGEMENT.md` first — it is the source of truth.

**3a. Detect unclassified top-level entries.**
`ls -A` the project root. For each top-level entry, decide whether the
plan accounts for it: it is named under git-tracked / gdrive-tracked /
local-only, or it is matched by a `.gitignore` rule the plan explains.
Collect everything **not** accounted for.

For each unclassified entry: inspect it (size with `du -sh`, file types,
whether it is itself a git repo with a remote, what's inside) and **ask
the user** with AskUserQuestion where it belongs — git-tracked /
gdrive-tracked / local-only (offer the obvious recommendation first).
Then:
- Add it to the matching section of `DATA_MANAGEMENT.md` with a one-line note.
- If gdrive-tracked or local-only, add the matching `.gitignore` rule.
- Commit the plan (+ gitignore) update.

Only after the plan covers every top-level entry do you proceed
autonomously for that project. (Per the plan's own rule: every top-level
entry must appear under exactly one category.)

**3b. Git sync (classified, non-active).**
`git status`. For modified/deleted **tracked** files outside active
experiment dirs, and for untracked files under a **git-tracked** path,
stage + commit with a clear message and push to the current branch.
Respect each repo's log conventions (e.g. nequiph tracks SLURM `.out` as
provenance but gitignores `.err`). Leave active experiment dirs untouched.
If the repo is on a default/protected branch and the right target is
unclear, ask before pushing.

**3c. Drive sync (gdrive-tracked).**
For each gdrive-tracked path, confirm it is present and current on the
MIR-backup shared drive (`rclone lsf` / `rclone size` / `rclone check`).
If missing or materially changed, push it with the `backup-to-gdrive`
scripts (`gdrive-push` / `gdrive-archive`).
- **Models**: never push a raw `.ckpt`. Package it to `.nequip.zip` first
  with the `package-nequip-model` skill (built in the producing job's uv
  env, via SLURM), then push the package. See
  `[[feedback_nequip_package_before_drive]]`.
- Before deleting any local copy of a gdrive-tracked path, confirm a fresh
  push exists — and only delete if the user explicitly asked.

**3d. Verify.** Reuse the `sync-project` checks: working tree clean and
pushed; every gdrive-tracked path present on Drive.

### 4. Report
Per project, summarise: commits made (with SHAs) and pushed, Drive
pushes / packages built, experiments skipped (active jobs), plan entries
added, and anything still needing attention. Close with an overall
**PASS / NEEDS-ATTENTION** line per project.

## Guardrails
- Skip experiments with active SLURM jobs — never touch their in-flight outputs.
- New top-level entry → ask, record in `DATA_MANAGEMENT.md`, *then* act. Never silently guess a classification.
- Models go to Drive only as `.nequip.zip`, never raw `.ckpt`.
- Never edit third-party / vendored / site-packages source.
- Confirm a recent push before deleting any local gdrive-tracked copy; deletion needs explicit user say-so.
- Commits/pushes target the current working branch.

## Related skills
- `backup-to-gdrive` — push/pull/archive mechanics and the `mir-backup:` remote layout.
- `package-nequip-model` — package a checkpoint to `.nequip.zip` before backing it up.
- `sync-project` — the verification checks reused in step 3d.
