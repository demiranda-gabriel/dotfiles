# Terminal portability and remote-cluster deployment

**Audience:** an implementing agent picking up `mathify`, working over VS Code
Remote-SSH to a compute cluster.
**Date:** 2026-09-01. Every measurement below was taken on the author's macOS
machine; re-measure on the actual client before trusting the font table.

---

## 0. Current state — read this first

`mathify` is **built, tested, and deliberately DISABLED.**

- Code, 29 passing tests, CLI, and `README.md` are all in this repo.
- The `hooks.MessageDisplay` key was **removed** from `~/.claude/settings.json`
  at the user's request after a first trial. Pre-install backup:
  `~/.claude/settings.json.bak-mathify`.
- Do not assume the hook is active. To re-enable, re-add that key pointing at
  `hooks/mathify.sh` and restart Claude Code (hooks load at startup only).

Run the tests before changing anything:

```bash
.venv/bin/python -m unittest discover -s tests -t .
```

---

## 1. The question this document answers

Does the Unicode `MessageDisplay` approach work in terminals other than kitty —
specifically the VS Code integrated terminal?

**Yes, and it is the only one of the four researched architectures that does.**

The conversion happens inside the hook, in Python, before any byte reaches the
terminal. What the terminal receives is ordinary UTF-8 text. Nothing about the
approach is terminal-specific.

| Approach | VS Code | Claude desktop app | kitty / Ghostty / WezTerm | SSH | tmux |
|---|---|---|---|---|---|
| **A — Unicode `MessageDisplay` hook (this repo)** | yes | yes | yes | yes | yes |
| B — `tformula` PTY proxy (kitty graphics) | **no** | **no** | yes | yes | needs `allow-passthrough on` |
| C — `termtex` sidecar (kitty graphics) | **no** | **no** | yes | partial | needs `allow-passthrough on` |
| OSC 66 text sizing (kitty 0.40+) | **no** | **no** | kitty only | yes | **no** |

