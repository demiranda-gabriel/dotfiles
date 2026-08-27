# hq-log-route.sh — shared HQ task-log routing, sourced by BOTH clients.
#
# HyperQueue's default --stdout/--stderr is
# %{SUBMIT_DIR}/job-%{JOB_ID}/%{TASK_ID}.{stdout,stderr}, which litters the cwd
# with job-*/ dirs. Workflow convention is logs next to the run, so every
# `submit` gets an explicit --stdout/--stderr under <git-root>/runs/_hq_logs/.
#
# WHY THIS IS A SEPARATE, SOURCEABLE FILE (2026-08-27): the routing used to live
# inline in the `hq()` shell function in shell/41-polaris.sh. That covered the
# name `hq` in interactive shells only, and missed two paths entirely:
#   1. `hqb` — the private bravo client — is a real script that `exec`s the hq
#      BINARY, so a shell function can never intercept it. Result: 29 job-*/
#      dirs in the multifidelity root between 2026-08-20 and 08-25, once the
#      bravo lane became the default (in-tree routing silently stopped at
#      job-563 on 08-10, the last alpha submit).
#   2. Non-interactive shells (`bash script.sh` that never sources ~/.bashrc)
#      have no function at all.
# Both clients now source this file, so the routing holds wherever it runs.
#
# hq_log_route_argv <lane> "$@"  ->  sets HQ_ARGV to the argv to actually run.
# Passes argv through untouched unless it is a `submit` with no explicit
# --stdout/--stderr/--stream. <lane> is an optional subdir keeping the two
# servers' independent job-ID counters from colliding ("" for alpha).
hq_log_route_argv() {
    local lane="$1"; shift
    HQ_ARGV=("$@")

    local a
    # Respect an explicit redirection. Stop at `--`: past it the tokens belong
    # to the payload command, not to hq.
    for a in "$@"; do
        case "$a" in
            --) break ;;
            --stdout|--stdout=*|--stderr|--stderr=*|--stream|--stream=*) return 0 ;;
        esac
    done

    # Locate the `submit` subcommand rather than assuming it is $1 — global
    # flags may precede it (`hq --server-dir DIR submit ...`), which the old
    # `[[ "$1" == submit ]]` test silently let through unrouted.
    local i n=$# idx=-1
    for (( i = 0; i < n; i++ )); do
        a="${@:i+1:1}"
        [[ "$a" == "--" ]] && break
        if [[ "$a" == "submit" ]]; then idx=$i; break; fi
    done
    (( idx >= 0 )) || return 0

    local d="$HQ_LOG_DIR"
    if [[ -z "$d" ]]; then
        local root; root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$root" && -d "$root/runs" ]]; then d="$root/runs/_hq_logs"
        else d="$HOME/.hq/logs"; fi
        # Only the default path is lane-qualified; an explicit HQ_LOG_DIR is
        # honoured verbatim (documented as HQ_LOG_DIR=runs/<N>-<exp>/logs).
        [[ -n "$lane" ]] && d="$d/$lane"
    fi

    # --stdout/--stderr are submit's own flags: they must land after `submit`
    # and before the `--` payload separator.
    HQ_ARGV=(
        "${@:1:idx+1}"
        --stdout "$d/job-%{JOB_ID}/%{TASK_ID}.stdout"
        --stderr "$d/job-%{JOB_ID}/%{TASK_ID}.stderr"
        "${@:idx+2}"
    )
}
