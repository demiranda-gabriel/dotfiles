# Why tmux window switching stays on Alt+<digit>

**Status: reference only -- NOT the shipped setup.** `config/tmux/tmux.conf`
binds plain `M-1`..`M-0` to `select-window -t 1..10` and that is what is in use.
This note records why the Ctrl+<digit> and Alt+Ctrl+<digit> variants were tried
on 2026-09-02 and abandoned, so the experiment is not repeated. Everything below
the fix heading is what you would have to add to make them work.

## Why a plain binding cannot work in VS Code

The key path is: macOS -> VS Code keybinding layer -> xterm.js encoder -> ssh
-> tmux. Two gates drop the keypress before tmux ever sees it:

1. VS Code owns `ctrl+1`/`ctrl+2`/`ctrl+3` (`workbench.action.focusFirstEditorGroup`
   and friends) and they sit in the default `terminal.integrated.commandsToSkipShell`
   list, so the terminal is never handed the key.
2. xterm.js has no way to *encode* `ctrl+<digit>` or `ctrl+alt+<digit>`. There is
   no legacy control byte for those combinations (only `ctrl+2`..`ctrl+8` have
   legacy aliases, and they collide with NUL/ESC/FS/GS/RS/US/DEL), and xterm.js
   does not negotiate xterm `modifyOtherKeys` or the CSI-u protocol.

Plain `Alt+<digit>` sidesteps both, because it encodes as ESC-then-digit, which
every terminal since the 1980s emits. That is why the old `M-1`..`M-0` binding
worked everywhere with zero configuration.

## The fix: make VS Code emit the sequence itself

Bypass gate 2 by having VS Code send the bytes verbatim with
`workbench.action.terminal.sendSequence`. tmux decodes the xterm
modifyOtherKeys form

    CSI 27 ; <mod> ; <code> ~

where `<mod>` is `1 + shift(1) + alt(2) + ctrl(4)`, so ctrl+alt = 7, and
`<code>` is the ASCII codepoint of the digit (`1` = 49 ... `9` = 57, `0` = 48).
`ESC [ 27;7;49 ~` therefore arrives as the tmux key `C-M-1`.

Paste the block below into the **Mac-side** user keybindings (Cmd+Shift+P ->
"Preferences: Open Keyboard Shortcuts (JSON)"). It is user-level on the client
machine, so it cannot be shipped from this repo or from workspace settings --
that is why it lives here as a snippet to copy.

The tmux side already requires `set -s extended-keys always` plus the
`xterm*:extkeys` terminal-feature assertion; both are set near the top of
`config/tmux/tmux.conf`.

```json
[
  {
    "key": "ctrl+alt+1",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;49~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+2",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;50~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+3",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;51~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+4",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;52~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+5",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;53~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+6",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;54~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+7",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;55~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+8",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;56~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+9",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;57~" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+0",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[27;7;48~" },
    "when": "terminalFocus"
  }
]
```

## If it still does not fire

Run `cat -v` in a pane, press Alt+Ctrl+1, and read the bytes:

- `^[[27;7;49~` -> VS Code is emitting correctly; the problem is on the tmux
  side (check `tmux list-keys -T root | grep select-window`).
- `^[1` -> the sendSequence binding is not active; VS Code degraded the combo to
  Alt+1. Confirm the JSON landed in the *user* keybindings and that `when` is
  `terminalFocus`.
- nothing at all -> macOS or VS Code is still swallowing the chord upstream;
  pick a different chord, or fall back to Alt+<digit>.

Some tmux builds prefer the CSI-u spelling instead; if the modifyOtherKeys form
is ignored, swap the `text` values to `\u001b[49;7u` (same mod/code numbering,
different envelope).