Why B, C, and OSC 66 are out in VS Code: the VS Code terminal is **xterm.js**,
which implements no kitty graphics protocol and no Unicode placeholders
(xtermjs/xterm.js#5711). Same engine as the Claude desktop app. This is a
structural absence, not flakiness — there is no configuration that enables it.

---

## 2. Remote cluster: what runs where

This is the part most easily got wrong. With VS Code Remote-SSH the work splits
across two machines:

```
 LOCAL (laptop)                          REMOTE (cluster)
 ─────────────────────────────────       ────────────────────────────────
 VS Code UI                              VS Code Server
 xterm.js terminal renderer   <── PTY ── shell
   * draws the glyphs                    claude (Claude Code CLI)
   * resolves fonts                        └── spawns hooks/mathify.sh
   * owns cell geometry                          └── .venv/bin/python
```

Consequences, all of which the implementing agent must respect:

1. **The hook executes on the cluster.** The Python venv and `mathify/` must
   exist *there*, and `hooks/mathify.sh` must be executable there. Path in
   `settings.json` is a **cluster-side absolute path**, and it is the cluster's
   `~/.claude/settings.json` that matters.
2. **Fonts are a local concern.** Glyph resolution happens in the laptop's
   xterm.js. Installing fonts on the cluster does nothing. Do not waste time
   provisioning fonts on the compute node.
3. **Cell geometry is local.** Column alignment in the 2D display blocks is
   decided by the local renderer, so it is consistent regardless of the cluster.
4. **No graphics transfer modes.** Irrelevant here since no graphics are used,
   but for the record: over SSH the kitty protocol's file and shared-memory
   transfer modes do not work; only direct/base64 does.
5. **`TERM` is forced.** The user's VS Code settings contain
   `"terminal.integrated.env.linux": { "TERM": "xterm-256color" }`, so on the
   cluster `TERM=xterm-256color`. **Do not gate any behaviour on `TERM`
   containing `kitty`** — it never will in this setup. If capability detection
   is ever added, detect the *renderer*, and default to the text path.
6. **Python on the cluster may differ.** The venv here was built from
   `miniconda3` Python 3.12. `mathify` uses only the stdlib (the installed
   `flatlatex`/`pylatexenc` are unused — see §6), so any Python ≥ 3.9 with
   `dataclasses` and `unicodedata` works. Rebuild the venv on the cluster
   rather than copying it; venvs are not relocatable across machines.

---

## 3. What actually varies between terminals: font coverage

Only glyph *appearance* varies. Correctness and alignment do not.

**Why alignment is safe:** xterm.js is cell-based. One character occupies one
cell regardless of the glyph's natural advance width, so a proportional
fallback glyph gets squeezed or clipped inside its cell but **does not shift the
grid**. The box-drawing alignment in stacked fractions, big-operator limits, and
matrices survives any font. This was the main worry and it is not a real risk.

**What is a real risk:** substituted glyphs looking wrong. The user's VS Code
has **no `terminal.integrated.fontFamily` set**, so the terminal falls back to
the macOS default chain (Menlo → Monaco → Courier New).

Measured coverage of the glyph classes `mathify` emits:

| Glyph class | Menlo (VS Code default) | JetBrains Mono | STIX Two Math |
|---|---|---|---|
| Greek `α β γ Γ Δ Ω` | all 24/24 | — | 24/24 |
| Operators, arrows `∑ ∫ √ ≤ → ⊗ ⟨ ⟩` | all 24/24 | — | 24/24 |
| Box drawing `─ │ ‾ ⎛ ⎝ ⎡ ⎣ ⎧ ⎨` | all 18/18 | — | 18/18 |
| Sub/superscripts `² ⁿ ᵢ ⱼ ₖ` | 16/19 | — | 9/19 |
| Blackboard bold `ℝ ℂ ℕ ℤ ℚ` | present | present | present |
| **Script letters `ℋ ℒ ℛ ℬ ℰ ℱ ℐ ℳ`** | **absent** | **absent** | present |
| **`ℏ` (hbar)** | **absent** | **absent** | present |
| **`ℓ`** | **absent** | present | present |
| **Math alphanumerics U+1D400–1D7FF `𝔤 𝒩 𝐄`** | **absent (0/9)** | **absent** | present (9/9) |

Nothing renders as tofu — macOS substitutes — but it substitutes from
*proportional* fonts, which is why the glyphs look off:

| Glyph | macOS fallback font | Problem |
|---|---|---|
| `ℋ ℒ ℛ ℬ ℰ ℱ ℐ ℳ` | Arial Unicode MS | proportional |
| `ℓ` | Verdana | proportional |
| **`ℏ`** | **Hiragino Sans (CJK)** | proportional *and* East-Asian-width ambiguous |
| `𝔤 𝒩 𝐄` | NewComputerModernMath | proportional |

`ℏ` is the worst case: U+210F is East_Asian_Width=Ambiguous and the fallback is
a CJK font designed for double-width cells. `mathify/boxes.py::cwidth()` treats
Ambiguous as width 1, which matches xterm.js's default ("treat ambiguous as
narrow"), so the *accounting* is consistent — but the glyph may look cramped.

---

## 4. The two fixes

### 4a. Font route — client-side, no code, ~5 minutes

In **local** VS Code `settings.json`:

```json
"terminal.integrated.fontFamily": "'JetBrains Mono', 'STIX Two Math', monospace"
```

xterm.js honours CSS font-fallback lists. STIX Two Math covers every gap above.
Still a proportional fallback for the substituted glyphs.

Cleaner, single-font option:

```bash
brew install --cask font-juliamono
```

JuliaMono is monospaced *and* has unusually broad math coverage, so one font
handles everything with correct advance widths. Set it as the terminal font in
VS Code (and in kitty, if used). Nerd Fonts do **not** help — they add icons,
not math.

### 4b. Portable glyph mode — code route, the robust answer

Make `mathify` terminal-agnostic **by construction** instead of by per-machine
font configuration. This matters precisely because the target is a cluster
reached from potentially several client machines, whose fonts the user may not
control.

Proposed design, consistent with the existing invariants:

1. Add a `SAFE_CODEPOINTS` allowlist — Basic Multilingual Plane only, restricted
   to blocks with near-universal monospace coverage: Greek, Mathematical
   Operators (U+2200–22FF), Arrows (U+2190–21FF), Box Drawing / Misc Technical
   for the delimiters, Superscripts and Subscripts (U+2070–209F), and the
   *specific* Letterlike Symbols that Menlo actually has (`ℝ ℂ ℕ ℤ ℚ` — but
   **not** `ℋ ℒ ℛ ℬ ℰ ℱ ℐ ℳ ℏ ℓ`).
2. Add a mode flag, e.g. `MATHIFY_GLYPHS=portable|full`, read in
   `mathify/hook.py` and threaded into `Renderer`. Default `portable` when the
   variable is unset and `TERM` is not a kitty variant; `full` is opt-in.
3. In `latex_to_unicode`, extend the existing safety gate: in portable mode, any
   output codepoint outside the allowlist is a conversion **failure**, so the
   expression falls back to raw LaTeX. This reuses the mechanism already there
   for residual `\ { } &`.
4. Consequence to accept deliberately: `\mathcal{L}` and `\hbar` stay as LaTeX
   in portable mode rather than becoming a Verdana glyph wedged into a Menlo
   cell. That is the correct trade — a legible `\hbar` beats an illegible `ℏ`.
5. Tests to add: for the full corpus in `tests/test_mathify.py`, assert that
   every codepoint of every portable-mode output is in the allowlist.

Note `mathify/symbols.py` already prefers BMP letterlike forms over SMP where
one exists (`MATHBB` maps `R`→`ℝ` not `𝕽`; `MATHCAL` maps `L`→`ℒ` not `𝓛`), so
the portable allowlist mostly *subtracts* from an already-conservative table.

---

## 5. Open questions — resolve these before further polish

### 5a. Does Claude Code's markdown renderer reflow the 2D display blocks?

**This is the blocking unknown, and the likely reason the first trial was
unconvincing.** `displayContent` replaces the text content of the assistant
message, which then goes back through Claude Code's Ink/markdown rendering path.
If that path reflows paragraphs, the multi-line aligned blocks (stacked
fractions, big-operator limits, matrices, `align`, `cases`) will be collapsed
and their column alignment destroyed.

- Inline math is **not** exposed to this — it never adds rows.
- Untested candidate fix: emit display blocks wrapped in a fenced code block so
  the renderer preserves them verbatim. Costs the block its "prose" look and may
  add a visible border depending on theme.
- **Get a description of what the user actually saw before implementing
  anything.** The failure could equally be font substitution (§3) or the 2-space
  indent interacting with markdown. Do not guess.

### 5b. Does `displayContent` pass raw ANSI escapes through?

Unresolved from documentation. A probe is already built in: when the assistant
message contains the literal token `MATHIFY_ESCAPE_PROBE`, the hook replaces it
with an SGR colour test, an OSC 66 text-sizing test, a kitty graphics test, and
instructions for reading the result (`mathify/hook.py::_escape_probe`).

Requires the hook to be enabled and a session restart. Interpretation:

- coloured/bold text appears → ANSI survives; display equations could be dimmed
  or coloured
- escape codes appear as literal text → the renderer escapes them
- lines missing entirely → the renderer strips them

OSC 66 would only ever help in kitty, never in VS Code, so it is low priority
for the cluster use case.

---

## 6. Facts already established — do not re-derive

### The `MessageDisplay` contract, read out of the Claude Code 2.1.247 binary

The public research write-up had several of these wrong.

- stdin fields are **snake_case**: `turn_id`, `message_id`, `index`, `final`,
  `delta` (plus the common `session_id`, `cwd`, `hook_event_name`).
- **`message_id` is stable across every flush of one message.** It is the
  correct key for streaming state — not `session_id` + heuristics.
- **`delta` is always whole lines**, except the final flush which may end
  mid-line. The final flush's delta is *empty* when the message ends on a
  newline, so treat `final` as the end-of-message signal regardless.
- `index` is zero-based and increments once per flush. Exactly one flush has
  `final: true`.
- Output shape: `{"hookSpecificOutput": {"hookEventName": "MessageDisplay",
  "displayContent": "..."}}`. Omitting it, or returning the delta unchanged,
  displays the original.
- Display-only: the stored message and what the model sees are untouched.
- Fails open: on error or timeout the original delta is displayed.
- `displayContent` is capped at 10,000 characters.

### `flatlatex` and `pylatexenc` are installed but unused

Both were evaluated and rejected. They leak unconverted commands into their
output (`\langle`, `\rangle`, `\to`, `\beginpmatrix`, `\textsoftmax`) and render
`Y_l^m` as `(Y[l])ᵐ` — results that read **worse** than the LaTeX they replace.
`mathify/render.py` replaces them entirely. They remain installed only as a
comparison baseline. Do not reintroduce them as the primary backend.

### Measured performance

40–50 ms full subprocess round-trip, dominated by Python interpreter startup;
7 ms for the conversion itself on a 3,215-character message. Against the event's
10-second budget this is free, which is why there is **no cache** — and
therefore no cache I/O to go wrong. A 3-second `SIGALRM` watchdog sits inside
the 10-second budget.

---

## 7. Design invariants — preserve these

Any change must keep all five. They are what make the hook safe to leave on.

1. **Never emit half-converted LaTeX.** `render.py` raises `Unsupported` on any
   unknown command; `latex_to_unicode` refuses output containing a residual
   `\`, `{`, `}`, or `&`. Partial conversion is worse than none.
2. **Inline math never grows a row.** Anything needing extra rows in running
   prose is rendered single-line (`\frac{a+b}{c+d}` → `(a + b)/(c + d)`,
   `F^{\mu\nu}` → `F^(μν)`) or refused. Only a line that is *entirely* display
   math gets 2D layout.
3. **Fail open, always.** Every failure path exits 0 with no stdout. Malformed
   JSON, non-dict JSON, timeout, unknown command, oversize output, crash — all
   silent no-ops, with a `BaseException` backstop so no traceback can reach the
   display path.
4. **Code is never touched.** Fenced blocks (`` ``` `` and `~~~`), indented blocks, and
   inline backtick spans pass through verbatim. Fence state is keyed on
   `message_id` and persisted under `~/.cache/mathify/state/`.
