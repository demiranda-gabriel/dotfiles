#!/bin/bash
# Bring up (or report) the VS Code *tunnel* on a FASRC compute node.
#
# Submits vscode.job as a SLURM batch job that runs `code tunnel --name
# cannontunnel`, then follows the job's output so you can (a) complete the
# one-time GitHub device-code login when the cached credential has lapsed and
# (b) grab the vscode.dev URL. Idempotent: if the tunnel job is already running
# it just prints how to connect instead of submitting a second one.
#
#   vscode            # up: submit if needed, then show connect info
#   vscode status     # show job state + tunnel name + connect URL
#   vscode down       # cancel the tunnel job
#   vscode log        # follow the job output (Ctrl-C is safe; job keeps running)
#
# The tunnel lives in the batch job, so it survives SSH disconnects and login-
# node hopping, and dies when the job's walltime ends (then just run `vscode`
# again). See docs/alcf-vscode-tunnel.md for the tunnel model.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/out"
JOBNAME="vscode-tunnel"                 # sbatch -J name we submit under
TUNNEL_JSON="$HOME/.vscode/cli/code_tunnel.json"

# Registered tunnel name (falls back to the historical default).
NAME="cannontunnel"
if [[ -r "$TUNNEL_JSON" ]]; then
  n="$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' "$TUNNEL_JSON")"
  [[ -n "$n" ]] && NAME="$n"
fi
URL="https://vscode.dev/tunnel/$NAME"

# Running/pending tunnel job(s): matches this script's job name OR the legacy
# plain "vscode.job" name. Prints "JOBID STATE NODE" per match.
find_job() {
  squeue -u "$USER" -h -O "JobID:20,Name:32,StateCompact:8,NodeList:32" 2>/dev/null \
    | awk '$2=="'"$JOBNAME"'" || $2=="vscode.job" {print $1, $3, $4}'
}
job_state() { find_job | head -1 | awk '{print $2}'; }

connect_banner() {
  echo "======================================================================"
  echo " VS Code tunnel '$NAME' is UP"
  echo "   Connect:    $URL"
  echo "   or VS Code: Remote Explorer > Tunnels > $NAME > Connect"
  echo "======================================================================"
}

cmd="${1:-up}"
case "$cmd" in
  status)
    j="$(find_job)"
    if [[ -n "$j" ]]; then
      echo "tunnel job: $j"
      echo "tunnel:     $NAME"
      echo "connect:    $URL"
    else
      echo "tunnel job: (none) — start with:  vscode"
    fi
    ;;

  down)
    scancel -u "$USER" --name="$JOBNAME"   2>/dev/null || true
    scancel -u "$USER" --name="vscode.job" 2>/dev/null || true
    echo "cancelled any running tunnel job ($NAME goes offline)."
    ;;

  log)
    tail -F "$OUT" ;;

  up)
    st="$(job_state)"
    if [[ "$st" == "R" ]]; then
      echo "Tunnel already running ($(find_job | head -1))."
      connect_banner
      exit 0
    elif [[ -n "$st" ]]; then
      echo "Tunnel job is queued ($(find_job | head -1)); waiting for it to start..."
    else
      echo "No tunnel running — submitting the job..."
      ( cd "$DIR" && : > out && sbatch -J "$JOBNAME" vscode.job ) \
        || { echo "sbatch failed."; exit 1; }
    fi

    # Wait for the allocation to start (~6 min cap).
    echo -n "waiting for allocation"
    for _ in $(seq 1 120); do
      [[ "$(job_state)" == "R" ]] && { echo " ... running."; break; }
      echo -n "."; sleep 3
    done
    if [[ "$(job_state)" != "R" ]]; then
      echo; echo "still not running after ~6 min. Check:  vscode status   /   vscode log"
      exit 1
    fi

    # Follow startup: surface the device code (if login is needed), then the URL.
    echo "watching tunnel startup (Ctrl-C is safe — the job keeps running):"
    last_code=""
    for _ in $(seq 1 200); do          # ~10 min
      if grep -q "vscode.dev/tunnel" "$OUT" 2>/dev/null; then
        echo; connect_banner; exit 0
      fi
      code="$(grep -oE 'use code [A-Z0-9-]+' "$OUT" 2>/dev/null | tail -1 | awk '{print $3}')"
      if [[ -n "$code" && "$code" != "$last_code" ]]; then
        last_code="$code"
        echo
        echo "----------------------------------------------------------------------"
        echo " ONE-TIME GITHUB LOGIN NEEDED"
        echo "   1. open   https://github.com/login/device"
        echo "   2. code:  $code"
        echo "   3. authorize with the SAME GitHub account VS Code uses"
        echo "   (rotates every few min; this line updates if it lapses)"
        echo "----------------------------------------------------------------------"
      fi
      sleep 3
    done
    echo "timed out waiting for the tunnel to register. Check:  vscode log"
    exit 1
    ;;

  *) echo "usage: vscode [up|status|down|log]"; exit 1 ;;
esac
