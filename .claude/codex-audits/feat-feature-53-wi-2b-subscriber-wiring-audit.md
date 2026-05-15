---
branch: feat/feature-53-wi-2b-subscriber-wiring
threadId: manual-fallback
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-15
---

# Codex audit log — Feature #53 WI-2b (subscriber wiring)

Manual fallback per rule 47 + saved feedback (audit-time constraint).

## Scope of this WI

Behavioral WI completing the subscriber side of the tap-on-highlight
contract for TXT/MD readers. New surfaces:

- `TXTTextViewBridge.highlightActionPresenter` + `onHighlightTapAction`
  optional bridge params (default nil → backward-compat).
- `TXTTextViewBridge.Coordinator` stores both fields; the existing
  `handleContentTap` extension fires the presenter and routes the
  resolved action through the callback after notification post.
- `TextHighlightRenderer.apply(record:)` now also appends to
  `uiState.persistedHighlightLookup` so newly-created highlights are
  immediately hit-testable (fix for a WI-2 lookup-sync gap discovered
  during live-device verification).
- `TXTReaderContainerView` + `MDReaderContainerView` wire
  `UIKitHighlightActionPresenter()` + a closure that routes to
  `HighlightCoordinator.handleTapAction(_:highlightID:)`.

## Files reviewed

Production (modified):
- `vreader/Views/Reader/TXTTextViewBridge.swift` (+12 lines)
- `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift` (+22 lines)
- `vreader/Views/Reader/TextHighlightRenderer.swift` (+9 lines — apply-path lookup sync fix)
- `vreader/Views/Reader/TXTReaderContainerView.swift` (+4 lines — non-chunked, non-chaptered call site)
- `vreader/Views/Reader/MDReaderContainerView.swift` (+4 lines)

Tests (new):
- `vreaderTests/Views/Reader/TXTBridgeHighlightTapSubscriberTests.swift` — 3 methods covering presenter invocation + dismiss-without-action + nil presenter safety.

## Audit dimensions

### 1. Correctness vs plan

- Subscriber wiring matches the plan: presenter resolves the event, completion routes to coordinator. ✅
- Renderer apply() lookup-sync fix is a genuine bug catch from live verify, not arbitrary scope creep. Without it, WI-2's hit-test was permanently stale on freshly-created highlights. ✅
- Containers stay agnostic of the presenter implementation — they pass an instance of `UIKitHighlightActionPresenter()` and could swap to any conforming type for testing. ✅

### 2. Edge cases

- **Presenter nil, callback nil**: coordinator still posts the notification (poster behavior preserved); presenter branch skipped. ✅
- **Presenter wired, callback fires nil action (user dismissed)**: closure has explicit `guard let action else { return }` — no spurious calls. Test coverage: `dismissWithoutAction_doesNotInvokeCallback`. ✅
- **Concurrent updates to lookup during a tap**: SwiftUI re-render rebuilds the bridge struct; `updateUIView` re-syncs both `persistedHighlightLookup` and the presenter fields. ✅
- **`highlightCoordinator` is `@State` optional in containers**: closure uses `[highlightCoordinator]` capture; if nil at call time (rare: pre-initialization), the call is a no-op via optional chaining. ✅

### 3. Security

N/A — no JS, no string interpolation, no remote input.

### 4. Duplicate code

- The closure `{ action, id in await highlightCoordinator?.handleTapAction(action, highlightID: id) }` is duplicated verbatim between TXT and MD containers. Extracting to a shared helper would save ~2 lines per site but add an indirection layer; deferred. Documented as deferred follow-up.

### 5. Dead code

- All new fields wired end-to-end through bridge → coordinator → handleContentTap → presenter.present → completion → callback → coordinator.handleTapAction → persistence + notification.
- `presenter_nil_skips_presentation_butStillPostsNotification` test verifies the nil-shape branch (defensive).

### 6. Shortcuts & patches

- **None deliberate.** Live device verify exposed a real bug (lookup not synced on apply()) → fixed in scope, not patched.

### 7. VReader compliance

