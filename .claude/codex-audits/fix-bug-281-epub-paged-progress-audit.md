---
branch: fix/bug-281-epub-paged-progress
threadId: codex-exec-local
rounds: 3
final_verdict: ship-as-is
date: 2026-05-30
---

# Gate-4 Codex Audit — Bug #281 (GH #1258): EPUB paged-layout page turns

Independent audit via `codex exec --sandbox read-only` (cc-suite / Codex CLI),
author/auditor separated (Codex process distinct from the implementing Claude
session). Three rounds. The diff audited each round was `git diff origin/main`
(origin/main == this branch's true fork base, the Bug #279 merge `e3a2797c`).

## Scope

Both defects of bug #281:
1. Within-chapter paged turns never updated reading progress / progress bar /
   persisted location (vertical-scroll-only `onProgressChange` producer; paged
   turns only change horizontal `scrollLeft`).
2. No swipe-to-turn (side-tap was the only page-turn input) — vs the working
   AZW3/Foliate paged reader which turns on swipe and reports relocate-per-turn.

Files audited: `EPUBPagedProgress.swift`, `EPUBSwipeGestureClassifier.swift`,
`EPUBPaginationHelper.swift` (pagedSwipeTrackingJS), `EPUBWebViewBridge.swift`,
`EPUBWebViewBridgeCoordinator.swift` (handlePagedSwipeMessage),
`EPUBWebViewBridgeJS.swift` (contentTapTrackingJS swipe-consume),
`EPUBReaderContainerView+ChapterWrap.swift` (recordPagedProgress),
`EPUBReaderContainerView.swift` (chapter-wrap landing).

## Round 1 — 3 findings (all fixed)

| file:line | severity | issue | fix |
|---|---|---|---|
| EPUBPaginationHelper.swift (pagedSwipeTrackingJS) | Medium | JS marked `__vreaderSwipeConsumedTap` at `abs(dx) > 10` but Swift only turns at `> 50`; an 11-49px horizontal jitter swallowed the following synthetic click WITHOUT turning, so a genuine side-tap / chrome-tap felt dropped. | JS now uses `SWIPE_PX = 50` interpolated from `EPUBSwipeGestureClassifier.defaultThreshold`, with the same `|dx|>SWIPE_PX && |dx|>|dy|` dominance test, so the consume flag is set ONLY for gestures Swift will turn on. Regression test `swipeJS_consumeThresholdMatchesClassifier`. |
| EPUBWebViewBridgeJS.swift (contentTapTrackingJS) | Medium | The anchor (`<a>`) early-return ran BEFORE the swipe-consume check, so a swipe ending on a link could (a) activate the link and (b) strand the flag → swallow the next genuine non-link tap. | Moved the consume check ABOVE the anchor guard; it now `e.preventDefault()` + `e.stopPropagation()` and clears the flag for any consumed click (link or not). |
| EPUBPaginationHelper.swift (pagedSwipeTrackingJS) | Low | No `touchcancel` / timeout cleanup — a consumed swipe that produced no synthetic click stranded the flag. | `touchcancel` resets gesture state; the consume flag self-expires via `setTimeout(clearConsumed, 700)`. Tests `swipeJS_handlesTouchCancel`, `swipeJS_autoExpiresConsumeFlag`. |

## Round 2 — 1 finding (fixed). M1/M2/Low verified resolved.

| file:line | severity | issue | fix |
|---|---|---|---|
| EPUBPaginationHelper.swift (pagedSwipeTrackingJS) | Low | The self-expiry `setTimeout` wasn't owned per swipe: a stale timer from an earlier swipe could fire during a later rapid swipe and clear that swipe's consume flag before its synthetic click landed (reopening the double-advance / link-activation path). | Timer id stored in `window.__vreaderSwipeExpireTimer`; the swipe JS `clearTimeout`s any pending timer before scheduling a new one, and the click handler `clearTimeout`s + nulls it when it consumes the flag. |

## Round 3 — 1 finding, accepted (max rounds reached). All prior fixes verified.

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBPaginationHelper.swift (pagedSwipeTrackingJS) | Low | The consume state is a single boolean; two rapid qualifying swipes whose synthetic clicks are both delayed could misattribute click #1 to swipe #2's flag/timer, letting click #2 fall through as a side-tap (one extra page-turn). | **Accepted with rationale.** Requires two full >50px horizontal swipes completed faster than WebKit's synthetic-click latency (typically a few ms after touchend) — physically near-impossible for a human. Worst case is a single self-correcting one-page over-advance (no crash, no data loss, no link mis-activation since the click handler still `preventDefault`s any consumed click). The proposed token-queue fix adds ordering machinery whose own correctness is harder to reason about; introducing it at round 3 risks a regression with worse expected value than the accepted edge. Logged here as a known limitation; a follow-up may adopt a per-swipe token queue if rapid-swipe double-advance is ever observed on device. Codex's other verifications were clean: @MainActor routing consistent, JS is fixed app-authored interpolation only (no injection surface), handler registration/teardown symmetric, new files under size limit. |

## Final verdict

ship-as-is. All Critical/High/Medium findings fixed and re-verified across 3
rounds. The single remaining Low is explicitly accepted with rationale (benign,
self-correcting, near-impossible trigger) per the rule-47 Gate-4 "Low findings
fixed or explicitly accepted" clause at max audit rounds. Codex's round-3
verbatim verdict was "follow-up-recommended" solely on that accepted Low; the
implementing decision records it as a known limitation rather than a blocker, so
the shippable verdict is ship-as-is with a documented Low.

## Test gate

Full `vreaderTests` suite: 7625 tests in 748 suites — PASS (iPhone 17 Pro
Simulator, UDID 61149F0E-DC18-4BE2-BB37-52659F1F4F62, derivedDataPath
/tmp/dd-bug281). New seam tests: `EPUBPagedProgressTests` (intra-chapter +
whole-book composition), `EPUBSwipeGestureClassifierTests` (classify +
pagedSwipeTrackingJS text contracts).
