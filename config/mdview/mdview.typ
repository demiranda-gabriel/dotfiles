// mdview.typ — pandoc typst template for reading notes in a terminal.
//
// The page is not paper. md-view sizes it to the aspect ratio of the terminal
// window, so one "page" is one screenful in doc-view and `j` reads like a
// scroll rather than a page turn. Every geometry and colour value below is
// injected by md-view; see that script for how they are derived.

#let horizontalrule = align(center, line(
  start: (25%, 0%), end: (75%, 0%), stroke: 0.6pt + rgb("$rule$"),
))

$highlighting-definitions$

#set page(
  width: $pagewidth$pt,
  height: $pageheight$pt,
  margin: (x: $marginx$pt, y: $marginy$pt),
  fill: rgb("$bg$"),
  columns: $columns$,
)

#set text(
  font: ("Libertinus Serif", "Nimbus Roman"),
  size: $fontsize$pt,
  fill: rgb("$fg$"),
  // Hyphenation earns its keep only when justifying; with a ragged right
  // edge it just litters the text with breaks it did not need.
  hyphenate: $justify$,
)
#show math.equation: set text(font: ("New Computer Modern Math", "Libertinus Serif"))
#show raw: set text(font: ("DejaVu Sans Mono", "Liberation Mono"), size: 0.85em)

#set par(justify: $justify$, leading: 0.62em, spacing: 1.05em)
#set heading(numbering: none)

// Headings: the level-1 rule gives a long note visible structure when you are
// paging quickly.
#show heading.where(level: 1): it => block(above: 1.3em, below: 0.7em)[
  #text(size: 1.45em, weight: 700, fill: rgb("$accent$"), it.body)
  #v(-0.62em)
  #line(length: 100%, stroke: 0.7pt + rgb("$accent$"))
]
#show heading.where(level: 2): it => block(above: 1.15em, below: 0.5em)[
  #text(size: 1.18em, weight: 700, fill: rgb("$accent$"), it.body)
]
#show heading.where(level: 3): it => block(above: 1em, below: 0.4em)[
  #text(size: 1.02em, weight: 700, fill: rgb("$fg$"), it.body)
]
#show heading.where(level: 4): it => block(above: 0.9em, below: 0.35em)[
  #text(size: 1em, style: "italic", fill: rgb("$fg2$"), it.body)
]

// Code: a tinted panel, breakable so a long block does not blow a page.
#show raw.where(block: true): it => block(
  width: 100%,
  fill: rgb("$codebg$"),
  inset: (x: 0.7em, y: 0.6em),
  radius: 3pt,
  stroke: 0.5pt + rgb("$border$"),
  breakable: true,
  it,
)
#show raw.where(block: false): it => box(
  fill: rgb("$codebg$"),
  inset: (x: 0.28em),
  outset: (y: 0.24em),
  radius: 2pt,
  it,
)

#show link: set text(fill: rgb("$link$"))

#show quote.where(block: true): it => block(
  width: 100%,
  inset: (left: 0.9em, y: 0.35em),
  stroke: (left: 2pt + rgb("$accent$")),
  text(style: "italic", fill: rgb("$fg2$"), it.body),
)

#set table(inset: 6pt, stroke: none)
#show table.cell.where(y: 0): set text(weight: 700)
#show figure: set block(breakable: true)
#show figure.where(kind: table): set figure.caption(position: top)

$if(title)$
#block(above: 0em, below: 0.9em)[
  #text(size: 1.7em, weight: 700, fill: rgb("$accent$"), [$title$])
]
$endif$

$body$
