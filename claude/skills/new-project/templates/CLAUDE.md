# {{PROJECT}}

{{DESCRIPTION}} Started {{DATE}}.

## Layout

**Read [`MAP.md`](MAP.md) first.** The top-level directory name tells you the
storage tier; full contract in [`DATA_MANAGEMENT.md`](DATA_MANAGEMENT.md).
Don't park loose files at the root.

## Working rules

- **Intent lives in `plans/`, findings in `notes/`.** Plan task bullets need
  Gabriel's per-edit OK (propose the exact text in chat); a `# Reports` section
  at the bottom of the active plan is agent-writable.
- **Always ask first:** launching (re)training, regenerating datasets, code
  changes beyond build/config, anything consuming a large share of the HQ
  fleet, more than 3 parallel subagents/background tasks.
- **On material progress:** commit the git-tracked artefacts, push bulk ones per
  the tier rules, tell Gabriel in chat, then append a dated report to the plan.
- Report in chat with specifics — numbers, pass/fail, artefact paths.

## Env / tooling

- Python {{PYTHON}} uv workspace, `torch=={{TORCH}}`. `uv sync` from the root.
- Forks in `software/` are git submodules installed editable:
{{FORK_LINES}}
  Bump with `git submodule update --remote <path>` + `uv sync`, and commit the
  bump with the experiment that needs it.
- Compute: Polaris HyperQueue (`hqb submit …`); payloads re-entrant, no
  `--time-request`. Put `%{INSTANCE_ID}` in task log paths.
- WandB: `project={{PROJECT}}`, `group=<N>-<exp>`, `name=<tag>`.

## Experiments

Copy `experiments/_template/` → `experiments/<N>-<name>/`, fill the header,
index it in `experiments/README.md`, commit **before** submitting. Outputs go to
`runs/<N>-<name>/`, surfaced as `experiments/<N>-<name>/runs`
(`scripts/link_experiment_runs.sh`). Check status hygiene with
`python3 scripts/check_experiment_status.py`.

## NequIP / Allegro gotchas

- `compile_mode: compile` for all Allegro / `ModelFromPackage` runs; eager only
  for short debugging.
- FM packages use the 89-element vocab — use `type_names_from_package:${model_path}`,
  never a hardcoded type list.
- POTCARs: check the TITEL, never the directory name (`potpaw_PBE.5x/.64` ship a
  different Pt). Record TITEL + ZVAL + full md5 in every experiment README.
