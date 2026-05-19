---
branch: feat/feature-68-wi-2-txt-chapter-typography
threadId: 019e3dc3-489c-78a1-9f70-764b6b9f3132
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Feature #68 (reader chapter-start typography) Gate-4 audit for WI-2 — TXT
chapter-start drop-cap + regex-heading restyle. Changed files:

- `vreader/Services/TXT/TXTChapterStartDecorator.swift` (NEW) — the
  drop-cap + heading restyle logic; extracted so the builder stays under
  the ~300-line cap.
- `vreader/Services/TXT/TXTAttributedStringBuilder.swift` — adds
  `buildChapterStart` / `buildChapterStartSendable` delegating to the
  decorator.
- `vreader/Views/Reader/TXTViewConfig.swift` — `accentColor` +
  `chapterHeadingColor` fields, `renderingEquals` update.
- `vreader/Services/ReaderSettingsStore.swift` — `txtViewConfig` threads
  the V2 accent + sub tokens.
- `vreader/Views/Reader/TXTReaderContainerView.swift` — `makeAttrStringKey`
  hashes the new colors + heading length; the `.task` chapter branch
  calls `buildChapterStart`.
- `vreader/ViewModels/TXTReaderViewModel.swift` —
  `currentChapterHeadingLineLength` + the pure `nonisolated`
  `headingLineLength(chapterText:chapterTitle:)` static helper.
- 4 new test files (47 tests total).

## Round 1 findings

- **Medium** — `headingLineLength` overflow was clamped to `nsText.length`,
  which restyled the whole body as a heading. Plan §4.2 says overflow =
  "treated as no heading".
- **Low** — `firstDropCapIndex` unconditionally skipped lead surrogates
  and hardcoded the cap range to length 1, contradicting the shared
  `isDropCapEligible` predicate which accepts supplementary-plane letters.
- **Low** — the integration test file was mislabeled; it called the pure
  functions directly rather than driving the container `.task`.

## Resolution

- **Medium** — `TXTChapterStartDecorator.decorate` now coerces
  `headingLineLength` to 0 when `> nsText.length` or `<= 0`. Overflow /
  negative inputs become drop-cap-only. Two tests pin this.
- **Low (surrogate)** — `firstDropCapIndex` → `firstDropCapScalar`:
  reconstructs the supplementary-plane scalar from the surrogate pair,
  tests `isDropCapEligible` on the real scalar, returns
  `(index, utf16Length)` with `utf16Length == 2` for non-BMP. The cap
  range now covers the whole glyph. New Deseret-letter (U+10400) test.
- **Low (label)** — integration file reframed as "composition" coverage;
  the purpose comment + `@Suite` name + scope note now honestly describe
  it as exercising the real `headingLineLength` → `buildChapterStart`
  data flow (the container `.task` itself is XCUITest / Gate-5
  territory). Misleading "navigateToChapter" wording corrected.

## Round 2 verdict

No remaining Critical/High/Medium findings. The core invariant holds:
`buildChapterStart` adds attributes only, backing string + UTF-16 length
unchanged, the legacy `build` path untouched, concurrency/isolation
sound. **ship-as-is.**
