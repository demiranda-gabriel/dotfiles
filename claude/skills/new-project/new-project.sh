#!/usr/bin/env bash
# Scaffold a new research project with the tiered layout used by
# multifidelity/electrostatics: git repo + uv workspace + editable NequIP/Allegro
# forks as submodules + DATA_MANAGEMENT.md + experiment template + 0-smoke run.
#
# Usage:
#   new-project.sh <name> [options]
#
# Options:
#   -d, --description TEXT   one-sentence project description (README/CLAUDE.md/pyproject)
#   -C, --parent DIR         where to create the project (default: $PWD)
#   --forks LIST             comma list of fork specs (default: nequip,allegro). A spec
#                            is a known short name (nequip, allegro) or
#                            <dir>=<git-url>[@branch]
#   --python VER             (default 3.10)
#   --torch VER              (default 2.9.0 — cu128 wheels from PyPI)
#   --no-smoke               skip experiments/0-smoke (also skipped if allegro absent)
#   --no-sync                skip `uv sync` (and the smoke data download)
#   --gdrive                 create the Drive mirror (dry run, then push the READMEs)
#   --remote URL             add origin + push main (create the EMPTY repo first;
#                            with `gh` available, pass `--remote gh` to create it)
#
# The script never pushes anything without --gdrive / --remote.

set -euo pipefail

TPL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"

declare -A KNOWN=(
  [nequip]="nequip-private=git@github.com:mir-group/nequip-private.git@develop"
  [allegro]="allegro-private=git@github.com:mir-group/allegro-private.git@develop"
)

NAME="" DESC="" PARENT="$PWD" FORKS="nequip,allegro" PY=3.10 TORCH=2.9.0
SMOKE=1 SYNC=1 GDRIVE=0 REMOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--description) DESC="$2"; shift 2 ;;
    -C|--parent)      PARENT="$2"; shift 2 ;;
    --forks)          FORKS="$2"; shift 2 ;;
    --python)         PY="$2"; shift 2 ;;
    --torch)          TORCH="$2"; shift 2 ;;
    --no-smoke)       SMOKE=0; shift ;;
    --no-sync)        SYNC=0; shift ;;
    --gdrive)         GDRIVE=1; shift ;;
    --remote)         REMOTE="$2"; shift 2 ;;
    -h|--help)        sed -n '2,25p' "$0"; exit 0 ;;
    -*)               echo "unknown option $1" >&2; exit 2 ;;
    *)                NAME="$1"; shift ;;
  esac
done
[ -n "$NAME" ] || { echo "usage: new-project.sh <name> [options]  (-h for help)" >&2; exit 2; }
DESC="${DESC:-TODO: one-sentence description.}"
ROOT="$PARENT/$NAME"
if [ -e "$ROOT" ] && [ -n "$(ls -A "$ROOT")" ]; then
  echo "error: $ROOT exists and is not empty" >&2; exit 1
fi
mkdir -p "$ROOT"; cd "$ROOT"
DATE="$(date +%F)"

step() { printf '\n== %s\n' "$*"; }

step "layout"
cp -a "$TPL"/. .
mv gitignore .gitignore
mkdir -p data models papers runs software
[[ ",$FORKS," == *",allegro,"* ]] || SMOKE=0
[ "$SMOKE" = 1 ] || rm -rf experiments/0-smoke

step "git + submodules"
git init -q -b main
FORK_DIRS=()
IFS=, read -ra specs <<< "$FORKS"
for s in "${specs[@]}"; do
  spec="${KNOWN[$s]:-$s}"
  dir="${spec%%=*}"; rest="${spec#*=}"
  url="$rest"; branch=""
  # split a trailing @branch, but not the git@ of an ssh url
  if [[ "${rest##*/}" == *@* ]]; then url="${rest%@*}"; branch="${rest##*@}"; fi
  git submodule add -q ${branch:+-b "$branch"} "$url" "software/$dir"
  FORK_DIRS+=("software/$dir")
done
git submodule status

step "pyproject.toml"
echo "$PY" > .python-version
python3 - "$NAME" "$DESC" "$TORCH" "${FORK_DIRS[@]}" <<'EOF'
import re, sys
name, desc, torch, *members = sys.argv[1:]
pkgs = []
for m in members:
    txt = open(f"{m}/pyproject.toml").read()
    pkgs.append(re.search(r'^name\s*=\s*"([^"]+)"', txt, re.M).group(1))
deps = sorted(pkgs + [
    "cuequivariance-ops-torch-cu12>=0.10.0", "cuequivariance-torch>=0.10.0",
    "setuptools<81", f"torch=={torch}", "wandb>=0.26.0"])
