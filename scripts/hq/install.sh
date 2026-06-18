#!/usr/bin/env bash
# Install the HyperQueue standing-fleet on a PBS/ALCF cluster (Polaris, Aurora,
# ...). Symlinks the orchestrator scripts onto PATH, builds the login-node
# get_nprocs shim, and renders the PBS allocation scripts into ~/.hq/ from the
# per-cluster knobs below. Idempotent; never overwrites an existing ~/.hq/*.pbs
# or fleet.env unless you pass --force. Does NOT start anything — see the
# printed next steps and docs/hyperqueue-fleet.md.
#
# Per-cluster knobs (env overrides; defaults = Polaris):
#   HQ_ACCOUNT, HQ_SYSTEM, HQ_NODES, HQ_FILESYSTEMS,
#   HQ_CAP_QUEUE, HQ_CAP_WALL, HQ_BRIDGE_QUEUE, HQ_BRIDGE_WALL,
#   HQ_DEBUG_QUEUE (autoalloc safety-net queue, for the printed commands)
#
# Example (Aurora-ish): HQ_SYSTEM=aurora HQ_FILESYSTEMS=home:flare \
#                       HQ_CAP_QUEUE=... ./install.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
HQDIR="$HOME/.hq"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

HQ_ACCOUNT="${HQ_ACCOUNT:-HetRxnEnergy}"
HQ_SYSTEM="${HQ_SYSTEM:-polaris}"
HQ_NODES="${HQ_NODES:-2}"
HQ_FILESYSTEMS="${HQ_FILESYSTEMS:-home:eagle}"
HQ_CAP_QUEUE="${HQ_CAP_QUEUE:-capacity}"
HQ_CAP_WALL="${HQ_CAP_WALL:-168:00:00}"
HQ_BRIDGE_QUEUE="${HQ_BRIDGE_QUEUE:-preemptable}"
HQ_BRIDGE_WALL="${HQ_BRIDGE_WALL:-72:00:00}"
HQ_DEBUG_QUEUE="${HQ_DEBUG_QUEUE:-debug}"

echo "=== HyperQueue fleet install (account=$HQ_ACCOUNT system=$HQ_SYSTEM nodes=$HQ_NODES) ==="
mkdir -p "$LOCAL_BIN" "$HQDIR/shim"

# 1. Orchestrator scripts onto PATH
for s in hq-server-up hq-fleet; do
    chmod +x "$DIR/$s"
    t="$LOCAL_BIN/$s"
    if [[ -e "$t" || -L "$t" ]]; then
        if [[ "$(readlink -f "$t" 2>/dev/null)" == "$DIR/$s" ]]; then
            echo "✓ $s already linked"
        else
            echo "⚠ $t exists and points elsewhere — leaving it (use the repo copy manually if intended)"
        fi
    else
        ln -s "$DIR/$s" "$t"; echo "✓ linked $s"
    fi
done

# 2. Build the login-node get_nprocs shim
cp -f "$DIR/shim/nproc8.c" "$HQDIR/shim/nproc8.c"
if command -v gcc >/dev/null 2>&1; then
    gcc -shared -fPIC -o "$HQDIR/shim/nproc8.so" "$HQDIR/shim/nproc8.c" \
        && echo "✓ built $HQDIR/shim/nproc8.so"
else
    echo "⚠ gcc not found — build the shim later: gcc -shared -fPIC -o $HQDIR/shim/nproc8.so $HQDIR/shim/nproc8.c"
fi

# 3. Render the PBS allocation scripts
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

# 4. fleet.env (secrets, notifications) — never overwrite
if [[ -e "$HQDIR/fleet.env" ]]; then
    echo "✓ fleet.env exists — kept"
else
    cp "$DIR/fleet.env.example" "$HQDIR/fleet.env"
    echo "✓ seeded $HQDIR/fleet.env from example (edit it; it is NOT tracked)"
fi

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
