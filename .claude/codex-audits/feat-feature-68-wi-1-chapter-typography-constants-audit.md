---
branch: feat/feature-68-wi-1-chapter-typography-constants
threadId: 019e3d9f-5f46-7242-892e-f963c49632b2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Feature #68 (reader chapter-start typography) Gate-4 audit for WI-1 — the
foundational shared-constants slice. Two new files:

- `vreader/Services/ChapterStartTypography.swift` — stateless `enum`
  namespace holding the design-pinned constants (drop-cap 2.6x scale,
  0.85 line-height, heading 13pt / 2pt tracking / 18pt-after / 8pt-before,
  `.medium` / `.semibold` weights, `2.6em` CSS size) plus the pure
  `isDropCapEligible(_:)` predicate.
- `vreaderTests/Services/ChapterStartTypographyTests.swift` — 31 tests.

## Round 1 findings

- **High** — `isDropCapEligible` used a broad `properties.isAlphabetic`
  acceptance; the audit brief said "Latin letters only".
- **Medium** — the CJK exclusion set was incomplete (missed Hangul
  Compatibility Jamo, Katakana Phonetic Extensions, halfwidth Katakana,
  supplementary-plane kana blocks).
- **Medium** — tests pinned only the plan §6 cases; did not lock the
  full Unicode contract.

## Resolution

- **High** — checked the plan: §4.1's docstring ("letter/number … CJK
  ideographs excluded") and Risk R4 pin exactly one script-class
  exclusion (CJK). The plan does NOT mandate Latin-only — Cyrillic/Greek
  books should still get a drop-cap and the Georgia serif fallback
  renders those scripts. Kept the broad alphabetic acceptance, added an
  explicit scope note in the docstring, added positive tests for Greek
  (Ω) / Cyrillic (Ж) / accented Latin (É). The round-2 auditor confirmed
  this is the correct plan interpretation.
- **Medium (CJK)** — `isCJKKanaOrHangul` now covers Hangul Jamo +
  Compatibility Jamo + Extended-A/B, Hiragana, Katakana + Phonetic
  Extensions, Bopomofo + Extended, Halfwidth Katakana/Hangul, and the
  supplementary-plane Kana Extended-B / Supplement / Extended-A / Small
  Kana Extension blocks. Combined with `properties.isIdeographic` the
  full Unicode range (BMP + supplementary) is closed.
- **Medium (tests)** — added negative cases for Hiragana, Katakana,
  Hangul syllable, Hangul Compatibility Jamo, Bopomofo, Halfwidth
  Katakana, supplementary-plane Kana Supplement (U+1B001) and
  supplementary-plane CJK Extension B ideograph (U+20000).

## Round 2 verdict

No remaining Critical/High/Medium findings. The enum is stateless,
UIKit-gated, under the line budget, free of actor-isolation issues; the
tests do real spec pinning. **ship-as-is.**
