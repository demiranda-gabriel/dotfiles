# lj — "list jobs": your active jobs on the batch scheduler and their status.
# Portable across the clusters in these dotfiles: PBS (Aurora/Polaris) via
# qstat, SLURM (FASRC) via squeue. Any extra args are passed straight through
# (e.g. `lj -x` on PBS to include finished jobs).
lj() {
    if command -v qstat >/dev/null 2>&1; then
        # -w: wide output so job IDs / names aren't truncated.
        qstat -wu "$USER" "$@"
    elif command -v squeue >/dev/null 2>&1; then
        squeue -u "$USER" "$@"
    else
        echo "lj: no batch scheduler found (qstat/squeue not on PATH)" >&2
        return 1
    fi
}
