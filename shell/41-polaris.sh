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

fi
