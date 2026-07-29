# Supervisor reports — {{CYCLE_TITLE}}

**Owner:** Supervisor agent (single writer — no other agent edits this file).
**Role spec:** master plan §Agent roles + the CLAUDE.md workflow section.
Read-only everywhere except this file and the supervisor dashboard line.

Method per review: read all plan files + dashboard; `git log`/`status`;
job-queue state; then **verify claims against artifacts** — checked boxes vs
files on disk, claimed numbers vs the sources they cite, claimed jobs vs the
queue. Escalate, never fix.

Append-only. One block per review, newest last.

<!-- Template:
## YYYY-MM-DD HH:MM — status review #N
Method: <what was read / cross-checked>
### Track A
- Done since last review: ...
- Claims verified / discrepancies: ...
- In flight / blocked on user: ...
### Track B / C
- ...
### Cross-track
- Timeline risk vs {{DEADLINE}}: <on track / at risk / fallback triggered>
  (show the arithmetic: remaining days vs serial-critical-path estimate)
- Shared resources: <reservations, conflicts between tracks, expiry cliffs>
- Discrepancies flagged (checklist vs artifacts, rule violations, plan
  drift, unstaffed tracks, repo hygiene): ...
### Recommendations for {{USER}}
1. ...
-->

*(no reviews yet)*
