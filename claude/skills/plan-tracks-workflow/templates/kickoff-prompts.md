# Kickoff prompts (copy-paste when spawning sessions)

One line is enough — the project CLAUDE.md section carries the rest.

**Scaffold a new cycle (new project / new push):**
> Set up the plan-tracks workflow for this project (use the
> plan-tracks-workflow skill). The goal is: <goal + deadline + external
> success criterion>. Let's devise the plan together first.

**Track agent:**
> You are the Track <X> agent. Follow the Active workflow section in
> CLAUDE.md.

**Supervisor:**
> You are the supervisor agent. Follow the Active workflow section in
> CLAUDE.md and give me a status review.

**Archivist:**
> You are the archivist agent. Follow the Active workflow section in
> CLAUDE.md and run a backup pass.

Cadence guidance:
- Track agents: spawn when staffing the track; re-spawn (or continue the
  session) per work session. Unstaffed tracks don't execute themselves —
  staff or descope deliberately.
- Supervisor: on demand or ~daily during a push; always before you make
  go/no-go decisions.
- Archivist: end of day; a natural candidate for a scheduled/cron run since
  it is time-triggered and mechanical.
