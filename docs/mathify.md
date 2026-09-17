# mathify — LaTeX math as Unicode in the Claude Code TUI

A `MessageDisplay` hook that converts LaTeX math to Unicode **at display time
only**. The transcript, Claude's context, `--resume`, and anything you copy out
all keep the exact original LaTeX.

```
Claude writes:   The loss is $\mathcal{L} = -\frac{1}{N}\sum_{i=1}^{N} \log p_\theta(x_i)$
You see:         The loss is ℒ = -1/N∑ᵢ₌₁ᴺ log p_θ(xᵢ)
Transcript has:  The loss is $\mathcal{L} = -\frac{1}{N}\sum_{i=1}^{N} \log p_\theta(x_i)$
```

Display math gets real two-dimensional layout:

```
$$\frac{\partial \mathcal{L}}{\partial \theta_j} = -\sum_{i=1}^{N} (y_i - \hat{y}_i) x_{ij}$$

 ∂ℒ       N
───── = - ∑  (yᵢ - ŷᵢ)xᵢⱼ
 ∂θⱼ     i=1
```

## Why this architecture

This is architecture **A** from `latex-in-terminal-research.md`. The pixel-based
options (B: `tformula` PTY proxy, C: `termtex` sidecar) need the kitty graphics
protocol, which the **Claude desktop app cannot provide** — it renders the TUI
through xterm.js, and xterm.js has no Unicode-placeholder support
(xtermjs/xterm.js#5711). This approach is pure text, so it works in the desktop
app, in kitty, over SSH, and inside tmux.

## Install

Already done, but for the record:

```bash
python3 -m venv .venv && .venv/bin/pip install flatlatex pylatexenc
```

and in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "MessageDisplay": [
      { "hooks": [ { "type": "command",
                     "command": "/path/to/latex-terminal/hooks/mathify.sh",
                     "args": [], "timeout": 10 } ] }
    ]
  }
}
```

**Hooks load at startup — restart Claude Code before this takes effect.**

> Note: `flatlatex` and `pylatexenc` are installed but the shipped renderer
> does not use them. Both leak unconverted commands (`\langle`, `\to`,
> `\begin{pmatrix}`) into their output and render `Y_l^m` as `(Y[l])ᵐ`, which
> reads worse than the LaTeX it replaced. `mathify/render.py` replaces them.
> They are kept only as a comparison baseline for `tools/compare.py`-style
> experiments.

## Usage

Nothing to do — it runs automatically. To try the renderer directly:

```bash
./bin/mathify '\sum_{i=1}^{N} \frac{x_i}{\sigma^2}'    # display style
./bin/mathify -i '\alpha \in \mathbb{R}^n'             # inline style
cat notes.md | ./bin/mathify                           # filter a document
```

## Design rules

**1. Never emit half-converted LaTeX.** `render.py` raises `Unsupported` on any
command it does not know, and `latex_to_unicode` refuses output containing a
residual `\`, `{`, `}`, or `&`. On refusal the original LaTeX is left alone.
This is the single most important rule: partial conversion is worse than none.

**2. Inline math never grows a row.** Anything that would need multiple rows in
running prose is either rendered single-line (`\frac{a+b}{c+d}` → `(a + b)/(c + d)`,
`F^{\mu\nu}` → `F^(μν)`) or refused. Only a line that is *entirely* display math
gets 2D layout. This is the "Unicode for inline, pixels for display" split that
both the Codex prototype and TFormula converged on independently.

**3. Fail open, always.** Every failure path exits 0 with no stdout, so Claude
Code displays the original text. Malformed JSON, a timeout, an unknown command,
an oversize result, a crash — all silent no-ops. There is a 3-second self-imposed
watchdog inside the event's own 10-second budget, and a `BaseException` backstop
so no traceback can ever reach the display path.

**4. Code is never touched.** Fenced blocks (`` ``` `` and `~~~`), indented code blocks,
and inline backtick spans pass through verbatim. Fence state is keyed on
`message_id`, which the binary documents as stable across every flush of a
message, and persisted under `~/.cache/mathify/state/`.

