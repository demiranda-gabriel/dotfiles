# DATA_MANAGEMENT.md

Classification of every top-level entry in this project root.
Drive root: `mir-backup:Current_members/Gabriel/projects/{{PROJECT}}/`.

## The rule

| Root | Tier | Durability |
|---|---|---|
| `experiments/` `software/` `scripts/` `notes/` `plans/` `writing/` `archive/` | **git-tracked** | GitHub, working branch |
| `data/` | **gdrive-tracked** | `…/{{PROJECT}}/data/` |
| `models/` | **gdrive-tracked** | `…/{{PROJECT}}/models/` (packaged `.nequip.zip` only, never raw `.ckpt`) |
| `papers/` | **gdrive-tracked** | `…/{{PROJECT}}/papers/` |
| `runs/` | **local-only** | none — regenerable from the experiment dir |

```bash
gdrive-push data data
gdrive-push models models
gdrive-push papers papers
```

## git-tracked

| Entry | Notes |
|---|---|
| `experiments/` | One dir per experiment, `N-<name>`, copied from `_template/`. Indexed in `experiments/README.md`. Each carries a gitignored `runs` symlink into `runs/`. |
| `software/` | uv-workspace members: `nequip-private`, `allegro-private` (git submodules on `develop`). |
| `scripts/` | Cross-experiment utilities (`link_experiment_runs.sh`, `check_experiment_status.py`). |
| `notes/` | Technical notes — how it works / what we found. |
| `plans/` | Research plans — what we intend to do next. |
| `writing/` | `abstracts/`, `reports/`, `figures/`, `slides/`. |
| `archive/` | Frozen reference material. |

## gdrive-tracked

| Entry | Notes |
|---|---|
| `data/` | Bulk datasets. Contents gitignored (`/data/*`); `data/README.md` tracked as the index. |
| `models/` | Curated packages. Contents gitignored; `models/README.md` tracked as the registry. |
| `papers/` | External literature PDFs. Contents gitignored; `papers/README.md` tracked as the index. Kept off git: PDF sets grow to 100+ MB. |

## local-only

| Entry | Notes |
|---|---|
| `runs/` | Training outputs, logs, checkpoints. |
| `.venv/` | uv env, rebuilt by `uv sync`. |
| `.claude/`, `.vscode/` (except `settings.json`) | Editor / agent state. |

## Root files

`README.md`, `MAP.md`, `CLAUDE.md`, `DATA_MANAGEMENT.md`, `pyproject.toml`,
`uv.lock`, `.python-version`, `.gitignore`, `.gitmodules` — git-tracked. No
other loose files at the root.
