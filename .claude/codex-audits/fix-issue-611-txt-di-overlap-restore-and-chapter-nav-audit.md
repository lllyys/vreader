---
branch: fix/issue-611-txt-di-overlap-restore-and-chapter-nav
threadId: 019e2893-21c0-7c80-9627-af7ae5b56c1a
rounds: 3
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit — Bug #179 (GH #611) — TXT reading content obscured by Dynamic Island on saved-position restore + chapter-nav paths

## Context

This is the SECOND attempt at fixing Bug #179. The first attempt (prior bugfix-cron iteration on 2026-05-15) tried to subtract/add `textContainerInset.top` inside `TXTTextViewBridgeCoordinator.attemptScrollRestore`. Codex thread `019e2743` rejected that approach as mathematically wrong: `contentOffset.y = lineY` is already correct when `textContainerInset.top` correctly includes the safe-area inset. The prior iteration documented the next hypothesis as "investigate next iteration: `contentInsetAdjustmentBehavior` interaction, `safeAreaInsets` stacking, post-call contentOffset race, save/restore asymmetry."

This iteration's diagnosis: the **GeometryReader-vs-makeUIView timing race** is the real root cause. `proxy.safeAreaInsets.top` returns 0 momentarily on initial render (before SwiftUI measures) and across the chapter-nav rebuild gap (when `chapterAttrString = nil` swaps to `loadingView` then back). During that window, the bridge's first `makeUIView` sets `textContainerInset.top = base(16) + 0 = 16` instead of `16 + ~59 = 75`. The 0.15s-delayed `attemptScrollRestore` then runs against a textView whose `textContainerInset.top = 16`, and `setContentOffset(y: lineY)` lands the restored glyph at viewport-y = 16 — behind the Dynamic Island.

The scroll math stays correct (per `019e2743`'s analysis). Only the inset feed needs to survive the race.

## Round 1 — initial audit

**Diagnosis confirmed**: "The root-cause diagnosis is mostly right: the scroll math still looks correct, and the failure mode is consistent with `attemptScrollRestore` combined with an under-reported top inset. You also did not miss any TXT/MD call sites; the only other `proxy.safeAreaInsets.top` bridge handoff is EPUB, which you intentionally left out."

**Findings** (2 Medium):

| # | severity | file:line | issue | fix |
|---|---|---|---|---|
| 1 | Medium | `ReaderSafeAreaResolver.swift:27` | `windowSafeAreaTop` only looks at `.foregroundActive` scenes with `isKeyWindow`. During the exact warmup window this fix targets, the scene can be `.foregroundInactive` and the window may not be `isKeyWindow` — `topInsetWithFallback(0)` collapses to 0, defeating the fallback. | Broaden activation states to active+inactive, walk every window in matching scenes, and cache the last-known nonzero value as a final fallback. |
| 2 | Medium | `ReaderSafeAreaResolver.swift:27` | Resolver is global, not window-local. In Stage Manager / multi-window cases another scene can win and contribute the wrong top inset. Restore is one-shot in `makeUIView`, so a wrong inset is permanent for that session. | Walk all windows in foreground scenes and take max. (Window-local resolution from `textView.window` not feasible at `makeUIView` time — view isn't attached yet.) |

**Resolution**: both fixed in the same commit. `windowSafeAreaTop` now walks `.foregroundActive` first, then `.foregroundInactive` only when no active scene exists. Within each pass, every window in every matching scene is probed and the max `safeAreaInsets.top` is taken. A `lastKnownNonZeroTop` `@MainActor` cache seeds correct behaviour once any prior call observes a positive value (also seeded opportunistically when `topInsetWithFallback(_:)` sees a positive geometry value while the window probe was empty). Pure-function seam `combine(_:_:)` extracted for testability; 10-case Swift Testing suite added at `vreaderTests/Views/Reader/ReaderSafeAreaResolverTests.swift` covering both-zero, geom-only, window-only, both-equal, geom-larger, window-larger, negative-geom-clamps, negative-window-clamps, both-negative, iPad-landscape. All 10 pass.

## Round 2 — re-audit after fix

**Findings** (1 Medium):

| # | severity | file:line | issue | fix |
|---|---|---|---|---|
| 3 | Medium | `ReaderSafeAreaResolver.swift:50` | The active-then-inactive fallback is still wrong for the multi-window case: if any `.foregroundActive` scene exists with real top inset 0 (landscape iPad / Stage Manager), falling through to `.foregroundInactive` can pull a stale `59` from a paused window and over-inset the active reader. Treating "active pass found only zeros" the same as "no active scene exists" is the bug. | Distinguish those cases. If at least one `.foregroundActive` scene exists, return its max top inset even when 0; only consult `.foregroundInactive` when no active scene exists at all. Cache remains the final fallback. |

**Resolution**: restructured to `active ? activeMax : (inactive ? inactiveMax-or-cache : cache)`. Active-scene presence is authoritative — its value wins even when 0. `.foregroundInactive` is consulted only when no active scene exists at all; an inactive-pass zero falls through to the cache (interpreted as "warmup window where the device hasn't reported its safe area yet") rather than fabricating a real zero-state.

## Round 3 — final audit

**Findings**: none.

**Verdict**: **ship-as-is**.

Codex notes one residual risk: "first ever restore call sees geometry 0, no active scene, inactive scenes also 0, and cache unseeded" — possible only when every signal fails simultaneously before the 0.15s-delayed restore fires. Codex classifies as residual risk, not a review finding. `updateUIView` re-applies `textContainerInset` whenever the bridge struct's `safeAreaTopInset` changes, so any subsequent SwiftUI render after the initial measurement can still fix it.

## Files changed

- `vreader/Views/Reader/ReaderSafeAreaResolver.swift` (new, ~90 lines)
- `vreader/Views/Reader/TXTReaderContainerView.swift` (3 call sites: `readerContent`, `chapterReaderContent`, `chunkedReaderContent`)
- `vreader/Views/Reader/MDReaderContainerView.swift` (1 call site: `readerContent`)
- `vreaderTests/Views/Reader/ReaderSafeAreaResolverTests.swift` (new, 10 tests)

## Out of scope

- `attemptScrollRestore` / `scrollToMatchedOffset` math — unchanged. Prior verdict that `contentOffset.y = lineY` is correct stands.
- `TXTTextViewBridge.combinedTextInset` — unchanged.
- `TXTChunkedReaderBridge.makeUIView` — unchanged.
- EPUB bridge (line 330 of `EPUBReaderContainerView.swift`) — same pattern but bug #163 was fixed via a different WKWebView-specific path. User-reported repro is TXT-only.
- A UI / bridge-level regression harness that exercises reopen + chapter-nav restore under a nonzero safe area — Codex recommended this in round 1 ("this bug lives at the SwiftUI/UIView/window seam"). Filed as a follow-up: vreader's test layer doesn't currently have such a harness. Pure-function coverage of `combine(_:_:)` is the test floor; device verification is the test ceiling.
