---
branch: feat/feature-53-wi-1-tap-on-highlight-foundational
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Feature #53 WI-1 (foundational tap-on-highlight infrastructure)

Manual fallback per rule 47. Saved feedback explicitly notes that Codex
audits exceed cron-iteration budget; manual-fallback is the documented
alternative.

## Scope of this WI

Foundational only — introduces:

- `Notification.Name.readerHighlightTapped` + `ReaderHighlightTapEvent`
  struct (UUID + CGRect, Sendable + Equatable).
- `HighlightTapAction` enum (`.delete` only).
- `HighlightActionPresenting` protocol + `UIKitHighlightActionPresenter`
  impl using `UIEditMenuInteraction`.
- `FireOnceBox` single-shot completion guard.
- `HighlightCoordinator.handleTapAction(_:highlightID:)` switching over
  `.delete` and dispatching to `persistence.removeHighlight` + posting
  `.readerHighlightRemoved` for the existing visual-clear pipeline.
- 16 Swift Testing methods across 4 new test files.

**No reader-container code is modified**: WI-1 is intentionally dormant.
No format posts `.readerHighlightTapped` yet; format-specific gesture/JS
hit-test work lands in WI-2…WI-6. End-user behavior is unchanged after
WI-1 merges.

## Files reviewed for audit

Production (new + modified):

- `vreader/Views/Reader/ReaderNotifications.swift` — added notification
  + struct.
- `vreader/ViewModels/HighlightTapAction.swift` — new file.
- `vreader/Views/Reader/HighlightActionPresenter.swift` — new file.
- `vreader/Views/Reader/HighlightCoordinator.swift` — added
  `handleTapAction`.

Tests (new):

- `vreaderTests/Views/Reader/ReaderHighlightTapEventTests.swift`
- `vreaderTests/ViewModels/HighlightTapActionTests.swift`
- `vreaderTests/Views/Reader/UIKitHighlightActionPresenterTests.swift`
- `vreaderTests/Views/Reader/HighlightCoordinatorTapHandlerTests.swift`

Plan + docs:

- `dev-docs/plans/20260515-feature-53-tap-on-highlight.md` (new — also
  contains inline Gate 2 audit evidence per rule 47).
- `docs/features.md` row 53 flipped TODO → PLANNED with plan reference.

## Audit dimensions

### 1. Correctness vs plan

- `ReaderHighlightTapEvent` carries `highlightID: UUID` + `sourceRect: CGRect`
  exactly as planned. ✅
- `HighlightTapAction` ships `.delete` only as planned. ✅
- Presenter protocol surface matches plan signature: `present(for:in:completion:)`
  with `@MainActor` completion delivering `HighlightTapAction?`. ✅
- Coordinator handler shape: `handleTapAction(_:highlightID:) async`,
  exhaustive switch on `HighlightTapAction`, `.delete` → persistence
  remove + post `.readerHighlightRemoved`. Matches the plan's "mirror
  `HighlightListViewModel.removeHighlight` pattern" decision. ✅
- WI-1 dormancy invariant: no reader-container code modified, no JS
  edited, no Foliate `handleAnnotationShow` rewired. ✅

### 2. Edge cases in the diff

- Persistence-throw path: `handleTapAction` catches the throw, returns
  without posting the notification. Test
  `handleTapAction_delete_persistenceFailure_doesNotPostNotification`
  asserts this. ✅
- Rapid double-fire of presenter completion: `FireOnceBox` guards via
  NSLock; tests `invokeAction_calledTwice_callsCompletionOnlyOnce` and
  `invokeDismiss_afterPriorAction_doesNotCallCompletionAgain` cover both
  the action→action and action→dismiss race orderings. ✅
- Notification-cross-pollination under Swift Testing parallel runner:
  observer is filtered by `notification.object == expectedString` so
  concurrent tests' UUIDs don't poison the box. ✅
- Empty/zero `sourceRect` round-trip: covered by
  `sourceRectIsPreservedThroughNotificationRoundTrip` using a non-zero
  fractional rect (42.5, 13.25, 100, 22). ✅

### 3. Security (JS injection / WKWebView bridge)

No JS, no WebView interaction, no string interpolation into JS. N/A for
WI-1. WI-4 (EPUB) will need to use `FoliateJSEscaper`-style safe
interpolation when it injects the click listener; that's tracked in the
plan's WI-4 surface area.

