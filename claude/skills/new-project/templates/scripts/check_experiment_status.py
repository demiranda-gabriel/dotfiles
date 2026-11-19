#!/usr/bin/env python3
"""Catch experiment bookkeeping that has gone stale.

The `**Status**:` line in an experiment README is the one field nothing verifies,
so it rots silently — and `experiments/README.md` then inherits the rot. On
2026-08-07 four experiments were found sitting at `planned` while their own
directories held curated packages, committed figures, or (in exp-501's case) a
results table a few lines below the stale header. This script makes that class of
drift fail loudly instead.

Five checks:

  1. STALE      status is planned/running, but the experiment has completion
                evidence (best.ckpt, results/, RESULTS.md/REPORT.md, a committed
                figure, or curated packages).
  2. NO_STATUS  README has no `**Status**:` line at all.
  3. BAD_STATUS status word is not in the documented vocabulary.
  4. MISMATCH   the README status disagrees with the row in its index
                (the README wins — it is closer to the work).
  5. NOT_INDEXED  the experiment dir has no row in its index.

Layout note (2026-09-10): experiments live at two depths. Live ones sit at
experiments/<N>-<name>/ and are indexed in experiments/README.md; closed ones
sit at experiments/archive/<cohort>/<N>-<name>/ and are indexed in that
cohort's own experiments/archive/<cohort>/README.md. Both depths are checked,
each against the index that owns it.

Exit status: 0 clean, 1 findings, 2 usage/enviroment error. Findings are advisory
— a legitimately `running` experiment WILL trip check 1 once it writes its first
checkpoint. Silence it by moving the status on, or pass --ignore.

Usage:
    scripts/check_experiment_status.py [-q] [--ignore DIR[,DIR...]]

    -q / --quiet   only print findings, no summary
    --ignore       comma-separated experiment dir names to skip entirely
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# NOTE: kept compatible with Python 3.6 — the bare `python3` on Polaris login
# nodes is 3.6.15, and this must run without activating the uv venv.

VOCAB = {"planned", "running", "done-success", "done-fail", "abandoned",
         "stopped-early", "in progress"}
OPEN_STATES = {"planned", "running"}

# Evidence that an experiment has actually produced something.
FIGURE_SUFFIXES = {".png", ".pdf", ".svg"}
RESULT_DOCS = {"RESULTS.md", "REPORT.md"}


def find_root(start):
    # type: (Path) -> Path
    for p in (start, *start.parents):
        if (p / "pyproject.toml").is_file():
            return p
    print("error: project root (pyproject.toml) not found", file=sys.stderr)
    raise SystemExit(2)


def read_status(readme):
    # type: (Path) -> Optional[str]
    """First `**Status**:` value, lowercased, trailing prose stripped."""
    try:
        text = readme.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    m = re.search(r"^\*\*Status\*?\*?:?\*?\*?\s*(.+)$", text, re.MULTILINE)
    if not m:
        return None
    raw = m.group(1).strip()
    # take the leading status token(s): up to the first separator
    tok = re.split(r"\s*(?:—|--|\(|\[|<!--|,|\.|;)", raw, maxsplit=1)[0].strip()
    return tok.lower().strip("*` ")


def index_statuses(index):
    # type: (Path) -> Dict[str, str]
    """Map experiment dir -> status cell from the detailed index table."""
    out = {}  # type: Dict[str, str]
    if not index.is_file():
        return out
    row = re.compile(r"^\|\s*\d{4}-\d{2}-\d{2}\s*\|\s*\[`([^`]+?)/?`\][^|]*\|\s*([^|]+?)\s*\|")
    for line in index.read_text(encoding="utf-8", errors="replace").splitlines():
        m = row.match(line)
        if m:
            cell = m.group(2).strip().rstrip("⚠").strip()
            # index cells may wrap the status in markdown (`done-success`, **planned**)
            cell = cell.strip("`*_ ").strip()
            out.setdefault(m.group(1).rstrip("/"), cell.lower())
    return out


def completion_evidence(expdir, packages):
    # type: (Path, Path) -> List[str]
    """Signs the experiment produced output. Cheap checks only — no deep walks
    into the scratch tier, which can be tens of GB."""
    ev = []  # type: List[str]

    for doc in RESULT_DOCS:
        if (expdir / doc).is_file():
            ev.append(doc)

    results = expdir / "results"
    if results.is_dir() and any(results.iterdir()):
        ev.append("results/")

    figs = [p.name for p in expdir.rglob("*")
            if p.suffix.lower() in FIGURE_SUFFIXES and "runs" not in p.parts][:3]
    if figs:
        ev.append("figure(s): " + ", ".join(figs))

    # checkpoints, via the runs symlink if present (one level deep only)
    runs = expdir / "runs"
    if runs.is_dir():
        for ckpt in list(runs.glob("*/best.ckpt"))[:1] + list(runs.glob("best.ckpt"))[:1]:
            ev.append(f"checkpoint: runs/{ckpt.relative_to(runs)}")
            break

    # curated packages: models/<N>-<name>-<tag>.nequip.zip (flat, one dir)
    pkgs = sorted(packages.glob(expdir.name + "-*.nequip.zip"))[:3] if packages.is_dir() else []
    if pkgs:
        ev.append("curated packages: " + ", ".join("models/" + p.name for p in pkgs))

    return ev


def main():
    # type: () -> int
    ap = argparse.ArgumentParser(description="Flag stale experiment status bookkeeping.")
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("--ignore", default="", help="comma-separated experiment dirs to skip")
    args = ap.parse_args()

    root = find_root(Path(__file__).resolve().parent)
    exp_root = root / "experiments"
    if not exp_root.is_dir():
        print("error: no experiments/ dir", file=sys.stderr)
        return 2

    skip = {s.strip() for s in args.ignore.split(",") if s.strip()}
    findings = []  # type: List[Tuple[str, str, str]]

    # (experiment dir, index that owns it). Live experiments are indexed by
    # experiments/README.md; archived ones by their cohort README.
    targets = []  # type: List[Tuple[Path, Path]]
    live_index = exp_root / "README.md"
    archive_root = exp_root / "archive"
    for d in sorted(exp_root.iterdir()):
        if not d.is_dir() or d.name.startswith("_"):
            continue
        if d == archive_root:
            for cohort in sorted(archive_root.iterdir()):
                if not cohort.is_dir() or cohort.name.startswith("_"):
                    continue
                cohort_index = cohort / "README.md"
                for e in sorted(cohort.iterdir()):
                    if e.is_dir() and not e.name.startswith("_"):
                        targets.append((e, cohort_index))
            continue
        targets.append((d, live_index))

    index_cache = {}  # type: Dict[str, Dict[str, str]]
    for expdir, index_path in targets:
        if expdir.name in skip:
            continue
        key = str(index_path)
        if key not in index_cache:
            index_cache[key] = index_statuses(index_path)
        idx = index_cache[key]
        readme = expdir / "README.md"
        if not readme.is_file():
            findings.append(("NO_STATUS", expdir.name, "no README.md"))
            continue

        status = read_status(readme)
        if status is None:
            findings.append(("NO_STATUS", expdir.name, "README has no **Status**: line"))
        elif status not in VOCAB:
            findings.append(("BAD_STATUS", expdir.name,
                             f"{status!r} not in vocabulary ({', '.join(sorted(VOCAB))})"))

        if status in OPEN_STATES:
            ev = completion_evidence(expdir, root / "models")
            if ev:
                findings.append(("STALE", expdir.name,
                                 f"status {status!r} but found: " + "; ".join(ev)))

        if expdir.name not in idx:
            findings.append(("NOT_INDEXED", expdir.name, "no row in experiments/README.md"))
        elif status and idx[expdir.name] != status:
            findings.append(("MISMATCH", expdir.name,
                             f"README {status!r} vs index {idx[expdir.name]!r} "
                             "(README wins — update the index)"))

    order = {"STALE": 0, "MISMATCH": 1, "NOT_INDEXED": 2, "NO_STATUS": 3, "BAD_STATUS": 4}
    findings.sort(key=lambda f: (order.get(f[0], 9), f[1]))

    for kind, name, detail in findings:
        print(f"{kind:<12} {name:<34} {detail}")

    if not args.quiet:
        n = len([1 for e, _ in targets if e.name not in skip])
        print(f"\n{n} experiments checked, {len(findings)} finding(s).")
        if findings:
            print("A legitimately in-flight experiment can trip STALE once it writes "
                  "its first checkpoint — move its status on, or use --ignore.")

    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
