# VS Code remote tunnel on ALCF login nodes (Polaris / Aurora)

How to get the exact VS Code experience we run on Polaris onto **Aurora** (or
any other ALCF login node), driven entirely from these dotfiles: clone the
repo, run `bootstrap.sh`, start one tmux session, connect from your laptop.

> **Scope.** This is *Option A — light editing on the login node*: browsing
> the tree, editing source, running git, launching short shell commands and
> `hq`/`qsub` submissions. It is **not** for running GPU or heavy compute in
> the VS Code terminal — login nodes are capped at 8 cores / 8 GB / 256 pids
> (see [The login-node cgroup](#the-login-node-cgroup-read-this)). For
> interactive compute, submit a job and attach to the compute node instead.

---

## TL;DR (Aurora, from a clean home)

```bash
# 0. From Polaris (or your laptop): get onto Aurora
ssh aurora                         # MobilePASS+ OTP; the ~/.ssh/config alias is set up

# 1. GitHub auth on Aurora (separate home from Polaris — see below), then:
git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh --viewers  # installs lf/tmux/... AND the `code` CLI
source ~/.bashrc

# 2. Start the tunnel in a persistent tmux session
vscode-tunnel                      # then: vscode-tunnel attach  (to do the login)
#   -> first run prints a github.com/login/device URL + code; enter it on your laptop
#   -> machine registers as e.g. "aurora-0009"; Ctrl-b d to detach, leave it running

# 3. On your laptop's VS Code: Remote Explorer -> Tunnels -> aurora-0009 -> Connect
#    (sign in to the SAME GitHub account). Open /eagle/projects/HetRxnEnergy/demiranda
```

That's the whole loop. Everything below is the *why* and the failure modes.

---

## Mental model

`code tunnel` runs a small Node service on the login node. Because ALCF login
nodes have **direct outbound internet**, that service registers itself with
Microsoft's tunnel relay over an outbound HTTPS connection — no inbound ports,
no SSH `ProxyCommand`, no `salloc`. Your local VS Code (or `vscode.dev` in a
browser) signs in to the **same GitHub account**, sees the machine in its
tunnel list, and connects through the relay. The VS Code *server* then runs on
the login node, so the integrated terminal, file tree, extensions, and language
servers all execute there — exactly like our Polaris setup.

```
  your laptop VS Code  ──HTTPS──>  MS tunnel relay  <──HTTPS──  code tunnel
  (Remote-Tunnels,                                              on aurora-uan-NNNN
   signed into GitHub)                                          (this repo's
                                                                 vscode-login-tunnel.sh)
```

Why a tunnel instead of Remote-SSH? Remote-SSH would re-run the MobilePASS+ OTP
on every reconnect and trips VS Code's 15 s connect timeout against the OTP
prompt. The tunnel authenticates **once** (device-code, cached in `~/.vscode-cli`)
and reconnects silently. (The `scripts/vscode/` toolkit in this repo is the
*other* pattern — Remote-SSH onto a FASRC SLURM compute node — and does not
apply here.)

---

## One-time setup on Aurora

### 0. SSH to Aurora

Already wired in `~/.ssh/config` (entry added 2026-06-18):

```
Host aurora
    HostName aurora.alcf.anl.gov
    User demiranda
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h
    ControlPersist 12h
```

`ssh aurora`, enter the MobilePASS+ OTP once, and the master persists 12 h.
Aurora only offers `keyboard-interactive` (the OTP) — no pubkey/hostbased — so
the first connection always needs the token. **The ControlMaster socket is
local to whichever login node you ran `ssh` from**; if you bounce between
Polaris login nodes the socket won't follow you.

### 1. Authenticate to GitHub from Aurora

**Aurora's `$HOME` is a separate filesystem from Polaris's** — none of your
Polaris SSH keys or dotfiles are there. You need GitHub auth on Aurora once.
Pick one:

- **New SSH key (recommended — survives, enables push):**
  ```bash
  ssh-keygen -t ed25519 -C "aurora-$(whoami)" -f ~/.ssh/id_ed25519 -N ""
  cat ~/.ssh/id_ed25519.pub        # add this at https://github.com/settings/keys
  ssh -T git@github.com            # expect "Hi demiranda-gabriel! ..."
  git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
  ```
- **Agent forwarding (no new key, but only while the laptop session is up):**
  `ssh -A aurora` *with your key loaded in the laptop's agent*, then clone via
  SSH as above. (Add `ForwardAgent yes` under `Host aurora` if you want it by
  default.)
- **HTTPS (read-only is enough for bootstrap if the repo is public):**
  `git clone https://github.com/demiranda-gabriel/dotfiles.git ~/dotfiles`

### 2. Bootstrap the dotfiles

```bash
~/dotfiles/bootstrap.sh --viewers
source ~/.bashrc
```

`--viewers` runs every `install/install-*.sh`, which now includes
**`install-vscode-cli.sh`** — it fetches the alpine-static VS Code CLI to
`~/software/vscode-cli/code` and symlinks `~/.local/bin/code`. The alpine
static build has no glibc coupling, so the same binary works on Polaris
(Rocky 8) and Aurora (SLES). `bootstrap.sh` also symlinks
`vscode-login-tunnel.sh` and `vscode-tunnel` from `bin/` into `~/.local/bin`.

Verify:

```bash
code --version          # e.g. 1.124.x
command -v vscode-tunnel vscode-login-tunnel.sh
```

---

## Start the tunnel

```bash
vscode-tunnel            # starts a detached tmux session named 'vscode'
vscode-tunnel attach     # attach to complete the device-code login
```

On first run you'll see:

```
To grant access to the server, please log into https://github.com/login/device
and use code XXXX-XXXX
```

Open that URL on your laptop, enter the code, authorize. The credential caches
under `~/.vscode-cli`, so subsequent restarts skip the login. The tunnel then
registers and prints its name — by default `<cluster>-<node-number>`, e.g.
**`aurora-0009`** on `aurora-uan-0009` (override with `vscode-tunnel up myname`).

`Ctrl-b d` to detach. The tunnel keeps running in the tmux session across SSH
disconnects.

Management:

```bash
vscode-tunnel status     # tmux session + registered tunnel name + login pid count
vscode-tunnel attach     # re-attach to watch its output
vscode-tunnel down       # stop the tunnel + kill the tmux session
```

---

## Connect from your laptop

**Desktop VS Code:**
1. Install the **Remote - Tunnels** extension (bundled in the Remote Development
   pack) if you don't have it.
2. Open the **Remote Explorer** view → **Tunnels**, sign in to the **same
   GitHub account** you used in the device-code step.
3. The machine (`aurora-0009`) appears → **Connect in Current Window** /
   **New Window**. Or Command Palette → *Remote-Tunnels: Connect to Tunnel*.
4. **File → Open Folder** → `/eagle/projects/HetRxnEnergy/demiranda` (cross-
   mounted, same path as Polaris) or `~`.

**Browser (no local install):** go to <https://vscode.dev>, Command Palette →
*Remote-Tunnels: Connect to Tunnel*, pick the machine.

---

## The login-node cgroup (read this)

Every ALCF login node confines each user to a cgroup: **8 cores, 8 GB RAM, and
`pids.max = 256` — and pids count *threads*, not just processes.** At the cap,
every new `fork()`/`pthread_create()` in *any* of your processes fails, which
crashes Claude/Node sessions and the VS Code server alike.

`vscode-login-tunnel.sh` runs `code` under **`taskset -c 0-7`** for this reason.
Pinning to 8 CPUs is free (the cgroup throttles you to 8 cores regardless) but
stops Node/tokio from sizing thread pools to the *hundreds* of hardware cores
the node reports — the thing that otherwise blows the 256-pid cap.

If you still hit `fork: retry: Resource temporarily unavailable` or the VS Code
server dies on connect:

- Check usage: `cat /sys/fs/cgroup/users/$USER/pids.current` (and `pids.events`
  — a rising `max` count means you're hitting the cap).
- **Keep extensions minimal** on the remote. Heavy language servers (Pylance,
  rust-analyzer, Jupyter) each spawn thread pools. Disable what you don't need
  *on the remote* (extensions have a "Disable (Remote)" option).
- `taskset` pins *scheduling* but does **not** lower the core count libraries
  read via `get_nprocs()`. On Polaris the HyperQueue fleet works around this
  with an `LD_PRELOAD` shim (`~/.hq/shim/nproc8.so`) that fakes 8 CPUs. If a
  specific extension is the culprit, the same shim can be prepended to the
  tunnel (export `LD_PRELOAD` before `vscode-tunnel`) — that shim is per-host
  and not in this repo.
- As a last resort for heavy work, don't fight the login node: get an
  interactive compute node and point VS Code there instead.

---

## Persistence, reconnection, and which node

- **Survives disconnects:** the tunnel lives in the `vscode` tmux session, not
  your SSH session. Close your laptop, reconnect later, VS Code re-attaches
  silently (no new OTP, no new device-code).
- **The tunnel is pinned to one login node.** The machine name encodes it
  (`aurora-0009`). If that login node reboots, the tmux session dies — SSH back
  in (you may land on a *different* UAN), run `vscode-tunnel` again, and a
  machine with the new node's name appears. Old stale entries can be removed
  with `code tunnel unregister` or from the VS Code Tunnels list.
- **Credential cache** (`~/.vscode-cli`) and the registered tunnel id
  (`~/.vscode/cli/code_tunnel.json`) live in home, so they persist across
  reboots and restarts. You only redo the device-code login if that cache is
  cleared.

---

## Aurora-specific notes

- **Home is not shared with Polaris.** Bootstrap from scratch (keys, dotfiles,
  CLI) the first time. The dotfiles make this one `bootstrap.sh --viewers`.
- **`/eagle` is cross-mounted**, so `cds` →
  `/lus/eagle/projects/HetRxnEnergy/demiranda` resolves to the *same* data on
  both systems — no copying needed to move a project between Polaris and Aurora.
- **`/lus/flare`** is Aurora's primary Lustre/DAOS scratch and is **not** on
  Polaris; conversely Aurora may not mount Polaris's `/grand`.
- **Login nodes have direct internet** (the device-code login and tunnel relay
  work as-is). Aurora *compute* nodes route through a proxy — irrelevant here
  since the tunnel only ever runs on the login node.
- The tunnel name auto-derives as `aurora-<NNNN>` from `aurora-uan-NNNN`; pass
  an explicit name to `vscode-tunnel up <name>` if you prefer something stable.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ssh aurora` keeps asking for the OTP | Aurora has no pubkey auth — OTP is required for the *first* connection per login node; the ControlMaster then persists 12 h. Check liveness: `ssh -O check aurora`. |
| Device-code URL never appears | You're past the cached-login branch — `code tunnel user show` already has a credential. That's fine; the tunnel registers directly. To force a re-login: `code tunnel user logout`. |
| Machine missing from VS Code Tunnels list | Laptop VS Code is signed into a *different* account than the device-code step. Sign into the same GitHub account. |
| `fork: Resource temporarily unavailable`, server dies on connect | 256-pid cgroup cap — see [the cgroup section](#the-login-node-cgroup-read-this). Trim remote extensions; check `pids.current`. |
| `'code' not found` from `vscode-login-tunnel.sh` | CLI not installed — run `~/dotfiles/install/install-vscode-cli.sh` (or re-run `bootstrap.sh --viewers`). |
| Tunnel gone after a few days | Login node rebooted and killed the tmux session. `vscode-tunnel` again; remove the stale machine entry if the node number changed. |
| `git clone` fails on Aurora | No GitHub auth in Aurora's (separate) home — see [GitHub auth](#1-authenticate-to-github-from-aurora). |

---

## What lives where

| Piece | Path | Role |
|---|---|---|
| `vscode-login-tunnel.sh` | `bin/` → `~/.local/bin/` | runs `code tunnel` cgroup-pinned; derives the machine name |
| `vscode-tunnel` | `bin/` → `~/.local/bin/` | tmux up/attach/status/down wrapper |
| `install-vscode-cli.sh` | `install/` | fetches the alpine-static `code` CLI (run by `--viewers`) |
| `code` CLI | `~/software/vscode-cli/code` → `~/.local/bin/code` | the standalone tunnel client |
| credential cache | `~/.vscode-cli/` | device-code login token (persists) |
| tunnel identity | `~/.vscode/cli/code_tunnel.json` | registered machine name/id |