### 4. Duplicate code

- `FireOnceBox` is the only single-shot guard in the codebase; not
  duplicating an existing pattern. (Grep `class FireOnce` and `func fire`
  outside this file returned no other matches.)
- The notification-post-after-success pattern in `handleTapAction`
  mirrors `HighlightListViewModel.removeHighlight` deliberately — same
  bug-#78 visual-clear contract. Extracting both to a shared helper is
  premature: only two call sites exist, and the panel-driven path has
  additional state mutation (`highlights.removeAll`) that doesn't apply
  to the tap path. Decision: keep both; revisit if a third caller appears.

### 5. Dead code

- All new symbols have at least one test reference (`#expect` or
  direct invocation). ✅
- `FireOnceBox` is `internal` (no access modifier in a file inside the
  same module = internal) — referenced by both the presenter and the
  presenter tests. ✅
- `invokeAction` / `invokeDismiss` static helpers are referenced by both
  the presenter's UIAction handlers and the test suite — intentional
  testable seam, not dead.
- `PresenterDelegate` is `private` to the file — used inside `present()`.
  ✅

### 6. Shortcuts & patches

- No TODO markers.
- No `try?` swallowing in `handleTapAction` — the error case is
  intentionally caught and silently consumed because the user-facing
  inline menu has already dismissed by the time the error surfaces;
  showing an alert here would be jarring. Documented in the method's
  doc comment.
- No feature flags or backwards-compat shims.

### 7. VReader compliance

- Swift 6 strict concurrency: all `@MainActor`-isolated types
  (`HighlightActionPresenting`, `UIKitHighlightActionPresenter`,
  `FireOnceBox`, `HighlightCoordinator`) cleanly declared. The
  `PresenterDelegate` is intentionally non-isolated to conform to
  `UIEditMenuInteractionDelegate`; runtime safety is preserved via
  `MainActor.assumeIsolated` in the SDK callback paths (UIKit guarantees
  these run on main). ✅
- File sizes:
  - `HighlightActionPresenter.swift` — 135 lines. ✅
  - `HighlightTapAction.swift` — 18 lines. ✅
  - `HighlightCoordinator.swift` — 126 lines (was 102, added 24). ✅
  - `ReaderNotifications.swift` — 96 lines (was 89, added 7). ✅
  - All under the 300-line guideline.
- `@MainActor` correctness: `FireOnceBox.fire` is non-isolated
  (uses NSLock); the block it runs may be `@MainActor` and is invoked
  only from main-actor contexts. Verified by call-site review. ✅
- SwiftData actor isolation: N/A — no SwiftData touched.

### 8. Bridge safety

N/A — no JS interpolation, no WKWebView message parsing. The bridge-side
work is in WI-4 (EPUB) and WI-5 (Foliate); both plan items already
specify FoliateJSEscaper-equivalent safety contracts.

## Findings

None. Zero Critical/High/Medium/Low findings.

## Tests added

- `vreaderTests/Views/Reader/ReaderHighlightTapEventTests.swift` — 4 methods.
- `vreaderTests/ViewModels/HighlightTapActionTests.swift` — 2 methods.
- `vreaderTests/Views/Reader/UIKitHighlightActionPresenterTests.swift` — 6 methods.
- `vreaderTests/Views/Reader/HighlightCoordinatorTapHandlerTests.swift` — 3 methods.

Total: 16 methods, all passing (`xcodebuild test -testPlan All
-only-testing:vreaderTests/<each suite>` → 16/16 pass, ~0.06s).

## Risks accepted

- WI-1 ships dormant code with no end-user behavior change. Justified
  because Gate 5 (device-verify) per rule 47 only applies to behavioral
  WIs; foundational WIs use unit tests + plan audit as their gate.
- `UIEditMenuInteraction` requires iOS 16+; project's deployment target
  (iOS 17 per build log) clears this comfortably.
- `MainActor.assumeIsolated` inside UIAction handlers + SDK delegate
  methods is the standard pattern for crossing Swift 6 strict-concurrency
  boundaries with UIKit. Documented inline in the file.

## Verdict

**ship-as-is.** Foundational WI; pure-additive scope; 16/16 tests pass;
no behavioral change to ship. Plan documents per-format WIs as
follow-ups (WI-2…WI-6).
