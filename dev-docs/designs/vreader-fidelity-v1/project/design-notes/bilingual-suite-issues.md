# Bilingual follow-up suite — #1640 · #1641 · #1646 · #1650

> Source of truth: `VReader Bilingual Suite Canvas.html`.
> Component files: `vreader-bilingual-suite.jsx` (#1640/#1646/#1650), `vreader-reading-time.jsx` (#1641).

Four committed decisions, one per `needs-design` issue.

---

## #1650 · Heading-translation treatment (feature #100)

**Decision: centered echo row (H-A).** A translated heading keeps HEADING
vocabulary, not paragraph vocabulary: centered, no left border, target-language
serif at 15.5px with wide tracking (5px for CJK), `t.sub` color, 6px under the
source strip. Component: `BSHeadingPair`.

- **Why not the paragraph row (H-C, rejected):** a left-anchored border under a
  centered element mixes two alignment systems; it reads as a pull-quote.
- **Numerals:** "Chapter 12" → 第十二章 — the translator owns numeral handling;
  the row never mixes scripts.
- **Short/front-matter headings** (Preface → 序言) stay legible because
  tracking carries the width. **Long headings** wrap centered.
- **Loading:** one centered shimmer bar (72×9) in the row's slot — same loading
  vocabulary as the paragraph rows from #1024, centered like the heading.
- **Inline dot-join (H-B, alt):** "CHAPTER 1 · 第一章" on one line. Tightest,
  but breaks when a heading wraps — an optimization for known-short headings,
  not the base treatment.
- Block enumeration: headings join `BLOCK_TAGS` keeping the 1:1 block↔segment
  contract — one heading, one row. The chapter-start drop cap (#68) is below
  the pair and untouched.

## #1646 · Sentence-granularity interlinear (bug #344)

**Decision: per-sentence rows (S-A), one step lighter than the paragraph row;
plus a designed DISABLED control state (S-C) as the per-format fallback.**
Components: `BSSentencePara`, `BSSentenceSlot`.

Row scale (vs committed paragraph row):

| | paragraph row | sentence row |
|---|---|---|
| size | 0.88× | 0.85× |
| border | `accent55` 2px | `accent40` 2px |
| gap above | 6px | 4px |
| between pairs | — | 7px |

- The paragraph still reads as ONE block: pairs are separated by 7px (less
  than the 0.9em paragraph gap), text-indent stays on the first sentence only,
  drop cap unaffected. Justification holds — justify never stretches a last
  line, so short sentences ("Mr. Bennet replied that he had not.") are safe.
- **States:** cached · loading (two shimmer bars) · pending (dashed stub,
  #1024 ghost vocabulary).
- **Fallback:** where a pipeline can't hold the 1:1 inject contract at
  sentence level (Gate-4), the setup-sheet Sentence segment renders at 45%
  opacity with an info footnote — the control dims rather than silently
  forcing `.paragraph`.
- Granularity change is live per-book; cache rows are segment-count-keyed, so
  the sheet surfaces the re-translate cost (see #1640 cost strip).

## #1640 · Translation-settings re-entry (feature #99)

**Decision: a "Translation settings" row inside the More menu's bilingual
cluster (canonical) + tapping the EN↔中 pill (secondary). Both reopen the
existing setup sheet, edit-framed.** Components: `BSMorePopover`,
`BSSettingsSheet`, `BSCostStrip`, `BSRetranslateBanner`, `BSBilingualPill`.

- **Cluster:** when bilingual is ON the toggle row and the new settings row
  share one accent-tinted group (radius 12, inset divider). The settings row's
  sub-line doubles as a status readout: "Chinese · Paragraph · Claude". When
  bilingual is OFF the row is absent (same rule as #864's re-translate row).
- **Edit framing:** title "Translation settings" (not "Bilingual mode"),
  Cancel in the leading slot, context strip naming the book, CTA varies:
  - no changes → quiet "Done"
  - cached language picked → "Switch to French" (+ neutral strip: instant,
    nothing re-paid)
  - new language picked → accent "Apply · re-translate as you read"
    (+ tinted strip: "≈ $0.31 for the rest of the book")
  - granularity changed → strip: "starts from this page".
- **Cache badges:** language tiles that already have cache rows carry a green
  tick badge — the cost story is visible before the strip says it.
- **Confirmed:** floating banner under the top chrome ("Re-translating in
  Japanese… · Cached Chinese stays — switch back anytime"); the pill flips to
  EN↔日; untranslated paragraphs show the #1024 pending ghost.
- **Pill press state:** `accent33` fill + 2px `accent55` ring.

## #1641 · In-reader total reading time (feature #101)

**Decision: the trailing metrics label (under the scrubber) becomes a tap
target that cycles page ↔ time readouts; the time readout carries BOTH
durations. Book details gains Reading time rows as the always-on home. No new
chrome.** Components: `RTMetricsLine`, `RTBottomChrome`, `RTBookDetailsRows`.

- Readouts: `414 pages left in book` ↔ `12m read · 6h 40m total`. Session
  first (it's what's changing), total second. Choice persists per book.
- **First-ever session:** `4m read · first session` — total == session, so
  repeating the number would be noise.
- **Long totals:** above 10h the total drops minutes — `41h`, never `41h 23m`.
- **Narrow widths:** leading (chapter title on production engines) truncates
  with ellipsis; the trailing label is `flex-shrink: 0` and never wraps.
- **Book details rows:** Reading time `6h 40m total` (sub: "23 sessions since
  Mar 2") · This session `12m` · Average session `17m`.

---

| File | Role |
|---|---|
| `VReader Bilingual Suite Canvas.html` | Canvas — every state across themes |
| `vreader-bilingual-suite.jsx` | `BSHeadingPair`, `BSSentencePara`, `BSSentenceSlot`, `BSParagraphPara`, `BSReadingPage`, `BSMorePopover`, `BSSettingsSheet`, `BSCostStrip`, `BSRetranslateBanner`, `BSBilingualPill` |
| `vreader-reading-time.jsx` | `RTMetricsLine`, `RTBottomChrome`, `RTBookDetailsRows` |
