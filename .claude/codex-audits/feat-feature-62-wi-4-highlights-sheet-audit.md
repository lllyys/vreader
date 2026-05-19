---
branch: feat/feature-62-wi-4-highlights-sheet
threadId: 019e40c2-12b7-7333-95e7-1903233fad68
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit — feature #62 WI-4

`HighlightsSheet` — the review sheet (unified card stream) of the
annotations-panel split.

## Files audited

- `vreader/Views/Reader/Annotations/HighlightAnnotationCard.swift` (new)
- `vreader/Views/Reader/Annotations/HighlightsSheet.swift` (new)
- `vreader/Views/Reader/Annotations/HighlightsSheet+Support.swift` (new)
- `vreader/Views/Reader/Annotations/HighlightsSheet+Export.swift` (new)
- `vreaderTests/Views/Reader/Annotations/HighlightAnnotationCardTests.swift` (new)
- `vreaderTests/Views/Reader/Annotations/HighlightsSheetTests.swift` (new)

## Round 1 — findings

| # | file:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | HighlightsSheet+Support.swift `metaLabel` | Medium | `metaLabel` rendered `p. N` only and returned `""` for EPUB/TXT — every non-PDF card lost the chapter context the `HighlightsSheetV3` design shows. | **Fixed** — `HighlightsSheet` now takes a `tocEntries` param; `metaLabel` composes `chapter · p. N` via `chapterTitle(for:)` (the same last-at-or-before matching `TOCSheet` uses); each component degrades. Tests `metaLabelResolvesChapter` + `metaLabelDegradesWithoutTOC`. |
| 2 | HighlightsSheetTests.swift retained-import test | Medium | The retained-import regression test passed a bogus URL — it bailed at `Data(contentsOf:)` before ever constructing `AnnotationImporter`, so the "compiled + tested for #963" constraint was unguarded. | **Fixed** — the test now builds a valid export JSON via `AnnotationExporter`, writes it to a temp file, drives `importForTesting(url:)`, asserts the status reports "Imported", AND fetches highlights/annotations from persistence — definitive proof `importJSON` ran end-to-end. |
| 3 | HighlightsSheet.swift export share sheet | Low | The export `ShareActivityView` lacked `.ignoresSafeArea()` — the legacy `AnnotationsPanelView` had it; not a byte-for-byte move. | **Fixed** — `.ignoresSafeArea()` restored. |

No Critical or High findings.

## Round 2 — verification

Codex re-read all three fixes against the worktree: "No Critical, High, or
Medium findings remain. I'd treat Gate 4 for these files as pass." The
chapter-resolving `metaLabel`, the real end-to-end retained-import test,
and the restored `.ignoresSafeArea()` all confirmed correct.

## Engine regression guards (plan §4 / §5)

The export flow moved verbatim from `AnnotationsPanelView`; the engines
are untouched. The named must-stay-green guards were run:

- `AnnotationExporterTests` — pass.
- `AnnotationImporterTests` — pass.

(22 tests across the two engine suites.)

## Verdict

**ship-as-is.** Two audit rounds. Round 1: 2 Medium + 1 Low. Round 2: all
three fixed and confirmed. Zero open Critical/High/Medium. 26 tests pass in
the two WI-4 suites + 22 engine-guard tests.
