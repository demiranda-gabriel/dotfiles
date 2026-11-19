#!/usr/bin/env bash
# Smoke test: Allegro tutorial (aspirin, 40 frames, 5 epochs, compile mode) on one GPU.
# Validates the uv env + editable nequip/allegro forks on a compute node.
# Data is pre-downloaded to runs/0-smoke/aspirin_data (compute nodes have no internet).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TAG=${TAG:-allegro_aspirin}
OUT="$ROOT/runs/0-smoke/$TAG"
export SMOKE_DATA_DIR="$ROOT/runs/0-smoke/aspirin_data"
cd "$ROOT"
nvidia-smi -L
.venv/bin/python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
exec .venv/bin/nequip-train \
  -cp "$ROOT/experiments/0-smoke/configs" -cn allegro_aspirin \
  hydra.run.dir="$OUT"
