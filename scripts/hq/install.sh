#!/usr/bin/env bash
# Install the HyperQueue fleet scripts. Scheduler-aware:
#   * PBS/ALCF (Polaris, Aurora, ...): the 24/7 standing-fleet orchestrator
#     (login-node server + capacity/bridge allocations + get_nprocs shim).
#   * SLURM/FASRC: an ON-DEMAND allocator (compute-node server + ssh-bridged
#     client + worker allocations sized on request). No standing fleet.
#
# Symlinks the right orchestrator scripts onto PATH and renders the allocation
# scripts into ~/.hq/ from the per-cluster knobs below. Idempotent; never
# overwrites an existing ~/.hq/*.{pbs,sbatch} or fleet.env unless you pass
# --force. Does NOT start anything — see the printed next steps and
# docs/hyperqueue-fleet.md.
#
# Scheduler is auto-detected (sbatch -> slurm, qsub -> pbs); override HQ_SCHED.
#
# PBS knobs (env; defaults = Polaris):
#   HQ_ACCOUNT, HQ_SYSTEM, HQ_NODES, HQ_FILESYSTEMS,
#   HQ_CAP_QUEUE, HQ_CAP_WALL, HQ_BRIDGE_QUEUE, HQ_BRIDGE_WALL, HQ_DEBUG_QUEUE
# SLURM knobs (env; defaults = FASRC server lane):
#   HQ_SRV_PART, HQ_SRV_CPUS, HQ_SRV_MEM, HQ_SRV_WALL
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
HQDIR="$HOME/.hq"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# --- scheduler detection -----------------------------------------------------
HQ_SCHED="${HQ_SCHED:-auto}"
if [[ "$HQ_SCHED" == auto ]]; then
    if   command -v sbatch >/dev/null 2>&1; then HQ_SCHED=slurm
    elif command -v qsub   >/dev/null 2>&1; then HQ_SCHED=pbs
    else echo "ERROR: neither sbatch nor qsub on PATH; set HQ_SCHED=slurm|pbs" >&2; exit 1; fi
fi

mkdir -p "$LOCAL_BIN" "$HQDIR"

link_script() {  # link_script <src-abspath> <name>
    local src=$1 name=$2 t="$LOCAL_BIN/$2"
    chmod +x "$src"
    if [[ -e "$t" || -L "$t" ]]; then
        if [[ "$(readlink -f "$t" 2>/dev/null)" == "$src" ]]; then
            echo "✓ $name already linked"
        else
            echo "⚠ $t exists and points elsewhere — leaving it (relink manually if intended)"
        fi
    else
        ln -s "$src" "$t"; echo "✓ linked $name"
    fi
}

seed_fleet_env() {
    if [[ -e "$HQDIR/fleet.env" ]]; then echo "✓ fleet.env exists — kept"
    else cp "$DIR/fleet.env.example" "$HQDIR/fleet.env"; echo "✓ seeded $HQDIR/fleet.env (edit it; NOT tracked)"; fi
}

# =============================================================================
# SLURM / FASRC — on-demand allocator
# =============================================================================
if [[ "$HQ_SCHED" == slurm ]]; then
    HQ_SRV_PART="${HQ_SRV_PART:-sapphire}"
    HQ_SRV_CPUS="${HQ_SRV_CPUS:-2}"
    HQ_SRV_MEM="${HQ_SRV_MEM:-4G}"
    HQ_SRV_WALL="${HQ_SRV_WALL:-3-00:00:00}"

    echo "=== HyperQueue install (SLURM / on-demand; server lane: $HQ_SRV_PART $HQ_SRV_WALL) ==="

    link_script "$DIR/slurm/hq-server-up" hq-server-up
    link_script "$DIR/slurm/hq-fleet"     hq-fleet

    render_slurm() {  # render_slurm <template> <dest>
        sed -e "s|__SRV_PART__|$HQ_SRV_PART|g" \
            -e "s|__SRV_CPUS__|$HQ_SRV_CPUS|g" \
            -e "s|__SRV_MEM__|$HQ_SRV_MEM|g" \
            -e "s|__SRV_WALL__|$HQ_SRV_WALL|g" \
            -e "s|__HQDIR__|$HQDIR|g" \
            "$1" > "$2"
    }
    for pair in "slurm/server.sbatch.tmpl:server.sbatch" "slurm/worker.sbatch.tmpl:worker.sbatch"; do
        src="${pair%%:*}"; dst="$HQDIR/${pair##*:}"
        if [[ -e "$dst" && $FORCE -ne 1 ]]; then echo "✓ ${pair##*:} exists — kept (--force to regen)"
        else render_slurm "$DIR/$src" "$dst"; echo "✓ wrote $dst"; fi
    done

    seed_fleet_env

    cat <<EOF