**5. `$` is guarded.** A single-dollar span must show real mathematical
structure before it is treated as math, so `$12.50`, `$1,000`, `$PATH`, and
`costs $5 and $10` are left alone. Spans that begin or end with whitespace are
rejected outright, which is what kills the currency cases.

## Streaming

`MessageDisplay` fires per batch of completed lines, so a `$$…$$` block can be
split across flushes. Unterminated display blocks are held in state and
typeset on the flush that closes them, capped at 60 lines, and flushed raw if
the message ends first. `tests/test_mathify.py::TestStreaming` asserts that
output is byte-identical to single-flush output for every chunk size 1–15.

## What it does well, and what it doesn't

Good: Greek, blackboard/script/fraktur/bold alphabets, single- and multi-level
scripts, stacked fractions, big operators with limits, matrices with extensible
brackets, `cases`, `align`, radicals, accents (composed to single codepoints via
NFC so terminals render one glyph), `\left…\right` with growing delimiters, and
TeX-style spacing including correct unary-minus handling.

Honest limits:

- **Inline math with unmappable scripts** falls back to `F^(μν)` rather than
  true superscripts, because Unicode has no superscript Greek. This is a Unicode
  limitation, not a bug.
- **Anything the renderer refuses stays as raw LaTeX.** That is the intended
  behaviour, not a failure — it is also exactly the hook point where a pixel
  sidecar would take over.
- **Very heavy notation** (deeply nested Clebsch–Gordan sums, Wigner D-matrices
  with three index groups) renders, but wide. It is legible; it is not
  beautiful.

## Diagnostics

The one question the research could not settle from documentation: does
`displayContent` pass raw escape sequences through, or does the Ink renderer
sanitise them? Ask Claude to say `MATHIFY_ESCAPE_PROBE` in a message; the hook
replaces that token with an SGR colour test, an OSC 66 text-sizing test, and a
kitty graphics test, then tells you how to read the result.

If ANSI survives, display equations could be dimmed or coloured. If OSC 66
survives *and you run in kitty*, display math could be set at double height with
no image pipeline at all — genuinely novel territory per the research doc.

To see conversions without the hook, pipe through `./bin/mathify`.

## Where this goes next

If you later want real typeset images for the equations Unicode cannot do
honestly, the sidecar (architecture C) composes with this cleanly and works
even from the desktop app, because the rendering terminal is a *different*
terminal from the one running Claude Code:

1. A `Stop` hook writes `last_assistant_message` to a spool file.
2. A watcher in a separate kitty window renders new entries through `termtex`.
3. `render.py` already classifies "Unicode-renderable" vs. "needs pixels" — the
   `Unsupported` path is the routing signal.

## Optional: kitty font configuration

Not needed in the desktop app, and `STIX Two Math` is already installed
system-wide so every glyph the renderer emits has coverage. If you move to
kitty and see tofu boxes for `\mathbb`/`\mathcal`/`\mathfrak`:

```conf
# ~/.config/kitty/kitty.conf
symbol_map U+2190-U+21FF,U+2200-U+22FF,U+27C0-U+27EF,U+2A00-U+2AFF STIX Two Math
symbol_map U+1D400-U+1D7FF STIX Two Math
```

## Tests

```bash
.venv/bin/python -m unittest discover -s tests -t .
```

26 tests: symbol correctness, spacing, the no-residual-LaTeX gate, a 3000-case
fuzz run asserting only `Unsupported` ever escapes, false-positive guards, code
safety, streaming invariance, and the hook's JSON contract and fail-open paths.

## Uninstall

Remove the `hooks.MessageDisplay` key from `~/.claude/settings.json` (a backup
from before install is at `~/.claude/settings.json.bak-mathify`) and restart.
