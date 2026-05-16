---
branch: feat/feature-60-wi-7c1-popover-presenter
threadId: 019e2ea9-1b3f-7be3-aed7-ee205015a30f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7c1 SelectionPopoverPresenter

## Round 1 — 1 Medium + 1 Low

### Medium — deferred-action dismissal silently swallows taps
- **`vreader/Views/Reader/SelectionPopoverPresenter.swift:115`** | Medium
  `onAction` cleared `pending` unconditionally after calling
  `SelectionPopoverActionRouter.route(...)`. Fine for dispatched
  actions, but `.askAI` and `.read` currently return
  `.deferredNotYetWired` (no production pipeline yet). Once
  WI-7c2..7c5 swap production bridges over, those buttons would
  silently do nothing and still dismiss the sheet.

**Fix applied**: extracted `SelectionPopoverDismissPolicy.nextPending(after:currentSelection:)` as a pure-logic `@MainActor enum` helper, swapped `onAction` to use it. `.dispatched` returns `nil` (sheet dismisses); `.deferredNotYetWired` returns the same `currentSelection` (sheet stays open until the pipeline lands). Added 4 new tests in a new `SelectionPopoverDismissPolicyTests` suite pinning the contract. Required adding `: Equatable, Sendable` to `TextSelectionInfo` (was a bare struct) — non-breaking additive conformance.

### Low — docs/architecture.md notification bus drift
- **`docs/architecture.md:163`** | Low
  PR adds `.readerSelectionPopoverRequested` + presenter modifier
  but the Notification Bus table doesn't document them. Rule 24
  requires docs sync when component communication changes.

**Fix applied**: added a row after `.readerHighlightRequested` with payload, direction, and a sentence on what the presenter does.

## Round 2 — clean

Codex verified: "No findings. The two fixes are correct as
implemented. `TextSelectionInfo: Equatable, Sendable` is a clean
additive conformance ... the dismiss policy is now explicit and
safe ... the exhaustive `switch` in SelectionPopoverPresenter.swift
means any future `SelectionPopoverActionRouter.Result` case will
force a compile-time review instead of silently picking the wrong
behavior."

## Verdict statement

**ship-as-is** after round 1 (1 Medium + 1 Low → both fixed). Round 2 clean.

All 8 audit dimensions clean:
1. Correctness vs the plan — WI-7c1 delivers exactly what plan v8 promises: notification contract, typed request helper, presenter modifier, dismiss policy. No production bridge wiring (deferred to WI-7c2..7c5).
2. Edge cases — handled: invalid payload (`selection(from:)` returns nil), latest-event-wins (`pending` overwrite), iOS-driven dismissal (drag-down / tap-outside via isPresented set-side), deferred actions (dismiss policy keeps sheet open).
3. Security — clean: pure SwiftUI + NotificationCenter, no JS interop.
4. Duplicate code — none; intentionally mirrors `FoliateSpikeView+Selection.swift` shape without forcing a premature abstraction.
5. Dead code — none.
6. Shortcuts / patches — none.
7. VReader compliance — clean: `@MainActor` on the enums + modifier, Swift 6 strict concurrency satisfied, file sizes well under 300 lines.
8. Bridge safety — `TextSelectionInfo` now `Sendable` (additive); parse helper rejects wrong shapes; dismiss policy exhaustive over router Result.

## Test results

- 6 `SelectionPopoverPresenterTests` (notification name, parse round-trip, parse tolerance, post round-trip, empty-text post)
- 4 `SelectionPopoverDismissPolicyTests` (dispatched dismisses, dispatched-any-name, deferred .askAI keeps open, deferred .read keeps open)
- Total: 10/10 pass

## Strengths called out by Codex

- WI-7c1 matches the plan split cleanly: notification contract + typed request helper + presentation modifier without prematurely touching production bridges.
- Lifecycle is simple and safe: rapid repeated notifications overwrite `pending` (latest selection wins); sheet dismissal clears state; `.onReceive` doesn't create observer leaks.
- Security surface clean.
- The exhaustive `switch` on `Result` means any future router-enum case will force a compile-time review.
- Keeping the dismiss policy keyed off router `Result` rather than action enum cases is the right abstraction boundary.
- Additive `Sendable` conformance improves the type's hygiene for Swift 6 without widening scope.
- Contract tests are high-value: they pin the wire format without dragging SwiftUI presentation into brittle unit tests.
