---
branch: feat/feature-85-wi-1-scroll-reroute-v3
threadId: 019e95b8-7520-7832-9723-3ac5008134b6
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #85 WI-1 (seamless Readium EPUB scroll, approach C)

Codex `gpt-5.4` / high, read-only. Author = claude (implementer); auditor =
Codex (separate context) — rule-48 separation held.

WI-1 routes EPUB **scroll** mode to the legacy #71 continuous-scroll stitch
(Readium keeps **paged**), with a cross-engine position bridge. Changed source:
`ReaderEngine.swift` (layout-aware router), `ReaderContainerView.swift`
(dispatcher + DEBUG-probe routing + `epubEvalUsesReadiumEngine` helper),
`ReaderPositionHandoff.swift` (NEW in-memory handoff cache),
`EPUBScrollAnchorResolver.swift` (NEW container↔OPF href resolver),
`EPUBReaderContainerView.swift` (legacy handoff restore + record),
`ReadiumEPUBHost.swift` (+`pendingCrossEngineRestore`), `ReadiumEPUBHost+Body.swift`
(cross-engine restore-after-open + record).

## Round 1 — session `019e95b1-5f14-7fc2-8bfc-87f5a60394b5` → block-recommended

| file | severity | issue | resolution |
|---|---|---|---|
| ReadiumEPUBHost+Body onLocationChange | High | The cross-engine restore SAVED the transient book-start locator before the one-shot navigate; a dismiss-before-navigate (or a navigate that never relocates) would `closeAndFlush` book-start over the scroll position. | **Fixed** — the cross-engine navigate now runs at the TOP of `onLocationChange`, BEFORE `viewModel.save`, and `return`s on a successful navigate (skipping the transient-start save/record/downstream). A failed conversion falls through to a best-effort save. So start can no longer be persisted over the real position; the navigate's own relocate persists it. |
| EPUBReaderContainerView buildContinuousScrollConfig | High | The legacy host used the handoff locator only to seed the window/fraction, not `viewModel.currentPosition`; a quick close before the first `onWindowedPosition` callback would persist the stale disk position (cross-launch loss). | **Fixed** — `buildContinuousScrollConfig` now calls `viewModel.updatePosition(EPUBPosition(...from the handoff...))` BEFORE mounting, so a quick close persists the handoff-backed position. |
| ReaderContainerView DEBUG probe | Medium | `readiumActive` was captured once at probe setup; a live paged↔scroll toggle left the probe targeting the old engine. | **Fixed** — `epubEvalUsesReadiumEngine(store:)` is now static and called INSIDE `probe.jsEvaluator` at call time (capturing `store`), so the eval routing re-targets live. |

## Round 2 — session `019e95b8-7520-7832-9723-3ac5008134b6` → ship-as-is

> All 3 prior findings are resolved; no remaining or new Critical/High/Medium
> findings in the scoped diff.

## Verdict

**ship-as-is.** The earlier (v1/v2) attempts surfaced the load-bearing
cross-engine position-handoff requirements (position LOSS on toggle, the wrong
spine-href source for the Readium fallback, the racy unawaited save); v3
implements them correctly — a synchronous in-memory handoff, a post-open
one-shot Readium navigate via `publication.readingOrder`, and the legacy
container↔OPF anchor resolver — and the two round-1 persistence-edge Highs +
the probe Medium are fixed. Test gate green (44 unit tests across the handoff,
resolver, router, and dispatch suites). The seam-removal + bidirectional
position-continuity VISUAL is the feature's Gate-5b on-device acceptance
(after WI-2 highlights + WI-3).
