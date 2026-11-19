# 0-smoke

**Status**: planned
**Wandb**: none (no logger — smoke test)
**Best ckpt**: not preserved
**Outer commit**: <SHA at submission>
**Submodule pins**: {{SUBMODULE_PINS}}
**Date submitted**: YYYY-MM-DD

## Intent

Validate the fresh env on a compute node: torch sees the GPU, the editable
forks import, and `compile_mode: compile` trains end to end. Config is
`software/allegro-private/configs/tutorial.yaml` verbatim except
`data_source_dir`, which reads `$SMOKE_DATA_DIR` (aspirin is pre-downloaded to
`runs/0-smoke/aspirin_data/` on the login node; compute nodes have no internet).

Success criterion: `train` + `test` both complete, `last.ckpt` written, finite
test metrics.

## Outcome

<pending>

## Re-run

```bash
hqb submit --resource gpus/nvidia=1 --name 0-smoke \
  --stdout 'runs/0-smoke/logs/%{JOB_ID}.%{INSTANCE_ID}.out' \
  --stderr 'runs/0-smoke/logs/%{JOB_ID}.%{INSTANCE_ID}.err' \
  -- experiments/0-smoke/scripts/train.sh
```