q = lambda xs, ind: "\n".join(f'{ind}"{x}",' for x in xs)
out = f'''[project]
name = "{name}"
version = "0.1.0"
description = "{desc.replace('"', "'")}"
readme = "README.md"
requires-python = ">=3.10"
dependencies = [
{q(deps, "    ")}
]

[tool.uv.workspace]
members = [
{q(members, "    ")}
]

[tool.uv.sources]
''' + "".join(f"{p} = {{ workspace = true, editable = true }}\n" for p in pkgs) + '''
[dependency-groups]
dev = [
    "pytest>=9.0.3",
]
'''
open("pyproject.toml", "w").write(out)
EOF

step "placeholders"
FORK_LINES=""; PINS=""
for d in "${FORK_DIRS[@]}"; do
  sha="$(git -C "$d" rev-parse --short HEAD)"
  br="$(git config -f .gitmodules "submodule.$d.branch" || echo HEAD)"
  FORK_LINES+="  - \`$d\` ($br)"$'\n'
  PINS+="${PINS:+, }$(basename "$d") $sha"
done
FORK_LINES="${FORK_LINES%$'\n'}"
export NAME DESC DATE PY TORCH FORK_LINES PINS
grep -rlI '{{' --exclude-dir=.git --exclude-dir=software . | while read -r f; do
  python3 - "$f" <<'EOF'
import os, sys
p = sys.argv[1]; s = open(p).read()
for k, v in {"PROJECT": "NAME", "DESCRIPTION": "DESC", "DATE": "DATE", "PYTHON": "PY",
             "TORCH": "TORCH", "FORK_LINES": "FORK_LINES", "SUBMODULE_PINS": "PINS"}.items():
    s = s.replace("{{" + k + "}}", os.environ[v])
open(p, "w").write(s)
EOF
done
if [ "$SMOKE" = 1 ]; then
  sed -i 's/^The next experiment is `1-<name>`./The next experiment is `1-<name>`. `0-smoke` is the env validation run./' experiments/README.md
  echo "| $DATE | [\`0-smoke\`](0-smoke/) | planned | Env validation: Allegro tutorial on 1 GPU, compile mode |" >> experiments/README.md
fi

if [ "$SYNC" = 1 ]; then
  step "uv sync (throttled for the login-node pid cap)"
  UV_CONCURRENT_DOWNLOADS=4 UV_CONCURRENT_BUILDS=2 UV_CONCURRENT_INSTALLS=4 RAYON_NUM_THREADS=4 \
    uv sync -q
  .venv/bin/python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda)" 2>/dev/null
  if [ "$SMOKE" = 1 ]; then
    step "0-smoke data (aspirin) -> runs/0-smoke/aspirin_data"
    mkdir -p runs/0-smoke/logs
    .venv/bin/python - 2>/dev/null <<'EOF'
import os, zipfile
from nequip.data.datamodule.sgdml_datamodule import sGDML_CCSD_DataModule as M
from nequip.utils import download_url
d = "runs/0-smoke/aspirin_data"; os.makedirs(d, exist_ok=True)
p = download_url(M.URL_DICT["aspirin"], d)
if p.endswith(".zip"):
    zipfile.ZipFile(p).extractall(d)
print("ok", sorted(f for f in os.listdir(d) if f.endswith(".npz")))
EOF
    scripts/link_experiment_runs.sh
  fi
fi

step "initial commit"
git add -A
git commit -q -m "Scaffold $NAME project (new-project skill): tiered layout, uv workspace, fork submodules"
git log --oneline -1

if [ "$GDRIVE" = 1 ]; then
  step "Drive mirror (mir-backup:…/projects/$NAME/)"
  for d in data models papers; do gdrive-push -n -p "$NAME" "$d" "$d"; done
  for d in data models papers; do gdrive-push -p "$NAME" "$d" "$d" >/dev/null 2>&1 && echo "pushed $d/"; done
fi

if [ -n "$REMOTE" ]; then
  step "remote"
  if [ "$REMOTE" = gh ]; then
    gh repo create "$NAME" --private --source . --push
  else
    git remote add origin "$REMOTE"
    git push -u origin main
  fi
fi

printf '\nDone: %s\n' "$ROOT"
[ -n "$REMOTE" ] || echo "Next: create an empty private GitHub repo, then: git remote add origin <url> && git push -u origin main"
[ "$SMOKE" = 0 ] || echo "Smoke test: see experiments/0-smoke/README.md (Re-run)"
