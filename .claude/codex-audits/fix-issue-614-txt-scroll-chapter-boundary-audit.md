---
branch: fix/issue-614-txt-scroll-chapter-boundary
threadId: 019e2923-42ed-7a43-ad58-357ce12e14e9
rounds: 2
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Bug #180 (GH #614) — TXT scroll mode cross-chapter navigation

## Round 1 findings

| # | File | Severity | Finding | Resolution |
|---|---|---|---|---|
| 1 | `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift:279-287` | Medium | `boundarySlack = 0.5` creates overlapping top/bottom zones when `0 < contentSize.height - bounds.height < 0.5`. Because bottom is checked first, a settle at `offset == 0` on a near-fit chapter is classified as "bottom" and advances instead of rewinding/no-op. The viewport-overflow guard only covered `contentSize <= bounds`, not tiny positive overflow from layout rounding. | Required `maxOffset > 2 * boundarySlack` before applying slack zones. Near-fit chapters (sub-1pt overflow) now fire neither boundary. Added regression test `decelerateOnNearFitChapterAtOffsetZeroFiresNeitherBoundary` covering `contentSize 852.4 vs bounds 852`. |
| 2 | `vreader/ViewModels/TXTReaderViewModel.swift:153-154, 352-382, 637-644` | Medium | Boundary callbacks launch untracked `Task`s into `nextChapter()` / `previousChapter()` with no in-flight navigation guard. Rapid repeated settles/bounces at the boundary before `loadChapter` returns can start concurrent chapter loads for the same target and duplicate `broadcastPosition` / preload work. | Added `private var isChapterNavInFlight: Bool` on TXTReaderViewModel (@MainActor); `navigateToChapter` early-returns if true, sets it after bounds-check, resets via `defer`. Because the VM is @MainActor and the flag-set runs BEFORE the first `await`, queued reentrant Tasks see `true` and drop. Protects both boundary-fired and chrome-button-driven nav paths. |
| 3 | `vreaderTests/Views/Reader/TXTScrollBoundaryChapterNavTests.swift:82-100` | Low | Test comment said it covered "chapter-restore landing at offset 0", but the bridge only sets `suppressScrollCallbacks` during restore when `restoreOffset > 0`. Test actually validates the coordinator guard itself. | Reworded the comment to describe what the unit test actually proves: coordinator-level guard against any programmatic scroll, not the offset-0 restore path specifically. |

## Round 2 verdict

Codex confirmed all 3 findings closed correctly. Zero new findings. Verdict: **ship-as-is**.

## Test gate

`xcodebuild test -only-testing:vreaderTests/TXTScrollBoundaryChapterNavTests` — 7 tests in 1 suite, all passing (0.005s).

Full `vreaderTests` suite: 2 pre-existing failures in `BookFormatAZW3Tests` (`azw3 supports tts` + `azw3 capabilities match EPUB simple capabilities`) — these reproduce on a fresh `main` checkout and relate to Bug #176 (`awaiting-device-verification`). NOT introduced by this fix.

## Pre-FIXED verify (TDD discipline)

The 7-test suite includes `decelerateAtBottomFiresBottomBoundaryCallback`, `decelerateAtTopFiresTopBoundaryCallback`, and `endDraggingWithoutDecelerateAtBottomFiresBottomBoundary` — these would FAIL on the pre-fix code (the protocol didn't have the new methods + the coordinator didn't call them). Confirmed RED→GREEN transition during implementation.

Real-environment slice verification (live simulator with a chaptered TXT) is deferred to the post-merge `awaiting-device-verification` close-gate per the project's bug-fix workflow.
