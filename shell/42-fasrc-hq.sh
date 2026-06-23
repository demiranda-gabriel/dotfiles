# FASRC HyperQueue client bridge. FASRC firewalls login<->compute on arbitrary
# ports both ways, so the HQ server runs on a compute node (hq-fleet up /
# hq-server-up) and the `hq` CLIENT reaches it by ssh'ing to that node, whose
# name hq-server-up publishes to ~/.hq/server-node. No-ops off FASRC or when hq
# isn't installed. (No 24/7 fleet here — usage is on-demand; cf. 41-polaris.sh.)
if [[ -d /n/netscratch && -x "$HOME/.local/bin/hq" ]]; then

  # hq — transparent ssh bridge to the HyperQueue client on the server node.
  # `hq submit ...`, `hq job list`, `hq worker list`, ... all behave as if local.
  # Each arg is %q-quoted so it survives the remote shell verbatim (spaces,
  # quotes, the `--` separator, and `%{...}` log placeholders included).
  # Plain `hq` with no server recorded prints how to start one.
  hq() {
    local node; node=$(cat "$HOME/.hq/server-node" 2>/dev/null)
    if [[ -z "$node" ]]; then
      echo "hq: no server recorded (~/.hq/server-node is empty)." >&2
      echo "    Start an allocation first:  hq-fleet up        (or: hq-server-up)" >&2
      return 1
    fi
    local q="" a
    for a in "$@"; do q+=" $(printf '%q' "$a")"; done
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        "$node" "PATH=\$HOME/.local/bin:\$PATH exec hq$q"
  }

fi
