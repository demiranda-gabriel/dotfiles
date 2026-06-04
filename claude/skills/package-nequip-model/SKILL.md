---
name: package-nequip-model
description: Package a trained nequip/allegro/unequip checkpoint into a portable .nequip.zip using the producing job's uv env, then archive it to Google Drive. Use when the user says "package the model", "package this checkpoint", "back up the model/checkpoint to drive", "curate this run", "nequip-package", or wants to preserve a training run's best.ckpt. Raw .ckpt must never be the Drive artifact — always package first.
---

# package-nequip-model

Convert a training checkpoint to a self-contained `.nequip.zip` **in the
same uv environment that produced it**, then back the package up to Google
Drive with the `backup-to-gdrive` scripts.

## Why package before backing up

A raw `.ckpt` is only loadable against the exact `nequip` / `unequip` /
`allegro` source and versions in the training env. A `.nequip.zip` embeds
the model code via `torch.package`, so it survives env drift and moves
between clusters. Backing up a bare `.ckpt` is a latent failure: re-loading
it after a dependency bump can break silently. The package is the artifact;
the `.ckpt` is not.

## Workflow

1. **Identify the checkpoint and its project env.** The producing env is
   the project's `.venv` (one shared uv env per project). Use `best.ckpt`
   for the curated model unless the run's README says the monitored metric
   saved the wrong one (a known `monitored_metric=MSE` vs MAE gotcha).

2. **Build the package via SLURM, in the project root.** Packaging loads
   the full model and (for cuEquivariance / OpenEquivariance models) may
   compile backend kernels, so submit it as a job rather than running on a
   login node — never run model compute interactively (`[[feedback_slurm_only]]`).
   `gpu_test` is enough for a smoke package; use a real GPU partition only
   if a kernel compile demands it.

   ```bash
   sbatch -p gpu_test,kozinsky_gpu,gpu -t 0-00:30 -N1 --gres=gpu:1 \
     --mem 64G --wrap '
       cd <project_root> &&
       uv run nequip-package build \
         experiments/<N>-<exp>/outputs/<run>/best.ckpt \
         saved_models/packages/<exp>-<tag>.nequip.zip'
   ```

   `nequip-package build <ckpt_path> <output_path>` — the `.nequip.zip`
   extension is mandatory. `--mode` controls which compile modes are
   embedded (default `nequip`).

3. **Mind the import-closure constraint.** For custom model modules,
   the pickled module's import closure must avoid `lightning` and
   `nequip.data` package-attribute imports or `torch.package` fails — see
   `[[project_nequip_package_custom_model_constraint]]`.

4. **Verify it loads** before trusting the backup (quick load in the same
   env, or `nequip-package`'s info path), then record provenance: append a
   row to `saved_models/best_checkpoint_paths.csv`
   (`experiment, tag, holylabs_path, wandb_url, git_sha, date`).

5. **Back up the package, not the ckpt.**

   ```bash
   gdrive-push saved_models/packages/<exp>-<tag>.nequip.zip saved_models/packages
   ```

   Per-project Drive layout follows `DATA_MANAGEMENT.md`. Curated packages
   live under `saved_models/packages/<exp>-<tag>.nequip.zip`.

## Do not

- Push a raw `.ckpt` to Drive as the model-of-record.
- Package in a different/newer env than the one that trained the model.
- Run the build on a login node.
