---
branch: feat/feature-64-wi-5-uikit-presenter
threadId: 019e408e-f83a-7550-88d1-e65aa6548c45
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-5 (UIKitHighlightPopoverPresenter test suite)

## Scope

WI-5 of the unified cross-format highlight-action popover. **Test-only WI** — `UIKitHighlightPopoverPresenter` itself shipped in WI-4 (PR #971) for compile-order reasons (the WI-4 modifier could not compile without the concrete presenter); the plan §5 assigned "UIKit anchored-card presenter" to WI-5, so WI-5's deliverable is the dedicated test suite the plan §6 mandates.

- `vreaderTests/Views/Reader/UIKitHighlightPopoverPresenterTests.swift` (NEW) — 8 tests.
- The pbxproj regen registering the file. No production code changed.

## Round 1 — Codex `019e408e-f83a-7550-88d1-e65aa6548c45`

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `UIKitHighlightPopoverPresenterTests.swift:117` | Medium | The same-`content.id` idempotence test used a *detached* `UIView`, so `presentCard` exited at the `nearestViewController` guard before reaching `.presenting` — the `presentCard` same-id fast-path was never exercised. Effectively a second idle-`updateCard` no-op test. | Drive a real presented state via a hosted `UIWindow` + root VC. |
| F2 | `UIKitHighlightPopoverPresenterTests.swift:5` | Medium | The scope-note header overstated the limitation ("the process lacks a live hierarchy") — the test target is app-hosted and the repo already uses temporary `UIWindow` fixtures. | Reword honestly; add a hosted-window test for the present path. |
| F3 | `UIKitHighlightPopoverPresenterTests.swift:58` | Low | `dismissCard_noCompletion_nothingPresented_doesNotCrash` was vacuous (`#expect(Bool(true))`). | Strengthen or fold into an observable assertion. |
| F4 | `UIKitHighlightPopoverPresenterTests.swift:75` | Low | `updateCard_nothingPresented_isNoOp` likewise proved no postcondition. | Assert an observable idle-state invariant. |

The auditor confirmed in round 1: the detached-view fallback test IS a genuine pipeline exercise; the suite is deterministic (no sleeps); deferring the full supersede path is defensible *as a scoping choice*; calling WI-5 a test-only WI is defensible.

## Resolution

The suite was rewritten with a `makeHostedAnchor()` helper building a real `UIWindow` + root `UIViewController` hosting the anchor `UIView`:

- **F1** — `presentCard_sameContentID_isIdempotent_keepsSameHostingController` now drives a real present, captures `root.presentedViewController`, issues a second `presentCard` for the SAME id, and asserts `root.presentedViewController === firstHost` — genuinely exercising the `presentCard` same-id fast-path. Added `presentCard_hostedAnchor_presentsAHostingController`, `updateCard_whilePresented_keepsSameHostingController`, and `dismissCard_whilePresented_runsCompletionAfterDismissal` (waits on a `CheckedContinuation` resumed from the real modal-dismiss completion — not a sleep — and asserts `presentedViewController == nil` after).
- **F2** — the scope-note header rewritten: it now states the app-hosted target lets the suite build a real `UIWindow` and exercise the *presented*-state contracts, listing exactly what it covers.
- **F3** — the vacuous test deleted.
- **F4** — `updateCard_nothingPresented_isNoOp_pipelineStaysIdle` now asserts an observable postcondition: a follow-up `dismissCard(completion:)` drains synchronously. The detached-view test similarly asserts pipeline reusability.

8 tests pass.

## Round 2 — Codex `019e408e-f83a-7550-88d1-e65aa6548c45` (re-audit of the fixes)

Verdict: **"Confirmed: the two prior Medium findings and two prior Low findings are resolved."** Codex verified the hosted-window helper, the genuine same-`content.id` fast-path exercise, the accurate scope note, the removal of the vacuous `#expect(Bool(true))` tests, and the meaningful presented-state dismiss-completion coverage without sleeps. **No remaining open Critical/High/Medium findings.**

## Verdict

**ship-as-is** — 2 rounds (round 1 found 2 Medium + 2 Low, all test-quality — the suite over-relied on detached-view branches and had vacuous assertions; round 2 clean after a rewrite to real hosted-window present/dismiss/update assertions).
