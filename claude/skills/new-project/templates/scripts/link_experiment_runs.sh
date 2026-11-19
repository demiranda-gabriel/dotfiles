#!/usr/bin/env bash
# Recreate the per-experiment convenience symlinks
#
#     experiments/<N>-<exp>/runs                   ->  ../../runs/<N>-<exp>
#     experiments/archive/<cohort>/<N>-<exp>/runs  ->  ../../../../runs/archive/<cohort>/<N>-<exp>
#
# Since the 2026-09-10 cycle close, closed experiments live two levels deeper
# under experiments/archive/<cohort>/, so the link target depth is computed from
# where the experiment dir actually is rather than hardcoded. Their run outputs
# followed on 2026-09-23 into the mirrored runs/archive/<cohort>/ tree.
#
# so that opening one experiment dir shows its configs AND its outputs, without
# merging the two storage tiers into one directory.
#
# Why symlinks and not a real merge: experiments/ is the git source of truth and
# must survive; runs/ is scratch (90-day FASRC purge, netscratch symlink there).
# Merging them would leave .gitignore pattern-matching as the only thing keeping
# 20+ GB of outputs out of a 60 MB repo, and a purge would delete files
# interleaved with committed configs. A symlink gives the same single-place
# navigation while keeping the tiers physically separate: it dangles harmlessly
# after a purge and `git status` never sees the outputs.
#
# The links are gitignored (`experiments/**/runs`) because their targets are
# cluster-specific. Re-run this after a fresh clone, or after new runs appear.
#
# Usage:  scripts/link_experiment_runs.sh [-n]
#           -n   dry run (print what would change, touch nothing)

set -euo pipefail

DRY=0
[ "${1:-}" = "-n" ] && DRY=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
cd "$ROOT"

[ -d runs ] || { echo "no runs/ dir at $ROOT — nothing to link"; exit 0; }

made=0 skipped=0 pruned=0

# 1. create/refresh a link for every runs/<name> (live) or
#    runs/archive/<cohort>/<name> (archived) that has a matching experiment
for r in runs/*/ runs/archive/*/*/; do
  [ -d "$r" ] || continue
  r="${r%/}"
  name="$(basename "$r")"
  [ "$name" = archive ] && continue
  # an experiment lives either at the top level or inside one archive cohort
  expdir=""
  if [ -d "experiments/$name" ]; then
    expdir="experiments/$name"
  else
    for cand in experiments/archive/*/"$name"; do
      [ -d "$cand" ] && { expdir="$cand"; break; }
    done
  fi
  [ -n "$expdir" ] || { skipped=$((skipped + 1)); continue; }
  link="$expdir/runs"
  # one ../ per path segment in $expdir, so the target resolves from $expdir
  depth=$(printf '%s' "$expdir" | tr -cd '/' | wc -c)
  up=""; for _ in $(seq 0 "$depth"); do up="../$up"; done
  target="${up}$r"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "SKIP  $link exists and is NOT a symlink — leaving it alone" >&2
    continue
  fi
  if [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then continue; fi
  if [ "$DRY" = 1 ]; then echo "would link  $link -> $target"
  else ln -sfn "$target" "$link"; fi
  made=$((made + 1))
done

# 2. prune links whose target vanished (e.g. after a scratch purge)
for link in experiments/*/runs experiments/archive/*/*/runs; do
  [ -L "$link" ] || continue
  [ -d "$link" ] && continue          # resolves fine
  if [ "$DRY" = 1 ]; then echo "would prune dangling  $link -> $(readlink "$link")"
  else rm -f "$link"; fi
  pruned=$((pruned + 1))
done

printf 'linked %d, pruned %d dangling, skipped %d runs dir(s) with no experiment\n' \
  "$made" "$pruned" "$skipped"
