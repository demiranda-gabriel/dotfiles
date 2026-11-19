---
name: lecture-walkthrough
description: Turn a lecture slide deck (PDF) into a comprehensive, didactic written walkthrough that cites slide numbers, justifies every step the slides only assert, checks the slides' numbers, and ends with self-check questions. Use when the user says "walk me through lecture N", "explain these slides", "lecture N just got uploaded", "I prefer reading to watching", or asks for a written explanation of a course deck (e.g. MIT 6.5940 EfficientML slides in resources/slides/).
---

# lecture-walkthrough

Goal: the user reads this **instead of** watching the lecture, and wants to
*understand* it, not just skim it. The walkthrough has to be complete (every part of
the deck is covered), justified (explain *why*, not only *what*), anchored (every
claim points to a slide number), and lean (no lists of terms, no padding).

Reference example: the Lecture 12 (Transformers and LLM) walkthrough of
2026-10-27, in the compression project
(`resources/slides/Lec12-Transformers and LLM.pdf`). The user singled out the
slide-number citations as the most useful feature.

---

## 1. Locate and extract the deck

```bash
find . -maxdepth 3 -iname '*lec*N*' -name '*.pdf'      # slides usually in resources/slides/
S=<scratchpad>                                            # never /tmp, never the repo
pdfinfo "<deck>.pdf" | grep Pages
pdftotext -layout "<deck>.pdf" $S/lecN.txt                # one pass, whole deck
```

- Read the **whole** text file with Read, in one go. Decks run to about 1.5k lines,
  so this is cheap. Don't sample.
- Read the text past these artefacts:
  - Ligatures come out broken: "e cient" means efficient, and a line holding only `ffi` / `fi` / `fl`
    is noise.
  - The slide number is the trailing integer on the footer line
    (`https://e cientml.ai   21`). Use those numbers for citations, not page
    indices. They are normally the same, but check.
  - Roadmap or agenda slides that repeat (e.g. "Transformer: tokenize → embed → …")
    mark section boundaries. Use them to build the outline and don't explain them.

## 2. Render only the slides whose content is an image

Text extraction drops equations, plots, tables of numbers and diagrams. Find
them from clues in the text:

- a bullet that announces a formula with nothing after it ("The general form:",
  "Equation of activation functions");
- a table header or "PPL results" with no numbers;
- stray labels such as "(Manually set)", "init with 0", "x" / "√", axis words;
- a key mechanism slide (the one that *defines* the method).

Render at low resolution and view each one with Read (as an image):

```bash
for p in 32 44 45 47 59 70 85 86; do
  pdftoppm -f $p -l $p -r 60 -png "<deck>.pdf" $S/p$p
done
```

60 dpi is enough to read equations and keeps the token cost down. Expect roughly
8–15 slides per deck. Rendering all of them is wasteful.

## 3. Plan before writing

Build a slide map: lecture part → topics → slide ranges. Then, for each topic,
note:

1. **The problem it solves.** What failed before (the motivating slides).
2. **The mechanism.** The equation or algorithm, taken from the rendered slide.
3. **The missing why.** The step the slide asserts without justifying. Slides
   are compressed and leave out this step most of the time. This is where most of the value comes from.
4. **The evidence.** The table or plot on the slide, with the actual numbers.
5. **The cost or trade-off,** especially memory, FLOPs or bandwidth, since this is
   an efficiency course.

