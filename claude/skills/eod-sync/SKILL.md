---
name: eod-sync
description: End-of-day scan + backup across all research projects. Discovers every repo with a DATA_MANAGEMENT.md, skips experiments with active SLURM jobs, commits+pushes git-tracked changes, pushes gdrive-tracked data (packaging models as .nequip.zip first), and asks how to classify any new top-level entry not yet in the data-management plan — then updates the plan and proceeds. Also always syncs the ~/dotfiles repo (commit local edits, reconcile with the remote via rebase, push). Use when the user says "end of day", "eod sync", "eod-sync", "daily backup", "scan and back up my projects", "wrap up for the day", or invokes /eod-sync.
---

# eod-sync

A daily scan-and-backup runbook for the research projects. The
per-project `DATA_MANAGEMENT.md` is the **contract**: it says, for every
top-level entry, whether it is git-tracked, gdrive-tracked, or local-only.
This skill enforces that contract — committing and backing up what is
already classified, and pausing only to ask you about anything new the
plan doesn't yet cover.

Default behaviour: **apply the safe, classified actions automatically;
surface every decision point interactively (see Interaction model),
record the outcome where it belongs, then continue autonomously.** Make
no irreversible change (deletion, history rewrite) without explicit
confirmation.

## Interaction model (default)

Surface every decision point to the user **interactively, one at a time**,
with AskUserQuestion — never silently guess, never collapse distinct
choices into one lump, and never dump them all as plain prose for the user
to sort out. For each decision:

- Inspect the thing first (size, file types, git state, is-it-a-repo) so
  the options are concrete and correct.
- Present it as its own question with 2–4 options, the **recommended one
  first**, each with a one-line consequence.
- Act on that item only after the user answers; then move to the next.

This applies to **any** judgment call — not just classifying a new entry:
where a new file/dir belongs, whether to commit work-in-progress, whether
to add a `.gitignore` rule, any multi-GB or hard-to-reverse push, etc.
Decisions within one project may share a single AskUserQuestion call (as
separate questions), but each distinct decision stays its own question.

Only **truly unambiguous, safe mechanics** are applied without a prompt:
committing changes to already-classified git-tracked paths, pushing
already-classified gdrive-tracked data, pushing an existing local commit.
The interactive step is for the *decisions*, not the plumbing.

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

### 4. Dotfiles sync (`~/dotfiles`)
**Always sync the dotfiles repo too** — it is the cross-cluster source of
truth for shell config, scripts, and Claude skills (including this one).
It lives outside the projects root and has no `DATA_MANAGEMENT.md`, so it
is handled here explicitly, not by the per-project loop. It is git-only
(no gdrive tier).

- `git -C ~/dotfiles fetch`, then read `git status` and ahead/behind
  (`git rev-list --left-right --count @{u}...HEAD`).
- **Local uncommitted changes** (tracked edits, or new untracked files):
  these are real config edits, not disposable. Inspect the diff first so
  the message is honest, then stage + commit — safe mechanics, like a
  project's git-tracked changes (step 3b).
- **Behind the remote** (commits pushed from another cluster): reconcile.
  Pure fast-forward + clean tree → fast-forward. Local commits/edits **and**
  remote commits (cross-cluster divergence) → commit local first, then
  `git rebase origin/<branch>`. A clean rebase that keeps both sides needs
  no prompt; **surface any merge conflict interactively** (show the local
  vs incoming hunks; ask take-local / take-remote / manual) — never
  auto-resolve a dotfiles merge. When the same file was edited
  independently on two clusters, the goal is to keep both changes.
- **Ahead** (unpushed commits): push to the tracking branch.
- End on `0 0` and a clean working tree. Remind the user that the *other*
  cluster's checkout still needs a pull before its next edit, so the
  dotfiles don't re-diverge.
- Note: the active skill copies under `~/.claude/skills/` may be plain
  copies rather than symlinks into `~/dotfiles` (bootstrap skips a target
  that already exists). If a skill edit is committed here, also refresh
  the active copy so it takes effect this session.

### 5. Report
Per project, summarise: commits made (with SHAs) and pushed, Drive
pushes / packages built, experiments skipped (active jobs), plan entries
added, and anything still needing attention. Close with an overall
**PASS / NEEDS-ATTENTION** line per project. Add a final line for the
**dotfiles** repo (commit SHA + push, or already-clean / needs-attention).

## Guardrails
- Skip experiments with active SLURM jobs — never touch their in-flight outputs.
- Every decision point (new entry, WIP commit, new ignore rule, multi-GB / hard-to-reverse push) → surface it interactively, one at a time, per the **Interaction model**. For a new top-level entry, record the answer in `DATA_MANAGEMENT.md` before acting. Never silently guess.
- Models go to Drive only as `.nequip.zip`, never raw `.ckpt`.
- Never edit third-party / vendored / site-packages source.
- Confirm a recent push before deleting any local gdrive-tracked copy; deletion needs explicit user say-so.
- Commits/pushes target the current working branch.
- Always sync `~/dotfiles` too (step 4). Commit + push its tracked edits as safe mechanics, but on cross-cluster divergence surface merge conflicts interactively — never auto-resolve a dotfiles merge.

## Related skills
- `backup-to-gdrive` — push/pull/archive mechanics and the `mir-backup:` remote layout.
- `package-nequip-model` — package a checkpoint to `.nequip.zip` before backing it up.
- `sync-project` — the verification checks reused in step 3d.