5. **Streaming is invariant.** Output must be byte-identical to single-flush
   output for every chunk size. `tests/test_mathify.py::TestStreaming`
   asserts this for sizes 1–15; keep that test green.

---

## 8. Suggested order of work

1. **Ask the user what looked wrong** in the first trial (§5a). Everything else
   is guesswork until that is known. One question, large payoff.
2. **Apply the font fix** (§4a) on the local client. Cheap, improves every
   terminal, and rules font substitution in or out as the cause of §5a.
3. **Re-enable the hook on the cluster** and confirm it fires: rebuild the venv
   there, register the cluster-side absolute path, restart, verify with a
   simple `$E = mc^2$`.
4. **Resolve §5a.** If blocks are reflowed, implement the fenced-output option
   behind a flag and let the user pick.
5. **Implement portable glyph mode** (§4b). This is the durable answer for a
   multi-client remote setup, and it is a small, well-scoped change that reuses
   the existing safety gate.
6. **Run the escape probe** (§5b) and record the result in this file either way.

---

## 9. References

- `README.md` — architecture, design rules, install/uninstall
- `latex-in-terminal-research.md` (in `~/Downloads`) — the original four-option
  survey. Treat its `MessageDisplay` contract details as superseded by §6.
- Kitty graphics protocol — https://sw.kovidgoyal.net/kitty/graphics-protocol/
- Kitty text sizing protocol — https://sw.kovidgoyal.net/kitty/text-sizing-protocol/
- Claude Code hooks — https://code.claude.com/docs/en/hooks
- xtermjs/xterm.js#5711 — no Unicode-placeholder support in xterm.js
- anthropics/claude-code#54546 — inline image rendering in the TUI (upstream)