Also identify the **single thread** that ties the lecture together (L12: "every
change since 2017 answers what it costs to run at inference"). That thread
becomes the opening line.

## 4. Write the walkthrough

### Structure

- **Opening line:** the thread of the lecture in one or two sentences. Then one short
  provenance paragraph: which slides were read as text, which were rendered,
  and which facts come from papers recalled from memory.
- **Parts mirror the lecture's own parts** (Part I, II, …). Subsections are
  numbered sequentially across the whole walkthrough. Each heading carries its
  slide range: `### 10. The KV cache … (slides 49–57)`.
- Inside the text, cite specific slides whenever a number, figure or claim
  comes from them: "Slide 57 (a 30B model trained on 150B tokens) shows GQA …".
- Use a table when the lecture compares families or variants (e.g.
  encoder–decoder / encoder-only / decoder-only).
- **Connections to the user's project:** a short section clearly labelled
  as the assistant's own observations, not the lecture's. Read the project
  brief or memory first so the links are concrete (e.g. RoPE ↔ E(3) invariance, attention
  ↔ message passing, head merging ↔ structured pruning). Keep it to 3–5 items.
- **Questions to check your understanding:** about 5 questions that test mechanisms, not recall.
  Give the answer inline for any numeric question.
- **Status line:** where the walkthrough lives (chat only unless asked), what
  was verified, and a one-line offer, with a recommendation, to save it (e.g. a section
  in `notes/lecture_takeaways.md`).

### Explaining each concept

Follow this order: problem → mechanism → why it works → evidence → cost. Do:

- **Derive the steps the slides skip.** For example, the √d_k scaling via
  Var(q·k) = d_k, why pre-norm keeps an identity gradient path, why sinusoidal
  encodings make a position shift a rotation, and why interpolation beats
  extrapolation for RoPE.
- **Check the slide's arithmetic and add one check of your own.** L12 had the
  12d² parameters per block giving LLaMA-7B ≈ 6.7B, KV cache bytes per token,
  and C ≈ 6ND reproducing the Chinchilla table. Say explicitly that the numbers match.
- **Walk through toy examples on the slides.** For instance, the MoE capacity factor with 6
  tokens and 3 experts, or Flamingo's K/V of length 32 = 27 visual + 5 latents.
- **Add caveats the lecture omits** when they change how a result should be read
  (e.g. "emergent abilities" vs. Schaeffer et al. 2023, or MoE saving FLOPs but
  not memory). Keep each caveat to one or two sentences.
- **Bring out the efficiency angle** even where the slide doesn't (e.g. decoding
  is memory-bound at about 1 FLOP/byte, so shrinking the KV cache makes each token faster).

Don't:

- define every term or list jargon as bullet fragments;
- restate the slide's bullets as the explanation;
- list approaches not taken, or pad with transitions;
- go deep on peripheral slides (application demos, motivation pictures). One
  sentence each is enough.

### Provenance discipline

Keep three kinds of content visibly separate:

| Source | How to mark it |
|---|---|
| On the slide | cite "slide N" |
| From a cited or related paper, recalled from memory | "(from the paper, not the slides)", or name it: "Xiong et al. (2020) showed …" |
| The assistant's own reasoning or observation | "This isn't on the slides, but …", or put it in the project-connections section |

Web research is optional. Do it inline (WebSearch/WebFetch), and only for facts that
are uncertain or that the user will rely on. Don't fan out to subagents: the user's
global cap and the cost of agents both argue against it. If no search was run, say so
in the provenance paragraph.

## 5. Formatting rules (from the user's global CLAUDE.md)

- Every equation goes in a display block `$$ … $$` on its own line, with blank lines
  around it. Use one block per statement and split chained statements.
- Display blocks use **base LaTeX2e only**:
  - `\mathrm`, not `\text` or `\operatorname`; `\frac`, not `\tfrac` or `\dfrac`;
  - no `\,` `\;` `\!` `\ `, and no `\boxed`;
  - **no amsmath environments**: write matrices as
    `\left( \begin{array}{cc} … \end{array} \right)`, never
    `pmatrix`/`bmatrix`, and write cases as two separate display blocks, never `cases`;
  - no literal unicode inside math. `\quad`, `\odot`, `\cdot`, `\sigma`, `\left(` are fine.
- Inline math is **unicode prose**, never `$…$`: ρ(z), √d_k, O(N²), θ′ = θ/2,
  n_kv. The same applies inside table cells.
- Write full sentences that explain mechanisms. Lead each section with the point.

## 6. Delivery

- Deliver in chat by default (the user reads it there). Save to a file only if asked.
- Length scales with the deck. For about 90 slides and 4 parts, expect a long answer
  of roughly 15–20 numbered subsections. Depth goes to the
  mechanism-defining slides, not to the demos.

## 7. Pre-send checklist

- [ ] Every lecture part and every non-trivial slide range is covered, and none are skipped.
- [ ] Every section heading has a slide range, and every quoted number has a slide number.
- [ ] Every rendered equation is reproduced correctly (compared with the image).
- [ ] At least one "why" derivation for each core mechanism.
- [ ] Arithmetic checks done and stated.
- [ ] Provenance marked: slide / paper from memory / own observation.
- [ ] No `$…$` inline math, and no amsmath in display blocks.
- [ ] The project-connections section is labelled as the assistant's own and kept short.
- [ ] Self-check questions included, with numeric answers given.
- [ ] Status line at the end, with a save offer and a recommendation.
