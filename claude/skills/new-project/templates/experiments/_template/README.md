# <experiment_name>

**Status**: planned | running | done-success | done-fail | abandoned
**Wandb**: <run url(s) — paste once submitted>
**Best ckpt**: <package under `models/`, or "not preserved">
**Outer commit**: <SHA of {{PROJECT}} repo at submission>
**Submodule pins**: <nequip-private SHA>, <allegro-private SHA>
**Date submitted**: YYYY-MM-DD

## Skeleton

```
<N>-<name>/
├── README.md     this file — status header, intent, outcome
├── configs/      training configs (base.yaml + <tag>.yaml per arm)
├── scripts/      experiment-specific scripts (submit, eval, analysis)
├── results/      committed figures + small derived CSVs
└── runs -> ../../runs/<N>-<name>   (gitignored symlink; outputs live here)
```

## Intent

What this tests. Hypothesis. Success criterion: a concrete metric threshold or
comparison the result must clear to count as `done-success`.

## Outcome

Final metrics. Qualitative result. Decision: keep / drop / iterate.

## Re-run

```bash
# Polaris (HyperQueue; re-entrant payloads, no --time-request)
hqb submit --resource gpus/nvidia=1 -- experiments/<N>-<name>/scripts/train.sh
```

## Curation checklist (on success)

- [ ] Package `.nequip.zip` → `models/<N>-<name>-<tag>.nequip.zip` (package-nequip-model skill)
- [ ] Row appended to `models/README.md`
- [ ] `gdrive-push models models`
- [ ] `Status` → `done-success`, committed
