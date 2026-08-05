---
branch: feat/156-wi-1-txt-justify
threadId: 019fd25d-dcb4-7a13-8d49-7e015563ae7d
rounds: 2
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #156 WI-1 (GH #2077)

Justify TXT/MD body text at the `bodyTextStyle()` seam, exclude wrapping Markdown
headings in **scroll** mode, and prove pagination is unchanged.

## Scope of audit

A 9-file diff on `feat/156-wi-1-txt-justify`:

- production — `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt`
  (justify-by-default + `chunkTextAlign`), `.../reader/MarkdownRenderer.kt`
  (`isHeadingChunk`, sharing `contentEndOf` + the ATX regex with `renderWithMap`),
  `.../reader/TxtReaderBody.kt` (the scroll body's per-chunk heading variant);
- JVM tests — `TxtDisplaySettingsTest.kt`, `MarkdownRendererTest.kt`, `paged/TxtPaginatorTest.kt`;
- connected test + fixtures — `TxtJustificationConnectedTest.kt`,
  `androidTest/assets/latin-justify-book.txt`, `androidTest/assets/md-justify.md`.

The audit prompt asked four scope-specific questions rather than a generic review,
because this feature's failure mode is a *green test over a zero-pixel change*:

1. can any acceptance assertion pass without a post-layout number;
2. does anything assert CJK flush-right (WI-0 measured justification as a total
   no-op on space-free CJK);
3. can `textAlign` shift a page boundary on any path;
4. is the heading exclusion genuinely scroll-scoped, or silently attempted in paged.

Codex ran read-only against the worktree with the plan
(`dev-docs/plans/20260805-feature-156-android-justified-text.md`) as the reference.

## Round 1 — 1 Medium, 2 Low (no Critical/High)

Raw output: `.reports/audit-r1.txt` (thread `019fd25d-dcb4-7a13-8d49-7e015563ae7d`).

### Medium — AC-2b could pass with zero glyph movement

`c2_mdPagedHeading_sharesThePageAlignment_knownLimitation` asserted only that the
paged page's `Text` **requested** `TextAlign.Justify`. That stays green if Compose
receives the request and moves zero heading glyphs — exactly the false-green class
the rest of the suite exists to close, and exactly what CJK does in practice. The
known limitation was therefore *inferred from the requested style*, not measured.

**Fixed** (commit `4defdd0e`): the test now locates the heading's own rendered
extent inside the page `AnnotatedString`, derives the wrapped lines covering it,
requires the heading to span ≥2 lines, requires at least one of its justifiable
lines' `getLineRight` to **move** against a `Start` re-measure of the same
`TextLayoutInput`, and requires each to sit on the page's common justified edge.

Measured on `emulator-5554`: heading lines `[0,1,2,3,4]`, justifiable `[0,1,2,3]`,
all four moved `707/688/959/872 → 950/954/941/946` at a 974px measure.

### Low — the JVM paginator fake overstated its own evidence

`StyleSensitiveLineMeasurer`'s name and doc implied the JVM invariance test proved
Android applies alignment after line breaking. It cannot: with a fake measurer the
Start/Justify page arrays match *by construction*.

**Fixed**: renamed `StyleRecordingLineMeasurer`; the class doc and the test doc now
claim only what a JVM test can prove — the alignment genuinely reaches phase 1 (so
the equality is not vacuous) and the comparison can detect a real shift (the
larger-font sensitivity control) — and point at the connected real-measurer test
for the engine-level proof.

### Low — "every acceptance number is read back AFTER layout" overstated

Commit `b7c5bc67`'s message claimed more than the code did: AC-2b relied on the
layout-input `textAlign`, and the JVM assertions are deliberately request/structure
tests. **Fixed**: corrected in `4defdd0e`'s message to "every LATIN justification
assertion uses post-layout coordinates", with AC-2b now carrying a post-layout
number too.

### Not defects, recorded

- `isCjk(Char)` misses supplementary-plane CJK — it is fixture *selection* for a
  known BMP-heavy real book, not an assertion.
- RTL is not exercised; the production alignment is `Start`/`Justify` (direction-
  aware), and the `getLineRight` oracle is deliberately LTR.
- The 745-line connected test exceeds the ~300-line guidance. Accepted by the
  auditor: it sits inside this repo's established connected-acceptance range
  (664–1206 lines), and splitting it would break the in-run `controlPassed` gate
  that makes the CJK result interpretable at all.

## Round 2 — clean

Raw output: `.reports/audit-r2.txt` (thread `019fd26a-a36a-7922-b0f7-befe5d1d7e10`).

> No new Critical, High, or Medium findings. All three Round-1 findings are
> genuinely closed. […] The fixes did not disturb the ordered `controlPassed` gate
> before CJK characterization, the Start/Justify oracle-faithfulness replay, or the
> real-book CJK zero-movement characterization. **Final verdict: ship as-is.**

The re-audit specifically checked the new heading-extent lookup for mislocation and
false-failure risk (duplicate anchor text, a page slice starting mid-heading,
boundary lines, a heading truncated across a page break) and found the half-open
overlap checks correct and the zero-movement path un-passable.

## Answers to the four scope questions (round 1, unchanged by round 2)

1. **Post-layout numbers.** `a1`/`a2`/`c1`-prose cannot pass with zero Latin glyph
   movement (`moved.isNotEmpty()`, edge collapse, unchanged line ranges); `c2` now
   cannot either. The JVM assertions can — they are propagation/structure tests and
   are documented as such. The raggedness-collapse criterion was judged genuinely
   discriminating: it jointly requires a ≥40px `Start` spread, a ≤15px justified
   spread, a ≥3× collapse, a common edge ≥90% of the measure, actual moved lines,
   and **no** movement on paragraph-final lines.
2. **CJK.** Nothing requires CJK flush-right. `b1` deliberately requires *zero*
   movement and does not route through `assertJustifiedAndMoved`.
3. **Page boundaries.** No path found where the measured and rendered styles can
   diverge: one `effectiveStyle` merge feeds phase-1 measurement and phase-2 render;
   `renderPage` constructs content, not layout; the scroll heading variant lives in
   a mode with no paginator. The full-page-array comparison through the real
   `ComposeLineMeasurer` was accepted as sound evidence.
4. **Scroll scoping.** Per-chunk alignment exists only in `TxtBody`; nothing
   attempts it in the paged path. `isHeadingChunk` and `renderWithMap` share
   `contentEndOf` and `ATX.matchEntire`, so no chunk classifies differently — the
   sole documented exception being `"# "` (ATX-shaped, renders no glyphs).

## Verification run alongside the audit

- JVM: full `:app:testDebugUnitTest` — **2197 tests, 0 failures, 0 skipped**.
- Connected (`emulator-5554`, real `黑暗血时代.txt` re-pushed before every run):
  `TxtJustificationConnectedTest` **6/0/0**; regression suites
  `TxtPagedBodyConnectedTest` 6/0/0, `TxtPagedWindowedConnectedTest` 5/0/0,
  `PagedAcceptanceConnectedTest` 4/0/0, `TxtDisplaySettingsUiTest` 3/0/0,
  `MdReaderRenderTest` 3/0/0, `MdHighlightConnectedTest` 1/0/0.
- Mutation pass (each mutation applied, run, reverted):
  dropping `textAlign` from `bodyTextStyle()` → 4 JVM + 5 of 6 connected RED;
  justifying the scroll MD heading → `c1` alone RED;
  making phase-1 pagination alignment-sensitive → the JVM invariance test and `d1`
  alone RED.