=== Next steps (SLURM / on-demand) ===
  1. Ensure 'hq' is on PATH (see docs/hyperqueue-fleet.md to install the binary).
  2. Make sure shell/42-fasrc-hq.sh is sourced (the \`hq\` ssh-bridge wrapper).
  3. Review ~/.hq/server.sbatch (server lane) and ~/.hq/worker.sbatch (defaults).
  4. Bring up a fleet sized to your needs (starts the server automatically):
       hq-fleet up                                        # 1 GPU on gpu_requeue
       hq-fleet up -p kozinsky_gpu -g 4 -t 1-00:00:00     # a whole lab A100 node
       hq-fleet up -p gpu_requeue  -N 2 -g 4              # +2 preemptable nodes
  5. Submit work (ssh-bridged to the server node automatically):
       hq submit --resource gpus/nvidia=1 -- python train.py
       hq job list ; hq-fleet status
  6. Tear down when done:
       hq-fleet down            # stop workers
       hq-fleet down --all      # stop workers + server
EOF
    exit 0
fi

# =============================================================================
# PBS / ALCF — 24/7 standing fleet
# =============================================================================
HQ_ACCOUNT="${HQ_ACCOUNT:-HetRxnEnergy}"
HQ_SYSTEM="${HQ_SYSTEM:-polaris}"
HQ_NODES="${HQ_NODES:-2}"
HQ_FILESYSTEMS="${HQ_FILESYSTEMS:-home:eagle}"
HQ_CAP_QUEUE="${HQ_CAP_QUEUE:-capacity}"
HQ_CAP_WALL="${HQ_CAP_WALL:-168:00:00}"
HQ_BRIDGE_QUEUE="${HQ_BRIDGE_QUEUE:-preemptable}"
HQ_BRIDGE_WALL="${HQ_BRIDGE_WALL:-72:00:00}"
HQ_DEBUG_QUEUE="${HQ_DEBUG_QUEUE:-debug}"

echo "=== HyperQueue fleet install (PBS; account=$HQ_ACCOUNT system=$HQ_SYSTEM nodes=$HQ_NODES) ==="
mkdir -p "$HQDIR/shim"

link_script "$DIR/hq-server-up" hq-server-up
link_script "$DIR/hq-fleet"     hq-fleet

# Build the login-node get_nprocs shim
cp -f "$DIR/shim/nproc8.c" "$HQDIR/shim/nproc8.c"
if command -v gcc >/dev/null 2>&1; then
    gcc -shared -fPIC -o "$HQDIR/shim/nproc8.so" "$HQDIR/shim/nproc8.c" \
        && echo "✓ built $HQDIR/shim/nproc8.so"
else
    echo "⚠ gcc not found — build the shim later: gcc -shared -fPIC -o $HQDIR/shim/nproc8.so $HQDIR/shim/nproc8.c"
fi

render() {  # render <template> <dest>
    sed -e "s|__ACCOUNT__|$HQ_ACCOUNT|g" \
        -e "s|__SYSTEM__|$HQ_SYSTEM|g" \
        -e "s|__NODES__|$HQ_NODES|g" \
        -e "s|__CAP_QUEUE__|$HQ_CAP_QUEUE|g" \
        -e "s|__CAP_WALL__|$HQ_CAP_WALL|g" \
        -e "s|__BRIDGE_QUEUE__|$HQ_BRIDGE_QUEUE|g" \
        -e "s|__BRIDGE_WALL__|$HQ_BRIDGE_WALL|g" \
        -e "s|__FILESYSTEMS__|$HQ_FILESYSTEMS|g" \
        -e "s|__HQDIR__|$HQDIR|g" \
        "$1" > "$2"
}
for pair in "capacity-workers.pbs.tmpl:capacity-workers.pbs" "preempt-bridge.pbs.tmpl:preempt-bridge.pbs"; do
    src="${pair%%:*}"; dst="$HQDIR/${pair##*:}"
    if [[ -e "$dst" && $FORCE -ne 1 ]]; then
        echo "✓ ${pair##*:} exists — kept (use --force to regenerate)"
    else
        render "$DIR/$src" "$dst"; echo "✓ wrote $dst"
    fi
done

seed_fleet_env

cat <<EOF

=== Next steps ===
  1. Ensure 'hq' is on PATH (install if needed — see docs/hyperqueue-fleet.md).
  2. Review ~/.hq/capacity-workers.pbs and ~/.hq/preempt-bridge.pbs.
  3. Edit ~/.hq/fleet.env (Slack/ntfy optional; HQ_FLEET_LABEL=$HQ_SYSTEM).
  4. Pick a stable login node and start the server there:
       HQ_SERVER_HOST=\$(hostname -s) hq-server-up
  5. (Optional) autoalloc safety-net queues, after the server is up:
       hq alloc add pbs --name debug   --time-limit 1h    -- \\
         -A $HQ_ACCOUNT -q $HQ_DEBUG_QUEUE -l filesystems=$HQ_FILESYSTEMS -l place=scatter
       hq alloc add pbs --name preempt --time-limit 3days -- \\
         -A $HQ_ACCOUNT -q $HQ_BRIDGE_QUEUE -l filesystems=$HQ_FILESYSTEMS -l place=scatter
  6. Start the standing fleet:
       HQ_SERVER_HOST=\$(hostname -s) HQ_FLEET_LABEL=$HQ_SYSTEM hq-fleet up
       hq-fleet status
EOF
