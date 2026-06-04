---
branch: feat/feature-91-wi-6b-search-other
threadId: 019e9176-12fc-76b2-9b76-f9919e679e79
rounds: 3
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-6b (search_other_books)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

Behavioral WI-6b — library-wide agentic search (the Gate-2-flagged index-coverage
risk):

- `vreader/Services/AI/Tools/LibraryBookSearchGate.swift` (new) — the PURE
  persistent-index safety gate (`LibraryBookSearchGate.evaluate`) + the
  `LibrarySearchBackend` seam + `LibraryIndexState` / `LibrarySearchEligibility` /
  `LibrarySearchExclusion`. Mirrors `ReaderSearchCoordinator.setup`'s full guard
  set (isBookIndexed AND not requiresReindex AND non-nil TXT/MD offsets).
- `vreader/Services/AI/Tools/SearchOtherBooksTool.swift` (new) — `struct
  SearchOtherBooksTool: AITool`; orchestration: list → drop open book → gate →
  restore TXT/MD offsets → per-book FTS search → coverage-reported result. Never
  throws; per-book failure is skipped.
- `vreader/Services/AI/Tools/ToolResultText.swift` (new) — shared `oneLine`/`clamp`
  extracted from WI-6a's SearchCurrentBookTool (which was migrated to use it).
- `vreader/Services/AI/Tools/SearchCurrentBookTool.swift` (modified) — delegates
  to `ToolResultText` (behavior preserved).
- Tests: `LibraryBookSearchGateTests` (7, exhaustive gate matrix),
  `SearchOtherBooksToolTests` (21).

Key design fact the auditor confirmed: `SearchService.search` queries the FTS
store directly (no in-memory marking required), so `markPersistentlyIndexed` is
correctly omitted; the gate only restores TXT/MD offsets (without which the
hit→locator resolver drops the result).

## Round 1 — findings (threadId 019e9176-12fc-76b2-9b76-f9919e679e79)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| SearchOtherBooksTool.swift gate call | **High** | The gate was driven by `book.format` (a stale-prone parallel String column — the Bug #246 class), not the canonical `DocumentFingerprint.format` parsed from the fingerprint key. A drifted row could be mis-gated (real TXT/MD included without offset restore → dropped results; real EPUB/PDF wrongly excluded as staleOffsets). | **Fixed.** The gate is now called with `fingerprint.format.rawValue` (the canonical format from the key). Regression test `gatesOnCanonicalFormatNotColumn` pins BOTH directions (canonical-TXT with column lying "epub" → restored; canonical-EPUB with column lying "txt" + nil offsets → searched, not excluded). |
| SearchOtherBooksToolTests.swift | **Medium** | The "restores TXT offsets first" test didn't prove ORDERING (separate restored/searched lists). | **Fixed.** The stub records an ordered `events` log; the TXT test asserts `firstIndex("restore:kB") < firstIndex("search:kB")`. |
| SearchOtherBooksTool.swift footer | Low | The coverage footer said "not indexed or need re-indexing" but `excludedCount` also spans staleOffsets + malformed keys. | **Fixed.** Footer now reads "not indexed, need re-indexing, or unreadable metadata". |

`ToolResultText` extraction confirmed behavior-preserving; no Swift 6
sendability/isolation issue; `markPersistentlyIndexed` omission confirmed safe.

## Round 2 — verification (threadId 019e918c-e94b-7f83-836b-4510c81ea974)

Findings 1–3 **RESOLVED**. One **new Medium**: `searchedCount` was derived from
`toSearch.count` (books *attempted*), so a skipped per-book search failure
overstated coverage ("No matches in N books" while some of those N failed).
**Fixed.** The loop counts `searchFailures` separately; `format` computes
`completedCount = attempted - failed`, reports the completed count (or "Couldn't
search N book(s) — the search failed." when all failed), and adds a "N book(s)
failed to search" coverage line. Tests `eligibleButNoHits`, `allSearchesFailed`,
and an assertion in `perBookFailureSkipped` pin it.

## Round 3 — verification (threadId 019e91a2-046d-7940-88da-9f493c1d3936)

The round-2 Medium **RESOLVED**. One **new Medium**: the coverage footer was
appended last and then byte-clamped, so a large hit set could truncate the
coverage signal away (misleading partial coverage). **Fixed.** `format` now builds
the footer first and reserves its bytes — only the BODY is clamped (to
`maxContentBytes - footerBytes`), then the footer is appended, so coverage always
survives. Test `coverageSurvivesTruncation` pins it (large hit set, 400-byte
budget → body shows `…(truncated)` AND the coverage line is present).

## Round-cap decision (rule 47: max 3 rounds)

This is round 3, the documented cap. The round-3 finding was fixed rather than
escalated because (a) convergence was monotonic — each round surfaced one
distinct, accepted, cleanly-fixable issue (High → Medium → Medium), never a
re-litigation of a prior fix; (b) the round-3 fix is mechanical (reorder + reserve
footer bytes) and directly test-pinned. Per the cap, the round-3 fix was applied
WITHOUT a 4th audit round; its correctness rests on `coverageSurvivesTruncation`.
A post-fix test bug (a `'g'/'h'` non-hex char in the truncation test's
fingerprint keys crashed `DocumentFingerprint(canonicalKey:)!`) was caught by the
test gate and fixed (hex-digit keys); not a production finding.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. Test gate green:
`LibraryBookSearchGateTests` (7 — full guard matrix: not-indexed, TXT/MD
reindex/nil-offsets/good, EPUB/PDF) + `SearchOtherBooksToolTests` (21 — open-book
exclusion, canonical-format gating both directions, restore-before-search
ordering, excluded/failed/capped coverage, truncation-survival, missing-query /
list-throw → isError) + `SearchCurrentBookToolTests` (10, refactor regression).
