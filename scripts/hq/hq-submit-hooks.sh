# hq-submit-hooks.sh — shared `hq submit` argv rewrites, sourced by BOTH clients.
#
# Two hooks, applied together by hq_submit_hooks_argv:
#   1. log routing  — task logs in-tree instead of job-*/ dirs in the cwd
#   2. owner prefix — job names carry "<user>:" so the fleet views can attribute
#                     them (see hq-shared/bin/hq-gpus)
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
# Both clients now source this file, so the hooks hold wherever they run.
#
# hq_submit_hooks_argv <lane> "$@"  ->  sets HQ_ARGV to the argv to actually run.
# <lane> is an optional subdir keeping the two servers' independent job-ID
# counters from colliding in the log tree ("" for alpha).

# Index of the `submit` subcommand in argv (0-based), or -1 when this argv is
# not a submit. Located rather than assumed to be $1 — global flags may precede
# it (`hq --server-dir DIR submit ...`), which the old `[[ "$1" == submit ]]`
# test silently let through unhooked. Stops at `--`: past it the tokens belong
# to the payload command, not to hq.
_hq_submit_idx() {
    local i n=$# a
    for (( i = 0; i < n; i++ )); do
        a="${@:i+1:1}"
        [[ "$a" == "--" ]] && break
        if [[ "$a" == "submit" ]]; then printf '%s' "$i"; return 0; fi
    done
    printf '%s' -1
}

# --- hook 1: task-log routing ------------------------------------------------
# HyperQueue's default --stdout/--stderr is
# %{SUBMIT_DIR}/job-%{JOB_ID}/%{TASK_ID}.{stdout,stderr}, which litters the cwd
# with job-*/ dirs. Workflow convention is logs next to the run, so every
# `submit` gets an explicit --stdout/--stderr under <git-root>/runs/_hq_logs/.
# Passes argv through untouched unless it is a `submit` with no explicit
# --stdout/--stderr/--stream.
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

    local idx; idx=$(_hq_submit_idx "$@")
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

# --- hook 2: owner-prefixed job names ----------------------------------------
# The HQ server runs every task as the fleet operator and records nothing about
# who submitted it, so the fleet convention is that a job name starts with
# "<user>:" — that prefix is the primary thing `hq-gpus` attributes a job by.
# hq-shared/bin/hq-submit applies it for teammates, but it deliberately leaves
# an explicit --name alone, and these clients never applied it at all: every
# job submitted with `--name <something>` therefore showed up unowned
# (rendered "?" in the User column) until hq-gpus learned to fall back to the
# submit directory. Prefix it at the source instead.
#
#   --name foo / --name=foo   ->  --name <user>:foo
#   (no --name)               ->  --name <user>:<basename of the payload>
#   a name that already has a "<something>:" prefix is left untouched.
hq_name_prefix_argv() {
    HQ_ARGV=("$@")
    local idx; idx=$(_hq_submit_idx "$@")
    (( idx >= 0 )) || return 0

    local i n=$# a v
    for (( i = idx + 1; i < n; i++ )); do
        a="${@:i+1:1}"
        [[ "$a" == "--" ]] && break
        case "$a" in
            --name=*)
                v="${a#--name=}"
                [[ "$v" =~ ^[A-Za-z0-9_.-]+: ]] && return 0
                HQ_ARGV[i]="--name=$USER:$v"
                return 0 ;;
            --name)
                (( i + 1 < n )) || return 0          # malformed; let hq complain
                v="${@:i+2:1}"
                [[ "$v" =~ ^[A-Za-z0-9_.-]+: ]] && return 0
                HQ_ARGV[i+1]="$USER:$v"
                return 0 ;;
        esac
    done

    # No --name at all: derive one from the payload, matching hq-submit.
    local name=job seen_dd=0
    for (( i = idx + 1; i < n; i++ )); do
        a="${@:i+1:1}"
        if (( seen_dd )); then name=$(basename -- "$a"); break; fi
        [[ "$a" == "--" ]] && seen_dd=1
    done
    HQ_ARGV=("${@:1:idx+1}" --name "$USER:$name" "${@:idx+2}")
}

# Both hooks, in order. This is what the clients call.
hq_submit_hooks_argv() {
    local lane="$1"; shift
    hq_log_route_argv "$lane" "$@"
    (( ${#HQ_ARGV[@]} )) && hq_name_prefix_argv "${HQ_ARGV[@]}"
    return 0
}
