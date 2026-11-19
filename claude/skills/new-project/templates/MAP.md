# MAP — where do I look for X

**Rule: the top-level directory name tells you the storage tier.**

| Looking for | Go to | Tier |
|---|---|---|
| An experiment's configs, scripts, README, result figures | `experiments/<N>-<name>/` | git |
| That experiment's checkpoints, logs, wandb dirs | `experiments/<N>-<name>/runs` → `runs/<N>-<name>/` | local-only |
| NequIP / Allegro source | `software/nequip-private`, `software/allegro-private` (submodules, `develop`) | git |
| Cross-experiment utilities | `scripts/` | git |
| Design docs, derivations, findings | `notes/` (index in `notes/README.md`) | git |
| What we intend to do next | `plans/` | git |
| Abstracts, reports, figures, slides | `writing/` | git |
| External literature PDFs | `papers/` (index in `papers/README.md`) | gdrive |
| Datasets, structures, trajectories | `data/` | gdrive |
| Curated `.nequip.zip` packages | `models/` | gdrive |
