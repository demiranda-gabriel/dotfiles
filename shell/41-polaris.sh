# Polaris (ALCF) — login-node helpers. Sourced everywhere but no-ops unless
# the eagle filesystem exists, mirroring the 40-fasrc.sh guard pattern.
if [[ -d /lus/eagle ]]; then

  # tl = hop to login-01 (where the main tmux with Claude agents lives).
  # ~/.ssh/config multiplexes polaris-login-* (ControlPersist 12h), so only
  # the first hop after a master expires asks for a MobilePASS+ OTP.
  alias tl='ssh polaris-login-01'

  # Self-heal the HQ fleet orchestrator after login-node reboots: any shell
  # on login-01 re-ups the tmux session (idempotent, instant when already
  # running). The fleet in turn re-ups the HQ server each tick.
  if [[ "$(hostname -s)" == polaris-login-01 ]] \
      && command -v hq-fleet >/dev/null 2>&1; then
    hq-fleet up >/dev/null 2>&1
  fi

  # Keep HQ task logs in-tree under runs/ (workflow convention: logs next to
  # the run) instead of dropping job-*/ dirs into the cwd. By default they land
  # in <git-root>/runs/_hq_logs/job-<id>/; set HQ_LOG_DIR=runs/<N>-<exp>/logs to
  # route a given experiment's logs alongside its run. Off-repo falls back to
  # ~/.hq/logs. Only the `submit` subcommand is touched (server/fleet/autoalloc
  # untouched), and any explicit --stdout/--stderr/--stream is respected.
  # `hq job cat <id>` keeps working — HQ records the resolved path in its journal.
  hq() {
    if [[ "$1" == submit ]] \
        && [[ " $* " != *" --stdout "* ]] \
        && [[ " $* " != *" --stderr "* ]] \
        && [[ " $* " != *" --stream "* ]]; then
      shift
      local d="$HQ_LOG_DIR"
      if [[ -z "$d" ]]; then
        local root; root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$root" && -d "$root/runs" ]]; then d="$root/runs/_hq_logs"
        else d="$HOME/.hq/logs"; fi
      fi
      command hq submit \
        --stdout "$d/job-%{JOB_ID}/%{TASK_ID}.stdout" \
        --stderr "$d/job-%{JOB_ID}/%{TASK_ID}.stderr" "$@"
    else
      command hq "$@"
    fi
  }

  # --- Login-node thread-budget guard ----------------------------------------
  # Login nodes expose 256 physical cores but confine each user to a cgroup of
  # 8 cores / 8 GB / 256 pids — and pids count THREADS. A single OpenMP/MKL/BLAS
  # call (numpy, torch) sizes its pool to the raw 256 cores, and a
  # `make -j$(nproc)` forks 256 jobs; either instantly exhausts the 256-pid
  # budget, after which every fork()/clone() in the cgroup fails and *all*
  # processes in it freeze — Claude included. (Claude is now a native binary,
  # ~20 threads, no node/libuv/libstdc++, so UV_THREADPOOL_SIZE and the
  # get_nprocs shim do nothing for it; capping the thread libraries is the fix.)
  # Values match the 8-core allotment, are overridable per-invocation
  # (`OMP_NUM_THREADS=32 cmd`), and are login-node-gated so HQ tasks on compute
  # nodes are unaffected.
  if [[ "$(hostname -s)" == polaris-login-* ]]; then
    export OMP_NUM_THREADS="${OMP_NUM_THREADS:-8}"
    export MKL_NUM_THREADS="${MKL_NUM_THREADS:-8}"
    export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-8}"
    export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-8}"
    export VECLIB_MAXIMUM_THREADS="${VECLIB_MAXIMUM_THREADS:-8}"

    # pidbudget — on-demand view of the cgroup budget + top thread consumers.
    pidbudget() {
      local cg=/sys/fs/cgroup/users/$USER
      printf 'login-node cgroup: pids %s/%s   mem %s MB\n' \
        "$(<"$cg/pids.current")" "$(<"$cg/pids.max")" \
        "$(( $(<"$cg/memory.current") / 1048576 ))"
      echo 'top thread consumers (nlwp pid etimes comm):'
      ps -u "$USER" -o nlwp,pid,etimes,comm --sort=-nlwp --no-headers | head -8
    }

    # Warn at >=80% of the pid budget, before forks start failing. Fork-free
    # ($(<file) uses no subshell), so it stays safe even near the cap, and
    # preserves $? so it can't disturb other PROMPT_COMMAND consumers.
    __pidbudget_warn() {
      local __rc=$? cg=/sys/fs/cgroup/users/$USER cur max
      cur=$(<"$cg/pids.current") || return $__rc
      max=$(<"$cg/pids.max")     || return $__rc
      [[ "$max" == max ]] && return $__rc
      (( cur * 100 / max >= 80 )) && \
        printf '\033[33m⚠ login-node threads %s/%s — near cap; run pidbudget\033[0m\n' "$cur" "$max"
      return $__rc
    }
    case ";${PROMPT_COMMAND};" in
      *";__pidbudget_warn;"*) ;;
      *) PROMPT_COMMAND="__pidbudget_warn${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
  fi

fi
