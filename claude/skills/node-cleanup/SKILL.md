---
name: node-cleanup
description: One-shot login-node triage — run node-health, reap the confident stale set automatically, hunt for leaks node-health's patterns missed, re-measure, and hand back a decision table for everything that backs a live session. Takes the node name as its argument (default polaris-login-01). Use when the user invokes /node-cleanup, or says "clean up the node", "clean up polaris-login-0N", "free pids on the login node", "do the node cleanup". For a report-only look, use the node-health skill instead.
argument-hint: "[node-name]  (default: polaris-login-01)"
---

# node-cleanup

Automates the full triage loop that the `node-health` skill describes one step
at a time. Read `~/.claude/skills/node-health/SKILL.md` for the background
(threads-count-as-pids cgroup trap, what CONFIDENT/SUSPECT mean, why load
average is a red herring). This skill only adds the procedure.

**Invoking this skill IS the user's consent to reap the CONFIDENT set** (the
`--clean` step). It is NOT consent for anything else: `--aggressive`, live VS
Code windows, Claude sessions, watchers, and fleet daemons always go back to the
user as a decision.

## 0. Resolve the target node

```bash
NODE="${ARGUMENTS:-polaris-login-01}"   # $ARGUMENTS = what the user passed
HERE=$(hostname -s)
```

- `NODE == HERE` → run everything below locally.
- Otherwise try exactly once:
  `ssh -o BatchMode=yes -o ConnectTimeout=10 "$NODE" true`.
  On Polaris this normally FAILS (login↔login ssh needs MFA:
  `Permission denied (keyboard-interactive,hostbased)`). If it fails, **stop**
  and tell the user: this session is on `$HERE`; open a VS Code window or shell
  on `$NODE` and invoke `/node-cleanup` there. Do not retry with other flags.
- If it succeeds, prefix every command below with `ssh "$NODE"` (quote the
  remote command as one string).
- If ssh connects but prints nothing and hangs, the node is wedged (fork
  failing) — follow "When the node is already wedged" in the node-health skill.

## 1. Baseline report

```bash
node-health; echo "exit=$?"
```

Record the `usage N/256`, `cap hit` count, and the STALE / VS CODE sections.

## 2. Reap the confident set (automatic)

If STALE — CONFIDENT is non-empty: `node-health --clean`. Never add
`--aggressive`; list any SUSPECT entries for the user instead.

## 3. Hunt for leaks node-health missed

node-health's rule A only fires when the parent's cmdline matches
`is_vscode_cli` in `~/dotfiles/bin/node-health`. When a new launcher name
appears the leak goes undetected (2026-09-26: tunnel ran as
`~/.local/bin/code-tunnel-cli tunnel`, pattern only knew `"code tunnel"`; 8
leaked shells were invisible). Check directly:

```bash
ps -u $USER -o pid=,ppid=,nlwp=,etimes=,args= |
  awk '$5 ~ /^\/bin\/(ba|da)?sh$/ && NF==5 && $3==1 && $4>=3600'
```

For each hit, confirm `pgrep -P <pid>` is empty and inspect the parent
(`ps -o args= -p <ppid>`). If the parent is unambiguously a VS Code/Cursor
tunnel/CLI supervisor, `kill -TERM` those shells, then add the parent's
distinctive name to `is_vscode_cli` in `~/dotfiles/bin/node-health`
(`bash -n` to check; leave it uncommitted and say so). If the parent is
anything else, report — don't kill.

## 4. Re-measure and find the big holders

```bash
cat /sys/fs/cgroup/users/$USER/pids.current      # right after
sleep 10; node-health --brief                    # settled value
ps -u $USER -o pid,ppid,nlwp,etime,args --sort=-nlwp | cut -c1-180 | head -25
```

A count that rises after cleanup means something is actively spawning threads —
identify it from the ps table (compare against the baseline top consumers)
rather than reaping more small stuff.

## 5. Classify what remains — never kill these yourself

| Class | How to recognise | Action |
|---|---|---|
| Essential fleet | `hq server start`, `hq-fleet run`, `bravo-fleet run`, `claude-tmux-watch`, tmux sessions `hq`/`hq-bravo`/`hq-fleet`/`bravo-fleet`, `code-tunnel-cli tunnel`, `vscode-login-tunnel.sh` | Never touch; say so in one line |
| This session | ancestors of your own shell (the Claude binary that spawned you, its extension host) | Never touch |
| Live VS Code window | a server `node` extension-host tree + its Claude/terminal children; group by parent PID and age | Decision table |
| Other Claude sessions | `anthropic.claude-code-*/native-binary/claude` not your ancestor | Decision table (may be the user's parallel agents) |
| Watchers / long user jobs | `marp`, `watch.sh`, jupyter, tensorboard, etc. | Decision table |
| Stale VS Code server version | node-health "OLD" stack | Decision table: close/reload those windows |
| `sshd: $USER@notty` | 1 pid each, days old | Mention only; negligible |

Anything thread-heavy that is doing real compute on a login node: recommend
moving it to `hq`/`hqb` rather than killing it.

## 6. Report (follow the global answer style)

Lead with the settled number: `pids N/256 (P%), was M before` and the health
level. Then: what was killed (PIDs + why), any node-health pattern patch,
the decision table (what / PIDs / threads / age / recommendation), and the
recommended first thing to close (largest thread holder that isn't essential).
Close with state: done / still critical and blocked on the user's decision.

If a command is denied by the permission classifier, stop pursuing that
outcome, finish the report with what you have, and name the command the user
would need to allow.
