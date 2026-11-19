# experiments/

One directory per experiment, `N-<name>` (N = next unused integer, permanent once
assigned). The next experiment is `1-<name>`.

## Starting an experiment

1. Copy `_template/` → `experiments/<N>-<name>/`.
2. Fill the README header and set `**Status**: planned`; add a row below.
3. Commit (with any submodule bumps) **before** submitting, so the SHA pins the run.
4. Run `python3 scripts/check_experiment_status.py` before committing status changes.

Status vocabulary: `planned | running | done-success | done-fail | abandoned`.

## Index

| Date | Experiment | Status | Intent |
|---|---|---|---|
