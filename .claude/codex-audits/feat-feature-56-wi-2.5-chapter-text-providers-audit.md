---
branch: feat/feature-56-wi-2.5-chapter-text-providers
threadId: 019e41cd-6191-7471-bc59-5eca1e3c4737
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Implementation Audit — feature #56 WI-2.5

`ChapterTextProviding` boundary protocol + 4 concrete per-format adapters
(`EPUBChapterTextProvider`, `TXTChapterTextProvider`, `MDChapterTextProvider`,
`PDFChapterTextProvider`) for bilingual reading. Foundational WI.

## Files audited

- `vreader/Services/Reader/ChapterTextProviding.swift`
- `vreader/Services/Reader/EPUBChapterTextProvider.swift`
- `vreader/Services/Reader/TXTChapterTextProvider.swift`
- `vreader/Services/Reader/MDChapterTextProvider.swift`
- `vreader/Services/Reader/PDFChapterTextProvider.swift`
- `vreaderTests/Services/Reader/ChapterTextProviderTests.swift`
- `vreaderTests/Services/EPUB/EPUBReaderViewModelTests.swift` (new `setSpineContent` helper)

## Round 1 — findings

Zero Critical / High. Three Medium + one Low — all genuine.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `PDFChapterTextProvider.swift` `unit(containing:)` | Medium | Returned `nil` for any `page` past the last unit; the boundary contract (plan Decision 2.6) requires a past-end position to clamp to the last unit (TXT/MD already clamp). | **Fixed** — clamps a page past `pageRanges().last.upperBound` to the last range; a negative page still returns `nil`. |
| `TXTChapterTextProvider.swift` `unit(containing:)` | Medium | A negative `charOffsetUTF16` resolved to unit 0 because the scan seeded `match = chapters[0]`; per the contract a locator that predates the book's first unit must resolve to `nil`. | **Fixed** — three-state offset handling: `nil` → unit 0, negative → `nil`, non-negative → scan. |
| `MDChapterTextProvider.swift` `unit(containing:)` | Medium | Same contract violation as TXT — negative offset resolved to unit 0. | **Fixed** — mirrored the TXT three-state fix. |
| `ChapterTextProviderTests.swift` | Low | Suite did not cover the contract edges that the Medium findings exposed (pre-book TXT/MD locators, past-end PDF clamp, malformed/inverted PDF range strings, Unicode/CJK UTF-16 slicing); the header comment overstated `unit(containing:)` coverage. | **Fixed** — added `txtUnitContainingReturnsNilForNegativeOffset`, `txtUnitContainingNilOffsetResolvesToFirstUnit`, `txtSourceTextSlicesCJKByUTF16Bounds`, `mdUnitContainingReturnsNilForNegativeOffset`, `mdUnitContainingClampsPastEndToLastUnit`, `pdfUnitContainingClampsPastEndToLastUnit`, `pdfUnitContainingReturnsNilForNegativePage`, `pdfSourceTextForMalformedRangeStringThrows`; corrected the header comment. Suite is now 37 tests. |

Codex also confirmed everything else sound: the referenced live symbols
(`EPUBParserProtocol.contentForSpineItem`, `EPUBTextExtractor.stripHTML`,
`EPUBSpineItem`, `TXTChapter` UTF-16 fields, `MDHeading.charOffsetUTF16`,
`PDFKit`, `Locator` fields) exist and are used correctly; EPUB units are spine
documents per plan Decision 2.7; the `Sendable` story holds under Swift 6
strict concurrency; repeated `PDFDocument(url:)` opens are safe in the
nonisolated value-type adapter; file sizes within the repo rule.

## Round 2 — verification

All three Medium findings + the Low finding verified resolved. Zero remaining
Critical / High / Medium. No new issue introduced by the fixes.

## Verdict

**ship-as-is** — Gate 4 clean after 2 rounds. All 37 `ChapterTextProviderTests`
pass on iPhone 17 Pro Simulator (iOS 26.5).
