---
name: agent-session
description: Start a coding-agent session (claude, claude-harvard or codex) in its own tmux window inside one of the user's projects, or clean up tmux windows whose agent has exited (e.g. after the remote session was archived or deleted). Use when the user says "create/open/spawn a new session in <project>", "start a claude/codex/harvard agent in <project>", "new codex session in <project>", "list my agent windows", "clean up stale sessions/windows", "kill dead agent windows", or invokes /agent-session.
---

# agent-session

Wraps `agent-session` (`~/dotfiles/bin/agent-session`, linked into
`~/.local/bin/` by `bootstrap.sh`). Two inputs for a new session: the **agent**
and the **project**.

| Agent            | Command typed into the window                              | Window name        |
|------------------|------------------------------------------------------------|--------------------|
| `claude`         | `claude --rc` (shell alias adds `--dangerously-skip-permissions`) | `<project>`        |
| `claude-harvard` | `claude-harvard --rc`                                      | `h-<project>`      |
| `codex`          | `codex --remote unix:// -C <root>/<project>`               | `codex-<project>`  |

A repeated name gets `-2`, `-3`, … Projects live in
`/lus/eagle/projects/HetRxnEnergy/demiranda/projects/` (override with
`AGENT_PROJECTS_ROOT`).

**Hosts.** Defaults are per site, picked from the hostname.

| Site    | `claude` / `claude-harvard`                 | `codex`               | Projects root |
|---------|---------------------------------------------|-----------------------|---------------|
| Polaris | the current node, current tmux session      | **polaris-login-04**  | `/lus/eagle/projects/HetRxnEnergy/demiranda/projects` |
| Aurora  | **aurora-uan-0011**, tmux session `agents`  | **aurora-uan-0012**   | `/lus/flare/projects/HetRxnEnergy/demiranda/projects` |

On Aurora the Claude host is pinned (`AGENT_CLAUDE_HOST`) because tmux is per
login node and `ssh aurora` lands on a random one. Remote nodes are driven
over ssh, in a tmux session named `agents`. Every command takes
`--host <node>` (`login-04` and `uan-0012` are accepted). `list` and `cleanup`
cover the current node, the Claude host and the codex node. On Aurora
`claude-harvard` is the shell alias from `claude-profile-init harvard`; on
Polaris it is `bin/claude-harvard`. To drive Aurora from Polaris:
`ssh aurora agent-session new claude <project>` (set up 2026-11-16).

## Codex: opening message

A Codex session has no thread until its first message, and the Codex app only
lists threads, so a freshly started session is **invisible in the app**
(verified 2026-11-15). `agent-session new codex …` therefore types a short
opening message ("Session for the <project> project … reply ready") once the
session is ready, and reports `opening message: answered` when Codex replies.
Codex can swallow the first Enter after fast typed input, so the script
re-presses Enter until the input box is empty — do the same when sending text
to a Codex window by hand (`tmux send-keys -l "<text>"`, pause, `Enter`, check).
The opening message is skipped while a trust prompt is pending; after the user
approves trust, send a first message manually so the session appears in the app.

## Codex: one node only

Codex sessions talk to a background daemon (`codex app-server`) through
`~/.codex/app-server-control/app-server-control.sock`, a symlink in the
**shared home** pointing at a node-local socket in `/tmp/codex-daemon-<uid>/`.
A daemon on a second node fights over that path, and when either daemon stops
it deletes the link, orphaning the other one. Symptom: new sessions fail with
`Error: the requested app-server socket is not available`. The script refuses
to start codex anywhere but the codex node.

Repair (verified 2026-11-15), on the codex node:

```bash
pgrep -u $USER -fa 'codex app-server'            # daemon still running?
codex app-server daemon version                  # fails if the link is gone
# relink to the daemon's control socket; the daemon log names it
# ("control socket is already in use at /tmp/codex-daemon-<uid>/<hash>"):
ln -s /tmp/codex-daemon-$(id -u)/<hash> ~/.codex/app-server-control/app-server-control.sock
codex app-server daemon version                  # -> "status":"running"
```

If no daemon is running there, `codex app-server daemon start` instead.
`daemon restart` does NOT fix an orphaned daemon (it cannot reach it to stop it).

**Second source of stray daemons: the Codex desktop app over SSH** (seen
2026-11-19). When the desktop app connects to a remote host by SSH it boots its
own `codex -c features.code_mode_host=true app-server --listen unix://` (parent
pid 1, `CODEX_REMOTE_PAYLOAD` in its environment) on whichever login node the
SSH lands on. If that is not the codex node, kill it, then check the link on
the codex node (`codex app-server daemon version`) and recreate it if needed.
The lasting fix is to point the desktop app's SSH host at the codex node
(polaris-login-04), not at a round-robin alias.

## Usage

```bash
agent-session new <claude|claude-harvard|codex> <project>
agent-session list                 # managed windows + state (alive / exited / dead)
agent-session cleanup              # dry run: which windows would be killed
agent-session cleanup --yes        # kill them
agent-session adopt <window> <agent> <project>   # tag a hand-started window
```

## Creating a session

1. If the agent is not stated, default to `claude`. If the project is
   ambiguous, run `agent-session new` anyway — on a bad name it prints the
   available projects; pick only on an exact or obvious match, otherwise ask.
2. Run `agent-session new <agent> <project>`. It waits up to 20 s and prints
   the window, the command, a `status:` line and (for Claude) the remote URL.
3. Report: window name and number, the remote URL, and the status.
4. **`status: WAITING ON TRUST PROMPT`** — the agent asks whether to trust the
   folder, and the answer is saved. Do not answer it yourself: ask the user, and
   on a yes send `tmux send-keys -t <window_id> Enter` (option 1 is "Trust and
   continue"), then capture the pane to confirm it is ready.
5. Refer to windows by **name**, not number: tmux here has `base-index 1` and
   `renumber-windows on`, so indices shift when windows close.

## Cleanup

`cleanup` considers **only windows tagged by this tool** (`@agent_kind` window
option), so ordinary shells and hand-started agents are never touched — use
`adopt` to bring a hand-started one under management. A window is stale when
its agent process (`claude` / `claude-harvard` / `codex`) is no longer running
under the pane (`exited`: back at the shell prompt) or the pane is `dead`.
Running agents are always kept, even when idle.

Run the dry run first, show the user the list, then `--yes`. The list is
already restricted to agent-less windows, so no per-window confirmation is
needed when the user asked for a cleanup.

**Archived sessions do not exit (verified 2026-11-15).** When a Claude session
is archived or ended from the web/app, the local CLI keeps running and only
prints `Remote Control disconnected — this session was ended or archived from
another device or app (code 4090)`. The script reads the pane history and marks
the window `archived` (stale) when the last remote-control line is that
disconnect. **Codex (verified 2026-11-15):** an archived Codex thread
also leaves its TUI running, with nothing on screen. The only trace is that the
thread's rollout file moves from `~/.codex/sessions/` to
`~/.codex/archived_sessions/`. `new codex` records the thread id on the window
(`@agent_thread`, found via a `ref` nonce in the opening message), and the
window is marked `archived` once a rollout with that id sits in
`archived_sessions/`. A Codex window without `@agent_thread` (trust prompt
pending at launch, or adopted by hand) is only caught if its CLI exits; set the
option by hand (`tmux set-option -w -t <win> @agent_thread <id>`) to cover it.
