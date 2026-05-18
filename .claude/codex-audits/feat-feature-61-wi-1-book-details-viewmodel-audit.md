---
branch: feat/feature-61-wi-1-book-details-viewmodel
threadId: 019e3ab8-c339-7262-ab65-1c649bb2a924
rounds: 3
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex Gate-4 Audit — feature #61 WI-1 (Book Details sheet — BookDetailsViewModel)

Foundational WI: a testable value-type view model (`BookDetailsViewModel`)
mapping `LibraryBookItem` → display-ready strings, plus a new
`LibraryBookItem.totalPageCount` DTO field and its `PersistenceActor`
projection wiring. No user-observable behavior (no view yet — that is WI-3).

Changed files:
- `vreader/Views/Reader/BookDetails/BookDetailsViewModel.swift` (new)
- `vreaderTests/Views/Reader/BookDetails/BookDetailsViewModelTests.swift` (new)
- `vreader/Models/LibraryBookItem.swift` (modified — `totalPageCount: Int?` field + init param)
- `vreader/Services/PersistenceActor+Library.swift` (modified — `fetchAllLibraryBooks` projection)

## Round 1 — initial audit (2 Medium)

> Round-1 ran on an earlier Codex thread whose full id was lost when the
> session context was compacted (recorded only as the prefix `019e3a14`).
> Round 2 re-audited the full WI-1 diff on a fresh thread
> (`019e3ab8-c339-7262-ab65-1c649bb2a924`) and independently confirmed
> the round-1 fixes — so the audit chain is intact.

| # | file:line | severity | issue | fix |
|---|---|---|---|---|
| 1 | BookDetailsViewModel.swift:46 | Medium | `pagesDisplay = book.totalPageCount.map(String.init)` rendered `"0"` for `totalPageCount == 0`; the plan requires the Pages row omitted unless the count is `> 0`. | Changed to `book.totalPageCount.flatMap { $0 > 0 ? String($0) : nil }`; `pagesDisplay` doc comment updated to state zero/negative is treated as absent. |
| 2 | BookDetailsViewModelTests.swift | Medium | No test asserted `pagesDisplay == nil` for `totalPageCount == 0`. | Added `pagesDisplayNilWhenCountZero()`. |

Resolution: both **fixed**.

## Round 2 — re-audit of the fixed diff (1 Medium)

| # | file:line | severity | issue | fix |
|---|---|---|---|---|
| 3 | BookDetailsViewModelTests.swift:77 | Medium | The `pagesDisplay` doc comment documents negative-count suppression and the code guards `> 0`, but the suite only pinned `312` / `nil` / `0` — a regression to `>= 0` would still pass. | Added `pagesDisplayNilWhenCountNegative()` (`totalPageCount: -1` → `pagesDisplay == nil`). |

Round 2 also confirmed the round-1 fixes are correct and complete, and
found no new correctness, back-compat, dead-code, or Swift 6 concurrency
issues. `LibraryBookItem` remains `Sendable`; the new `totalPageCount`
init parameter defaults to `nil` so all pre-existing call sites compile
unchanged; all four files are under the ~300-line guideline.

Resolution: **fixed**.

## Round 3 — verification

Codex confirmed verbatim: "Feature #61 WI-1 is clean. I do not have any
remaining audit findings for this slice." The `pagesDisplay` contract is
now pinned for all four branches: positive → `"312"`, `nil` → `nil`,
zero → `nil`, negative → `nil`.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium/Low findings after 3 rounds.

## Test gate note

WI-1's targeted gate is green: `xcodebuild test` of
`BookDetailsViewModelTests` + `LibraryBookItemTests` +
`LibraryBookItemFileStateTests` passed (32 tests), and a follow-up run of
`BookDetailsViewModelTests` after the round-2 fix passed (17 tests),
including all four `pagesDisplay` cases.

The full `-only-testing:vreaderTests` suite could not produce a clean run
— three consecutive attempts hit a pre-existing flaky test-host crash in
the backup/restore (`SelectiveRestoreCoordinator`) area, unrelated to this
diff (WI-1 is pure value types and cannot crash a test host; every
post-restart re-run reported 720/720 tests passing with zero assertion
failures). That flake is filed as **Bug #221 (GH #849)**. WI-1's
correctness is fully established by the targeted gate above.
