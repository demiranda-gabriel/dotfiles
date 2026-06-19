#!/bin/bash
# hq-xpu-bind.sh — bridge HyperQueue's GPU resource scheduling to Intel GPUs.
#
# HQ v0.26.x only auto-detects NVIDIA/AMD GPUs and, for those, sets
# CUDA_VISIBLE_DEVICES / ROCR_VISIBLE_DEVICES automatically. It has no Intel
# (Level-Zero) equivalent. We register the PVC GPUs on each worker as a custom
# indexed resource `gpus/intel` (see the fleet PBS scripts), and this wrapper
# translates the indices HQ assigns to a task into ZE_AFFINITY_MASK so the task
# only sees its allotted GPU(s). Use it as a prefix:
#     hq submit --resource gpus/intel=1 -- /home/demiranda/.hq/hq-xpu-bind.sh <cmd...>
#
# HQ exposes the assigned indices in HQ_RESOURCE_VALUES_<name> (non-alnum chars
# in the name become '_', so gpus/intel -> HQ_RESOURCE_VALUES_gpus_intel).
set -euo pipefail

vals="${HQ_RESOURCE_VALUES_gpus_intel:-}"

# Fallback: if HQ named the env var differently, scan for any GPU-ish one.
if [ -z "$vals" ]; then
  for v in $(compgen -e | grep -E '^HQ_RESOURCE_VALUES_.*([Gg][Pp][Uu]|intel)'); do
    vals="${!v}"; [ -n "$vals" ] && break
  done
fi

if [ -n "$vals" ]; then
  export ZE_AFFINITY_MASK="$vals"
  echo "[hq-xpu-bind] ZE_AFFINITY_MASK=$ZE_AFFINITY_MASK" >&2
else
  echo "[hq-xpu-bind] WARNING: no GPU indices from HQ; leaving ZE_AFFINITY_MASK unset" >&2
fi

exec "$@"
