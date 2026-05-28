---
branch: feat/feature-71-wi-4-scroll-coordinator
threadId: 019e6449-4225-7643-bd3b-8b985867001b
rounds: 3
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Feature #71 WI-4: EPUBContinuousScrollCoordinator

WI-4 of feature #71 (EPUB continuous cross-chapter scroll): the `@MainActor`
host-side coordinator that turns the JS scroll observer's boundary signals into
`EPUBSpineWindow` transitions — materializing the adjacent chapter, emitting
append/prepend section JS through an async-throwing evaluator, and (only after a
successful eval) advancing the window + evicting far chapters. WI-1/2/3 (window,
rewriter, JS generators) are merged; WI-5 (live bridge) is next. WI-4 is the
decision logic, unit-tested with a recording stub evaluator + stub provider.

Files:
- `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` (new — coordinator + `EPUBScrollBoundarySignal`)
- `vreader/Views/Reader/EPUBSpineWindow.swift` (added `reanchored(to:)` + `span`)
- `vreaderTests/Views/Reader/EPUBContinuousScrollCoordinatorTests.swift` (new — 12 tests)
- `vreaderTests/Views/Reader/EPUBSpineWindowTests.swift` (reanchored tests)

## Round 1 findings

| # | severity | issue | resolution |
|---|---|---|---|
| H1 | High | Generation-token discard not carried through the eviction phase — a stale task could emit remove JS + publish its window over a rebuilt generation. | **Fixed.** `window` assigned ONCE at the end, gen-guarded; gen re-checked before each eviction remove eval. |
| M4 | Medium | Window shrank even when a remove eval threw (window claims a chapter trimmed while the DOM still holds it). | **Fixed.** Incremental eviction (see M5) advances the committed window only on a successful remove. |
| M3 | Medium | `nearTop && nearBottom` both-true: forward always won (`if/else if`); a short chapter could starve one side. | **Fixed.** Two sequential `if`s — both sides extend. Test `nearTopAndBottom_extendsBothSides`. |
| L2 | Low | No defensive check that the provider returned the requested `spineIndex` (DOM/window desync risk). | **Fixed.** `guard body.spineIndex == targetIndex` aborts on mismatch. Test `providerReturnsWrongSpineIndex_abortsExtend_noEval`. |

## Round 2 finding

| # | severity | issue | resolution |
|---|---|---|---|
| M5 | Medium | The first M4 fix (`window = extended` on any remove failure) was only correct for the single-drop case; a multi-drop partial failure (after a prior remove failure left the window wide) could re-claim an already-removed chapter. | **Fixed.** Eviction is now INCREMENTAL — trim exactly one farthest chapter per step via `evictFarFromAnchor(maxSpan: committed.span - 1)`, advancing `committed` only on a successful remove; `break` on failure leaves `committed` reflecting exactly the sections actually removed. |

## Round 3 — **No findings. Ship as-is.** Codex confirmed the incremental loop
terminates (span strictly decreases per successful step), `committed` always
matches the DOM under partial failure, the one-step trim + `singleDroppedIndex`
are correct, and every await-driven side effect is gen-fenced (after provider,
after insert, before each remove, once before the single race-free `window =
committed` publish).

## Verification (Gate 5a — Behavioral, logic-only)

WI-4 is "Behavioral (logic unit-testable with stub evaluator; no live WKWebView
yet)" per the plan. Verified by 35 unit tests (12 coordinator + 23 EPUBSpineWindow
incl. `reanchored`): forward/backward extend, first/last no-op, partial-eval
failure (window not advanced), stale-generation (during provider AND during
eviction), single-in-flight idempotency, dual-boundary, provider-mismatch abort,
eviction emits remove JS. The live-WKWebView slice verification is WI-5/WI-6.

## Verdict

**ship-as-is** — the window-transition decision logic is correct, race-safe on
`@MainActor`, and DOM-consistent under every failure/cancellation path the plan's
WI-4 contract enumerates.
