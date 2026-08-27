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
  #
  # The logic lives in scripts/hq/hq-log-route.sh so the `hqb` client (a real
  # script, which execs the binary and so can never inherit this function) gets
  # the same treatment — see that file's header for the job-*/ leak it fixes.
  _hq_route="${BASH_SOURCE[0]%/shell/*}/scripts/hq/hq-log-route.sh"
  if [[ -r "$_hq_route" ]]; then
    . "$_hq_route"
    hq() {
      hq_log_route_argv "" "$@"
      command hq "${HQ_ARGV[@]}"
    }
  fi
  unset _hq_route

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
    # No core dumps on login nodes. When the pid cap is hit, a failed
    # fork()/pthread_create() makes the native Claude binary (and Node tools)
    # abort with SIGABRT — and Polaris's default `ulimit -c unlimited` +
    # core_pattern=core then writes a multi-GB core into the cwd (a 6.5 GB
    # core.<pid> was found in $HOME). That fills the disk and page cache,
    # deepening the very memory pressure that triggered the abort. The cores
    # are worthless here (no debugging of stripped release binaries), so
    # suppress them; compute nodes are unaffected by this login-node gate.
    ulimit -c 0

    export OMP_NUM_THREADS="${OMP_NUM_THREADS:-8}"
    export MKL_NUM_THREADS="${MKL_NUM_THREADS:-8}"
    export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-8}"
    export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-8}"
    export VECLIB_MAXIMUM_THREADS="${VECLIB_MAXIMUM_THREADS:-8}"
    # Go's runtime ignores all of the above: it sizes GOMAXPROCS (and its OS-thread
    # pool) from the raw CPU-affinity mask — 256 cores here — so an uncapped Go tool
    # (fzf, lazygit, gh) spawns ~256 threads and trips the 256-pid cgroup. Cap it to
    # match the 8-core allotment. (The M-j chooser also self-caps in tmux-window-fzf,
    # since a display-popup child doesn't source this rc.)
    export GOMAXPROCS="${GOMAXPROCS:-8}"

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