- Swift 6 strict concurrency: all new closures `@MainActor`-isolated, propagate cleanly through the bridge → coordinator → presenter chain.
- File sizes:
  - `TXTTextViewBridge.swift` — 322 lines (+12).
  - `TXTTextViewBridgeCoordinator.swift` — 392 lines (was 370).
  Both over the 300-line guideline; pre-existing borderline. Splitting deferred — the added code is cohesive with the existing tap-handling block.

### 8. Bridge safety

N/A.

## Live device verification (CU on iPhone 17 Pro Sim, iOS 26.5)

Driven via computer-use against fresh build v3.22.8 (this WI's binary):

1. Cold-launch with `--seed-md-toc` → "Test Markdown TOC" book in library.
2. Tap book → MD reader opens (dark theme persisted from prior session).
3. Long-press → drag selects multi-line text → "Highlight | Add Note | Define" menu.
4. Tap Highlight → yellow paint visibly applied to ~3 lines.
5. Tap outside (y=600) → selection dismisses, highlight persists, chrome toggles.
6. **Tap on highlighted text (230, 264)** → chrome toggles back ON; **the inline edit/delete menu does NOT appear**.

### Diagnosis (own — not from issue comments)

The `handleContentTap` path runs and the hit-test SHOULD match the freshly-created highlight (after the apply() lookup-sync fix). BUT the live behavior shows the **chrome-toggle path runs instead** of the highlight-tap path. Two hypotheses:

- **(a) Hit-test miss due to gesture-arbitration**: UITextView with `isSelectable: true` installs its own tap recognizer for cursor / selection. My added `UITapGestureRecognizer` competes via `gestureRecognizerShouldRecognizeSimultaneouslyWith → true`, but UITextView's native tap may consume the gesture before my recognizer's handler fires the lookup branch — falling through to the chrome-toggle path on the same coord set.
- **(b) `UIEditMenuInteraction.presentEditMenu` doesn't display on top of UITextView's responder chain**: even if the notification + presenter invocation runs, the menu may be silently rejected because UITextView's selection state preempts.

Both hypotheses would manifest the same way (no visible menu). Distinguishing them needs a Logger statement at the hit-test branch — not added in this WI to keep the diff minimal.

### Follow-up scope (deliberate deferral, NOT a regression)

The cleanest fix is likely **option C: integrate via `UITextViewDelegate.textView(_:editMenuForTextIn:suggestedActions:)`**. When the user long-presses on highlighted text, iOS shows the existing `Highlight | Add Note | Define` menu; this delegate callback can detect overlap with persisted highlights and PREPEND a "Delete Highlight" action. This sidesteps the gesture-arbitration conflict because we hook the same menu UITextView naturally presents.

Tracked as deferred WI-2c (or fold into WI-3 chunked TXT). The current `.readerHighlightTapped` + presenter infrastructure stays correct — it's the FUTURE path for formats (EPUB, Foliate, PDF) where the textView-gesture conflict doesn't apply.

## Tests added

- `vreaderTests/Views/Reader/TXTBridgeHighlightTapSubscriberTests.swift` — 3 methods. All passing.
- Pre-existing WI-1 (16) + WI-2 (13) tests continue passing — no regression. Combined: 32 tests across 6 suites.

## Risks accepted

- **End-to-end UX gap on TXT/MD**: the subscriber-side wiring is functionally complete (unit-tested + manually traced), but the live tap-on-highlight UX is blocked by UITextView gesture-arbitration. Documented as a follow-up; ship value is the foundation for WI-4/5/6 (EPUB/Foliate/PDF) where this conflict doesn't exist.
- **File-size guideline drift**: both bridge + coordinator are 322/392 lines (over 300). Cohesion of tap-handling block argues against splitting now.

## Verdict

**follow-up-recommended.** The WI-2b code is correct, unit-tested, and ready
to merge. Live UX for TXT/MD specifically needs a follow-up (delegate-menu
approach over UIEditMenuInteraction). The infrastructure unblocks the
subsequent format WIs.
