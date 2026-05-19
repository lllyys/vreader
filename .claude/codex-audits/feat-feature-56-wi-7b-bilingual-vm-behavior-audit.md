---
branch: feat/feature-56-wi-7b-bilingual-vm-behavior
threadId: 019e41e1-dedd-7e82-a0d3-13b4f6630574
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Implementation Audit — feature #56 WI-7b

`BilingualReadingViewModel` behavioral layer: the unit-aware translation
prefetch trigger (`ChapterPrefetching` seam, `handlePositionChange`,
epoch/cancellation, offline silent-source-fallback, `.readerBilingualDidChange`).

## Files audited

- `vreader/Services/AI/ChapterPrefetching.swift`
- `vreader/ViewModels/BilingualReadingViewModel.swift`
- `vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift`
- `vreader/Views/Reader/ReaderNotifications.swift` (the new `.readerBilingualDidChange`)
- `vreaderTests/ViewModels/BilingualReadingViewModelBehaviorTests.swift`

## Round 1 — findings

Zero Critical. 1 High + 2 Medium + 2 Low — all genuine.

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `+Prefetch.swift` `handlePositionChange` | High | Stale-launch race: between `epoch += 1` and the `await unit(after:)` suspension a disable could occur; the resumed (stale) invocation started superseded-epoch prefetches. | **Fixed round 1 (partial)** — resolved `unit(after:)` before mutating epoch + re-checked `isEnabled` after the suspension. Round 2 found this incomplete (see below). |
| `+Prefetch.swift` `finishPrefetch` | Medium | A transient (`.failed`/`.cancelled`) outcome left `lastTriggerUnit` set, so a later position change *inside the same unit* was deduped away — the unit only retried after the reader left and re-entered it. | **Fixed** — `finishPrefetch` clears `lastTriggerUnit` when a transient outcome names the unit it points at. Test `transientFailure_retriesOnNextPositionChangeInSameUnit`. |
| `BilingualReadingViewModel.swift` / `+Prefetch.swift` `prefetchTasks` | Medium | `prefetchTasks` (a `[Task]`) grew unbounded — completed tasks were never removed — and `awaitPrefetchForTesting` could not reliably drain cancelled tasks. | **Fixed** — `prefetchTasks` is now `[TranslationUnitID: Task]`; `finishPrefetch` removes the completed entry (epoch-guarded). |
| `BilingualReadingViewModelBehaviorTests.swift` | Low | Missing the failure-edge tests (retry-in-same-unit, the stale-launch race) and an empty-book (`unit(containing:) == nil`) test. | **Fixed** — added `transientFailure_retriesOnNextPositionChangeInSameUnit`, `emptyBook_positionChangeIsNoOp`, `disableDuringUnitAfterSuspension_doesNotStartStalePrefetch`. |
| `BilingualReadingViewModel.swift` WI-7b stored state | Low | The split-file approach leaves WI-7b internals as module-`internal` stored properties (the `+Prefetch.swift` extension writes them; Swift `private` is file-scoped), widening the type surface. | **Accepted with rationale** — a `PrefetchState` holder would re-touch every access site across both files for a cosmetic gain on a `final class`; the properties are only ever touched by the type's own two files. Documented in the main file's header. Codex accepted this rationale in rounds 2 and 3. |

## Round 2 — findings

The round-1 High fix was incomplete. 1 High + 1 Low.

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `+Prefetch.swift` `handlePositionChange` | High | The post-suspension re-check `currentUnit != lastTriggerUnit` did NOT defeat a concurrent later unit-change to a *different* unit: call A resolves ch0 + suspends; call B resolves ch2 + sets `lastTriggerUnit = ch2`; A resumes — `ch0 != ch2` passes the guard, A cancels B's prefetches and starts stale ch0 prefetches. | **Fixed** — added a monotonic per-call `triggerRequestSeq` token captured at entry and re-checked after BOTH suspensions. Only the latest request proceeds, regardless of which unit each request named. Regression test `interleavedPositionChanges_laterUnitWins_notTheStaleOlderOne`. |
| `+Prefetch.swift` `awaitPrefetchForTesting` | Low | The test helper could return before cancelled-and-removed tasks finished unwinding. | **Fixed** — `cancelInFlightPrefetches` preserves cancelled tasks in `cancelledPrefetchTasks`; `awaitPrefetchForTesting` drains both active and cancelled snapshots, looping while either is non-empty. |

## Round 3 — verification

Both round-2 findings verified resolved. Zero remaining Critical/High/Medium/Low.
Codex re-confirmed acceptance of the round-1 Low #5 rationale.

## Verdict

**ship-as-is** — Gate 4 clean after 3 rounds. The WI-7b suite is 19 tests, all
passing on iPhone 17 Pro Simulator (iOS 26.5). Codex confirmed everything else
sound against the live codebase: the current+next prefetch on a real unit
change, the offline miss recorded as source-only, `.readerBilingualDidChange`
posting, the referenced symbols, and MainActor-confined state mutation (no data
race).
