# {{PROJECT}}

{{DESCRIPTION}} Started {{DATE}}.

## Quick start

```bash
git clone --recurse-submodules <remote> {{PROJECT}} && cd {{PROJECT}}
uv sync                              # Python {{PYTHON}}, torch {{TORCH}}, editable forks
scripts/link_experiment_runs.sh      # per-experiment runs/ symlinks
gdrive-pull papers papers            # literature (gdrive-tracked)
```

See [`MAP.md`](MAP.md) for where things live and
[`DATA_MANAGEMENT.md`](DATA_MANAGEMENT.md) for the storage tiers.
