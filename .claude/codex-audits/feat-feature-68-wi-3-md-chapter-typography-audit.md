---
branch: feat/feature-68-wi-3-md-chapter-typography
threadId: 019e3dec-fe9e-75a2-a5b7-8ecf2000e096
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Feature #68 (reader chapter-start typography) Gate-4 audit for WI-3 — MD
chapter-start drop-cap + leading-heading restyle + `MDRenderConfig`
plumbing. Changed files:

- `vreader/Services/MD/MDChapterStartDecorator.swift` (NEW) — leading-
  heading restyle + drop-cap application.
- `vreader/Services/MD/MDChapterStartScanner.swift` (NEW) — locates the
  drop-cap target (first PLAIN body paragraph + its eligible initial);
  block-type detection from run attributes. Split from the decorator so
  both files stay under the ~300-line cap.
- `vreader/Services/MD/MDTypes.swift` — `MDRenderConfig` gets
  `accentColor` + `chapterHeadingColor` + `==` update.
- `vreader/Services/MD/MDFileLoader.swift` — `load` gains `renderConfig`,
  drops the hardcoded `MDRenderConfig.default`.
- `vreader/ViewModels/MDReaderViewModel.swift` — `open` gains
  `renderConfig`, forwards it, runs `MDChapterStartDecorator.decorate`.
- `vreader/Views/Reader/MDReaderContainerView.swift` — `viewModel.open`
  passes `settingsStore?.mdRenderConfig ?? .default`.
- `vreader/Services/ReaderSettingsStore.swift` — `mdRenderConfig` threads
  the V2 accent + sub tokens.
- 4 new/extended test files + `MockMDParser.swift` (records
  `lastParsedConfig`).

## Round 1 findings

- **High** — `MDChapterStartScanner` did not exclude heading blocks. A
  heading is rendered as plain bold text with no distinctive run
  attribute, so `# H1\n\n## H2\n\nBody` mis-drop-capped the `## H2` line
  instead of `Body`; also broke the multi-heading "headings-only" case.
- **Low** — the WI-3 tests missed the heading-then-heading regression and
  under-covered the MD leading-quote and MD surrogate-pair cases.

## Resolution

- **High** — `firstPlainParagraphDropCap` now takes a
  `headingOffsets: Set<Int>` and rejects any `paragraphStart` matching a
  heading's `charOffsetUTF16` before plain-paragraph classification.
  `decorate` computes the set from its `headings` parameter and threads
  it through `applyDropCap` into the scanner. Both leading and
  non-leading headings are now excluded from the drop-cap scan.
- **Low** — added `dropCapSkipsSecondHeading`, `multiHeadingOnlyDocument`,
  `dropCapAfterLeadingQuote` (U+201C), and `dropCapSupplementaryPlaneInitial`
  (U+10400) tests.

## Round 2 verdict

No remaining Critical/High/Medium findings. The config-plumbing seam is
correct (`MDReaderContainerView` → `MDReaderViewModel.open` →
`MDFileLoader.load` → `parser.parse`, no hardcoded `.default`); the core
invariant holds (`decorate` adds attributes only, `renderedText` stays
the byte-identical undecorated string); concurrency/isolation sound; the
TXT/MD `firstDropCapScalar` duplication is acceptable per plan §3.2.
**ship-as-is.**
