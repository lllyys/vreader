---
branch: feat/feature-61-wi-2-cover-pick-coordinator
threadId: 019e3ade-167a-7431-bd78-eb9bd3e80549
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex Gate-4 Audit — feature #61 WI-2 (CoverPickCoordinator extraction)

Foundational WI: a **behavior-preserving extraction**. The library
custom-cover replace flow (PhotosPicker presentation + `CustomCoverStore`
persist + a `coverVersion` refresh counter) is pulled out of
`LibraryView` / `LibraryViewSheets` into a reusable `@Observable
@MainActor CoverPickCoordinator`, so the reader Book Details sheet
(feature #61 WI-4) can drive the same flow.

Changed files:
- `vreader/Views/Shared/CoverPickCoordinator.swift` (new — coordinator + `CoverPickerModifier` + `.coverPicker(_:)`)
- `vreaderTests/Views/Shared/CoverPickCoordinatorTests.swift` (new — Swift Testing suite)
- `vreader/Views/LibraryView.swift` (modified — 4 cover `@State` vars → one `@State CoverPickCoordinator`)
- `vreader/Views/Library/LibraryViewSheets.swift` (modified — dropped 4 cover `@Binding`s + inline `.photosPicker`; attaches `.coverPicker`)
- `vreader/Views/Library/LibraryView+Body.swift` (modified — Set/Remove Cover + `coverVersion` reads route through the coordinator)

## Round 1 (1 High + 1 Medium)

| # | file:line | severity | issue | fix |
|---|---|---|---|---|
| 1 | CoverPickCoordinator.swift (`pickedItem` handler) | High | The extracted handler did not snapshot the target `book` before the async `Task`. The pre-extraction code captured `book` in its `guard` and saved against that snapshot; the new path only checked `bookForCover != nil` then re-read `bookForCover` at save time — a rapid re-present could redirect an in-flight image onto the wrong book. | `applyCover` changed to take an explicit `for book:` parameter (no `bookForCover` re-read); `CoverPickerModifier` snapshots `let book = coordinator.bookForCover` before spawning the `Task`. |
| 2 | CoverPickCoordinatorTests.swift | Medium | The suite tested only synchronous helpers; the target-book snapshot / retarget contract was unguarded — which is why finding 1 was uncaught. | Added `applyCoverTargetsTheGivenBookNotCurrentState()` — presents a book, retargets to a second, applies for the first, asserts the cover landed on the first and not the second. |

Resolution: both **fixed**. Codex confirmed the `do/catch + log.error` change
(replacing the inline `try?` silent swallow, per rule 50 §6) is
behavior-equivalent, the grid/list/Continue-reading refresh path stays
wired, the removed `PhotosUI` imports were cleaned up, and the Swift 6
`@Observable @MainActor` isolation is sound.

## Round 2 — verification

Codex confirmed verbatim: "No findings. ... feature #61 WI-2 is clean
from this Gate-4 audit." The retargeting bug is resolved (explicit-book
save + pre-Task snapshot) and the test gap is closed.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium/Low findings after 2 rounds.

## Test gate

Targeted `xcodebuild test` (iPhone 17 Pro): `CoverPickCoordinatorTests` +
`CoverLifecycleTests` + `CustomCoverStoreTests` (the latter two are the
plan's named behavior-preservation regression guards) — **25 tests, 3
suites, passed**. The full `-only-testing:vreaderTests` suite is blocked
by the pre-existing flaky test-host crash filed as Bug #221 (GH #849),
unrelated to this diff; WI-2's correctness is established by the targeted
gate above.

## Note — parallel-execution incident

While WI-2 was in flight, a concurrent feature-#66 worktree subagent's
shell `cd` resolved to the main checkout instead of its worktree and it
committed two #66 commits onto this WI-2 branch. Detected via
`git log origin/main..HEAD`, the two commits + #66's six files were
purged (`git reset --mixed origin/main` + targeted `checkout`/`rm` +
`xcodegen`), and the branch verified to contain only WI-2 files. #66's
complete work is intact on its own origin branch
(`feat/feature-66-reader-settings-subcontrol-reskin`).
