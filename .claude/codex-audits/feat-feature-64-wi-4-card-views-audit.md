---
branch: feat/feature-64-wi-4-card-views
threadId: 019e407f-e49d-7ec0-966a-f3e83c7cae97
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-4 (SwiftUI card+sheet views + modifier + Foliate JS bridge)

## Scope

WI-4 of the unified cross-format highlight-action popover — the largest WI. 8 new production files + 1 modified:

- `FoliateHighlightJSBridge.swift` (NEW) — pure-logic Foliate recolor/delete notification poster.
- `HighlightActionCardSubviews.swift` (NEW) — shared subviews + the `HighlightPopoverSwatch` color mapper.
- `HighlightPopoverDeleteConfirm.swift` (NEW) — the inline delete-confirm subview (split for the 300-line guideline).
- `HighlightActionCardView.swift` (NEW) — the SwiftUI view (card + sheet shells, the 3 note modes, the controlled `HighlightNoteDraftEditor`).
- `HighlightPopoverActionRouter.swift` (NEW) — `@MainActor @Observable` state + dispatch core.
- `HighlightPopoverModifier.swift` (NEW) — the `HighlightPopoverPresenting` protocol, parse helper, share types.
- `HighlightPopoverModifierBody.swift` (NEW) — the `HighlightPopoverModifier` `ViewModifier` + attach helpers.
- `UIKitHighlightPopoverPresenter.swift` (NEW) — the `UIPopoverPresentationController`-based presenter (serialized pipeline; idempotent in-place `updateCard`).
- `HighlightCoordinator.swift` (MOD) — the `HighlightMutating` protocol + `deleteHighlight` + the conformance.

Plus 3 new test files (`FoliateHighlightJSBridgeTests`, `HighlightPopoverActionRouterTests`, `HighlightActionCardViewTests`).

## Round 1 — Codex `019e407f-e49d-7ec0-966a-f3e83c7cae97`

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `HighlightPopoverActionRouter.swift:114` + `HighlightPopoverModifierBody.swift:111` | **High** | `share` set the share item immediately after `dismiss()`, while the card was dismissed with no completion — reintroducing the modal-collision feature #55 guarded against. R2-F7 not fully satisfied on the card path. | Stage share presentation behind a real dismiss completion. |
| F2 | `HighlightCoordinator.swift:246` + `HighlightPopoverActionRouter.swift:152` | Medium | `confirmDelete` / `deleteHighlight` collapsed every failure into `false`, so a concurrent-deletion race (`recordNotFound`) left the popover open over a record that no longer exists — inconsistent with the typed recolor/save handling. | Make `deleteHighlight` return a typed `HighlightMutationOutcome`; dismiss on `.notFound`. |
| F3 | `HighlightPopoverModifierBody.swift:84/117` + `UIKitHighlightPopoverPresenter.swift:121` | Low | (a) `resolvedForm` recomputes from persisted `content.note`, not the live `noteDraft` — an anchored card never degrades to the sheet mid-edit. (b) `pressedColor` was never threaded through `presentCard`/`updateCard` — the card lost the design's transient swatch press feedback. | (a) reroute on the live draft; (b) thread `pressedColor`. |

The auditor confirmed everything else structurally sound in round 1: the Foliate bridge posts the right notifications/keys in the right order, the non-`.epub` skip is safe, `@MainActor` coverage is correct, R2-F6's same-`content.id` in-place `rootView` update is implemented the right way.

## Resolution

- **F1 (High)** — the router's `route(.share)` now records `pendingShareText` (not a share item) + clears `content`. The modifier's `routePresentation()` nil-branch calls a new `tearDownSurfaces(then:)` that dismisses whichever surface is up and runs the completion from the surface's REAL dismissal (sheet → `.sheet`'s `onDismiss` via a stashed `pendingPostSheetDismiss`; card → `dismissCard(completion:)`). The modifier-owned `@State shareItem` is set only inside that completion — so the `UIActivityViewController` is presented strictly after the popover has fully dismissed.
- **F2 (Medium)** — `HighlightCoordinator.deleteHighlight` now returns `HighlightMutationOutcome`: a fetch throw → `.failed`, no matching record → `.notFound`, `removeHighlight` throwing `recordNotFound` → `.notFound`, generic → `.failed`, success → `.success(record)`. The `HighlightMutating` protocol's signature changed to match. The router's `handleConfirmDelete` dismisses on `.success`/`.notFound`, stays open (→ reading) only on `.failed`. New tests: 3 coordinator-level + 2 router-level.
- **F3a (Low)** — accepted, NOT changed, with rationale: re-routing card→sheet mid-edit would tear down the anchored card while the keyboard is up — a worse UX than a presentation-stable form. The form is decided once at present time from the stored note; the next tap re-decides. Plan known-limitation L2 already accepts the card-vs-sheet axis as fidelity, not correctness.
- **F3b (Low)** — fixed: `presentCard` / `updateCard` now take a `pressedColor` parameter; the UIKit presenter threads it into `HighlightActionCardView`; the modifier's `syncLiveCard` runs on `onChange(of: router.pressedColor)`.

51 tests pass across the 3 WI-4 suites + `HighlightCoordinatorMutationTests` + `HighlightCoordinatorTests`.

## Round 2 — Codex `019e407f-e49d-7ec0-966a-f3e83c7cae97` (re-audit of the fixes)

Verdict: **"Confirmed."** Codex verified: the High is resolved (share now waits for a real dismissal completion); the Medium is resolved (`deleteHighlight` typed, the router dismisses on `.success`/`.notFound`); the pressedColor Low is fixed (threaded through the protocol + UIKit presenter); and accepting the live-draft form-selection Low with the stated rationale is "reasonable — a documented fidelity limitation rather than a correctness defect". **No remaining open Critical/High/Medium findings.**

## Verdict

**ship-as-is** — 2 rounds (round 1 found 1 High + 1 Medium + 1 Low; the High share-modal-collision + Medium delete-typing fixed, the pressedColor Low fixed, the live-draft-form Low accepted with rationale; round 2 clean).
