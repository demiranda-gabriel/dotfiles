# Archive log — {{CYCLE_TITLE}}

**Owner:** Archivist agent (single writer — no other agent edits this file).
**Role spec:** master plan §Agent roles + the CLAUDE.md workflow section +
the `plan-tracks-workflow` skill §Archivist runbook.

Scope per pass (mechanical only — ambiguity is flagged, not acted on):
1. Push unpushed `plan(...)` commits to the remote.
2. Commit stragglers ONLY when clearly owned by a finished task; never
   `git add -A`.
3. gdrive-push keep-worthy bulk artifacts per DATA_MANAGEMENT.md tiers
   (via `eod-sync` / `gdrive-push` / `package-nequip-model` where available).
4. Verify curation registries and top-level-dir classification; flag gaps.

Append-only. One line per action; one block per pass, newest last.

<!-- Template:
## YYYY-MM-DD HH:MM — pass #N
- pushed: <branch> (<n> commits, through <sha>)
- committed: <path> ("plan(archivist): sweep — <why clearly owned>")
- gdrive-push: <local path> → <remote subpath> (<size>)
- verified: <registry/classification checks run, result>
- FLAGGED (needs user/track action, not taken): ...
-->

*(no passes yet)*
