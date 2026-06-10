---
branch: fix/issue-1568-round4-gesture-deferral
threadId: 019eb2e0-3ad6-7cb0-a038-a5ad5a7d00ea
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Gate-4 Codex audit — Bug #329 round 4 (gesture-aware mutation deferral, GH #1568)

Adversarially briefed ("fixed three times and reopened each time — be
maximally skeptical"). 2 rounds (round-2 session 019eb2eb-e548-7041-af14-ba0f4a38c3e0).

## Round 1 — "Not clean"

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollJS.swift:239 | High | Single `fingerDown` boolean — a second finger on glass while the first lifts arms settle and re-opens the mid-gesture compensation class. | **Fixed** — `fingerCount` from `event.touches.length` on touchstart/touchend/touchcancel; settle arms only at 0. JSC regression `multiTouch_secondFingerKeepsWindowOpen`. |
| EPUBContinuousScrollCoordinator.swift:481 | Medium | Deferred evictions + unbounded appends → no cap on in-gesture DOM growth. | **Fixed** — `touchGrowthCeilingSlack = 3`: past `maxSpan + 3` the forward append pauses too for the gesture's remainder (brief boundary stall, never a teleport); settle drains. |
| EvictionGuardTests.swift:224 | Medium | No EXECUTABLE settle-machine coverage — "exactly how rounds 1–3 missed the real gesture bug". | **Fixed** — `EPUBContinuousScrollObserverJSTests`: the PRODUCTION observer JS runs unmodified in JavaScriptCore over stubbed DOM / fake timers / rAF / postMessage. Cases: momentum re-arm, re-touch during settle, multi-touch hold/release, queued resize-delta flush at settle, immediate compensation outside a gesture, bridge `touchActive` parse. The harness's fake setTimeout ids start at 1 (browser parity — the production truthiness check ignores falsy ids). |

Round 1 also confirmed the single-touch settle logic coherent (pre-touchend
scrolls don't arm; post-touchend scrolls re-arm; touchstart cancels).

## Round 2 — CLEAN, ship-as-is

Verified all three fixes; the JSC harness "materially faithful for this bug
class" with no further mismatch; the ceiling's interplay with the
dual-boundary same-signal return + echo suppression sound (eviction path →
`ignoreNextNearTop` return; no-eviction path → independent `touchActive`
deferral).

## Device evidence (the round-4 re-close bar: REAL gestures, user-class book)

`scripts/b329-gesture-probe.sh` + a passive scroll-event recorder on
道诡异仙 (19.4MB, 1042 spines), same workload pre/post (20 forward pans +
12 reversal cycles):

| build | teleports (>200px) | content leaps | forward regressions |
|---|---|---|---|
| baseline (v3.62.16) | 77 | 43 | 0 |
| touch-only gate | 32 | 22 | 0 |
| + settle window (shipped) | **0** | **0** | **0** (4524 events) |

All 5 continuous-scroll unit suites green (1px sim unchanged — rounds 1–3
behavior preserved). Analysis: `dev-docs/verification/bug-329-r4-analysis-20260611.md`.

## Verdict

**ship-as-is** after 2 rounds.
