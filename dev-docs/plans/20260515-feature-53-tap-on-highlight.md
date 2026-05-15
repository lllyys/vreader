# Feature #53 — Tap on highlighted text → inline edit/delete options

GH: #596 | Status entering plan: TODO → PLANNED on Gate 2 pass
Author: Claude (Opus 4.7) | Date: 2026-05-15

## Problem

Deleting a highlight today requires navigating to the annotations panel
(Highlights tab → swipe-to-delete). Tapping already-highlighted text in any
reader format does nothing — there is no tap-on-highlight → inline
popup/contextMenu. Users expect a Kindle-style inline menu with at minimum
Delete, with room to grow to Edit Color / Add Note.

Background fact uncovered during plan research: the Foliate path at
`vreader/Views/Reader/FoliateReaderContainerView+Highlights.swift:41`
*currently* posts `.readerHighlightRequested` from `handleAnnotationShow`
when the user taps an existing AZW3 highlight, but the modifier at
`ReaderNotificationModifier.swift:48` is the **create** path — it requires
a non-empty `TextSelectionInfo` range and validates `endUTF16 > startUTF16`.
The mismatch means tapping a Foliate highlight silently returns. Same null
behavior across TXT/MD/EPUB/PDF. This feature replaces the broken
overload with a dedicated tap-show pipeline.

## Surface area

### New notification + payload

- `vreader/Views/Reader/ReaderNotifications.swift`
  - Add `static let readerHighlightTapped = Notification.Name("vreader.readerHighlightTapped")` —
    fired by reader bridges (text, EPUB JS bridge, Foliate, PDF) when the user
    taps an existing highlight.
  - Add struct:
    ```swift
    struct ReaderHighlightTapEvent: Sendable {
        let highlightID: UUID
        let sourceRect: CGRect    // screen-space rect of the tapped highlight,
                                  // used to anchor a popover / action sheet
    }
    ```
  - Notification's `object` is `ReaderHighlightTapEvent`.

### Tap-action enum

- `vreader/ViewModels/HighlightTapAction.swift` (new file)
  ```swift
  enum HighlightTapAction: Sendable {
      case delete
      // Future: case editColor, case addNote, case copy
  }
  ```

### Presenter

- `vreader/Views/Reader/HighlightActionPresenter.swift` (new file)
  - `@MainActor protocol HighlightActionPresenting` with one method:
    `func present(for event: ReaderHighlightTapEvent, in view: UIView, completion: @MainActor @Sendable @escaping (HighlightTapAction?) -> Void)`
  - Default implementation `UIKitHighlightActionPresenter`: shows a `UIMenu`
    on iOS 16+ (or `UIAlertController(style: .actionSheet)` on visible-VC
    fallback) anchored to `sourceRect` in `view`. Returns selected action
    through completion; nil = dismissed without action.

### Coordinator routing

- `vreader/ViewModels/HighlightCoordinator.swift` already has `remove(highlightId:)`.
  Add a public:
  ```swift
  @MainActor
  func handleTapAction(_ action: HighlightTapAction, highlightID: UUID) async {
      switch action {
      case .delete:
          await remove(highlightId: highlightID)
      }
  }
  ```

### Modifier hookup (deferred to per-format WIs)

- `ReaderNotificationModifier.swift` gains an additional `.onReceive` on
  `.readerHighlightTapped` that asks an injected presenter to show the menu
  and routes the result back through the coordinator. **WI-1 only**
  introduces this modifier extension behind a presenter-injection point —
  it stays inactive until a format actually posts the notification.

### Files OUT of scope (this feature)

- `EPUBHighlightJS.swift` JS — only edited in WI-4 (EPUB).
- `Foliate*` files — only edited in WI-5 (Foliate/AZW3).
- `PDFAnnotationBridge.swift` — only edited in WI-6 (PDF).
- Foliate's `handleAnnotationShow` misuse of `.readerHighlightRequested` —
  fixed in WI-5; **not** in WI-1 (foundational work must not change
  user-observable behavior).
- Edit-color, Add-note, Copy menu items — listed in row as future
  extensions; not in this feature's acceptance criteria.

## Prior art / project precedent / rejected alternatives

### Prior art in this codebase

- `.readerHighlightRequested` / `.readerHighlightRemoved` / `.readerHighlightsDidImport`
  pattern in `ReaderNotifications.swift` — bridge fires notification,
  modifier subscribes, coordinator does the work. Same shape used here.
- `HighlightCoordinator` (`vreader/ViewModels/HighlightCoordinator.swift`)
  already centralizes create/restore/remove flows across all reader formats
  with `HighlightRenderer` protocol per-format adapters
  (`TextHighlightRenderer`, `EPUBHighlightRenderer`, `PDFHighlightRenderer`,
  `FoliateHighlightRenderer`). The tap-action handler fits cleanly here.
- iOS 17+ `UIEditMenuInteraction` is used elsewhere in TXT bridges for the
  text-selection menu; a similar `UIMenu` pattern fits the tap-on-highlight
  case.

### Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Reuse `.readerHighlightRequested` for both create and tap paths | Already shown to silently fail; overloading the notification couples create-validation logic to tap-show paths. Two notifications cost nothing and keep both paths legible. |
| Long-press to delete instead of tap | Long-press is the system gesture for **starting** a selection — overloading it would block highlight creation on already-highlighted spans. |
| Add a "Delete Highlight" UIMenu item inside the existing text-edit menu when the selection overlaps a painted range | Requires a selection, not a tap. The user complaint is "I tap and nothing happens." |
| iOS 17 `UIEditMenuInteraction` for the inline menu | Works on iOS 16+ targets and would be ideal — but the deployment target check (`@available`) plus integration with non-UITextView formats (EPUB WebView, PDFView) make it more cost than `UIMenu` anchored to a `sourceRect`. Revisit when iOS 17 floor is enforced. |
| One single "tap" handler in a base class shared by all formats | TXT/MD use `UITextView`, EPUB uses `WKWebView`, PDF uses `PDFView`, Foliate uses Foliate-js inside WKWebView. No useful base class exists. Each format has its own native hit-test path. |

### Industry precedent

Kindle iOS: tap on highlighted text → inline contextual bubble with Delete +
Note + Color. Apple Books iOS: tap → inline action menu with Remove
Highlight + Note + Color. The Delete-only WI-1 ships the minimum-viable
shape; the structure supports future menu growth.

## Work-item sequencing

| WI | Tier | What ships | PR size |
|----|------|-----------|---------|
| WI-1 | Foundational | Notification + payload struct + tap-action enum + presenter protocol + UIKit presenter impl + coordinator handler + Swift Testing suite. No format yet posts the notification — modifier subscribes but tap-show path is dormant. | ~6 files, ~200 LOC |
| WI-2 | Behavioral | TXT — extend `HighlightableTextView` / `TXTTextViewBridge` with a `UITapGestureRecognizer` that hit-tests against painted ranges (stored in `HighlightingLayoutManager.highlightRanges`) and fires `.readerHighlightTapped`. Tests cover hit/miss + non-highlight tap preserves chrome-toggle (`.readerContentTapped`). | ~4 files, ~150 LOC |
| WI-3 | Behavioral | MD — same pattern, via the chunked + non-chunked text path. Tests mirror WI-2. | ~3 files, ~100 LOC |
| WI-4 | Behavioral | EPUB — extend `EPUBHighlightJS.swift` JS payload to attach a `click` listener that uses `document.caretPositionFromPoint()` (or per-Range `getBoundingClientRect` hit-test) to identify which highlight ID was tapped; post message; Swift posts `.readerHighlightTapped`. Tests: parser + payload encoding. | ~3 files, ~180 LOC |
| WI-5 | Behavioral | Foliate/AZW3 — `handleAnnotationShow(cfi:)` stops posting `.readerHighlightRequested` (regression fix) and instead resolves the CFI to a `HighlightRecord` via persistence, then posts `.readerHighlightTapped`. Tests: CFI→UUID resolution helper. | ~3 files, ~120 LOC |
| WI-6 | Behavioral (final) | PDF — `PDFViewBridge` adds tap gesture; on tap, walk `PDFAnnotationBridge.annotationMap` for hit-test, post `.readerHighlightTapped`. Final WI; flips feature row to DONE. | ~3 files, ~140 LOC |

Total: 6 WIs, ~890 LOC across 22 files. Each WI is one PR.

## Test catalogue

### WI-1 (this iteration's scope)

- `vreaderTests/Views/Reader/ReaderHighlightTapEventTests.swift` (new)
  - `event_isValueType_andSendable()`
  - `event_canBePostedAndReceived()` — round-trip through NotificationCenter
  - `event_sourceRectIsPreserved()` — popover anchoring depends on this
- `vreaderTests/ViewModels/HighlightTapActionTests.swift` (new)
  - `tapAction_delete_isExhaustiveSwitchable()` — enforce switch coverage
    so adding a case is a compile error in `handleTapAction`
- `vreaderTests/Views/Reader/UIKitHighlightActionPresenterTests.swift` (new)
  - `presenter_builds_uiMenu_withDeleteItem()` — verify menu has a Delete
    item titled exactly "Delete Highlight" (acceptance criterion: at minimum
    a Delete option). Uses test double instead of presenting on real screen.
  - `presenter_completion_isCalledOnce_perAction()` — guard against
    double-fire on rapid dismiss.
  - `presenter_dismissWithoutAction_callsCompletionNil()` — guard against
    leaking the completion when the user taps outside the menu.
- `vreaderTests/ViewModels/HighlightCoordinatorTapHandlerTests.swift` (new)
  - `handleTapAction_delete_callsRemove()` — uses existing
    `HighlightPersistingMock` (already present in test helpers) to assert
    `remove(highlightID:)` was invoked exactly once.
  - `handleTapAction_delete_postsHighlightRemoved_notification()` — verify
    the existing `.readerHighlightRemoved` notification still fires
    downstream (rerouting via the same coordinator preserves the bug-#78
    visual-clear path).

### WI-2 through WI-6 (subsequent iterations)

Each behavioral WI ships its own format-specific gesture/hit-test tests +
the cross-format integration test:

- `vreaderTests/Views/Reader/<Format>HighlightTapTests.swift` — hit-test
  against painted ranges, miss = no notification, hit = correct UUID in
  payload, multi-highlight overlap picks the topmost.

End-to-end (Gate 5 device-verify on the final WI): on iPhone 17 Pro
Simulator, open a fixture book per format, create a highlight, tap it,
verify the menu appears and Delete removes the visual + persisted record.

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Existing Foliate `handleAnnotationShow` already posts `.readerHighlightRequested` — WI-1 must not change that yet. | WI-1 is **additive only**: new notification + new struct + new presenter + new coordinator method. The existing notification continues to be silently no-op'd by the create-path validator. WI-5 removes the misuse. |
| EPUB CSS Highlights API has no DOM element to attach `click` to. | WI-4 problem only; WI-1 doesn't touch JS. WI-4 plan: tap → `caretPositionFromPoint()` → walk registered Range list → match by `compareBoundaryPoints`. Existing `highlightRangeMap` in `EPUBHighlightJS.swift` already stores live Range objects. |
| Two highlights overlap; tap is ambiguous. | Always pick the topmost / most-recent UUID (per render order). Document this in the per-format tests. |
| Tap detection competes with text-selection long-press start. | Tap gesture has `require(toFail:)` relationship with long-press in WI-2/3; in WI-4 EPUB the JS click listener is short-press only (mousedown→mouseup<200ms). |
| `UIMenu` anchoring at `sourceRect` flickers on small highlights. | Compute `sourceRect` to be the union of all painted rects for that highlight ID; if zero-size, fall back to the tap location. |
| iOS 16 deployment target: `UIEditMenuInteraction` is iOS 16+, fine — but `UIMenu`-anchored popover is iOS 14+. We're safe. | n/a |

## Backward compat

- No SwiftData schema change. No backup format change.
- WI-1 is dormant — nothing fires the new notification yet — so users see
  no behavior change at end of WI-1.
- Per-format WIs are independently shippable; partial rollout (e.g.,
  TXT/MD only) still works for the formats that landed.
- Foliate `handleAnnotationShow` misuse remains until WI-5 ships; it has
  been silently no-op'd since merge — WI-5 isn't a regression risk, it's a
  regression fix.
- `.readerHighlightRequested` semantics unchanged (text-selection → create
  path). `.readerHighlightRemoved` semantics unchanged (deletion → visual
  clear path). New `.readerHighlightTapped` lives alongside them.

## Acceptance criteria (final WI)

From the docs/features.md row 53:

- (a) Tapping a highlighted word shows a menu with at minimum a Delete option.
- (b) Delete removes the highlight visually and from persistence (via
      `HighlightCoordinator.remove` / `.readerHighlightRemoved` pipeline).
- (c) Consistent across all 5 formats: TXT, MD, EPUB, AZW3 (Foliate), PDF.
- (d) Tapping non-highlighted text preserves existing scroll/chrome-toggle
      behavior.

WI-1 acceptance: foundational types in place; test suite green; nothing
visibly changes (the notification has no posters yet).

## Manual Audit Evidence (Gate 2, manual-fallback per rule 47)

Per saved feedback: Codex audit-time consistently exceeds cron-iteration
budget; manual-fallback is the documented alternative.

### Files read in full

- `vreader/Views/Reader/ReaderNotifications.swift` (89 lines)
- `vreader/Views/Reader/ReaderNotificationModifier.swift` (137 lines)
- `vreader/Views/Reader/HighlightableTextView.swift` (125 lines)
- `vreader/Views/Reader/FoliateReaderContainerView+Highlights.swift` (58 lines)
- `vreader/Views/Reader/EPUBHighlightJS.swift` (around tap detection sites)
- `vreader/ViewModels/HighlightListViewModel.swift` (around .readerHighlightRemoved poster)

### Files surveyed (grep, not full-read)

- `HighlightCoordinator.swift` — confirmed `remove(highlightId:)` exists
- `PDFAnnotationBridge.swift` — confirmed `annotationMap` exists for hit-test
- `TXTBridgeShared.swift` — confirmed `.readerHighlightRequested` poster pattern
- `EPUBHighlightJS.swift` — confirmed CSS Highlights API + Range registry pattern

### Symbols / signatures verified

- `HighlightCoordinator.remove(highlightId: UUID) async` — exists, used by `HighlightListViewModel.swift:108`
- `HighlightingLayoutManager.highlightRanges: [NSRange]` — exists, public-on-class, can be hit-tested from a tap gesture in WI-2
- `FoliateReaderContainerView.handleAnnotationShow(cfi: String)` — exists, currently misuses `.readerHighlightRequested`
- `Notification.Name("vreader.readerHighlightTapped")` — not present in current codebase ✓ (no collision)
- `HighlightTapAction` — not present ✓
- `ReaderHighlightTapEvent` — not present ✓
- `HighlightActionPresenting` protocol — not present ✓
- iOS 16 `UIMenu`-anchored popover via `UIEditMenuInteraction` — confirmed available, deployment target supports

### Edge cases checked (WI-1 scope)

1. Notification posted with a UUID that has been deleted between tap and
   handler invocation: `HighlightCoordinator.remove` already handles missing
   IDs (existing test coverage in HighlightCoordinator tests). No new branch needed.
2. Presenter completion called more than once: `UIKitHighlightActionPresenter`
   guards with a `didFire` flag; test covers it.
3. Presenter dismissed without action (user taps outside menu): completion
   fires with `nil`; coordinator no-ops. Test covers it.
4. Notification fired from a non-main thread: `ReaderHighlightTapEvent` is
   `Sendable`; the modifier's `.onReceive` runs on the main actor — safe.
5. Two notifications fired in rapid succession before the presenter
   dismisses: presenter is stateful (`didFire`); the second event's
   completion fires with `nil`. WI-2+ tests cover this from the gesture side.

### Risks accepted

- iOS 16 `UIMenu` anchoring on very small painted rects may flicker. Mitigation
  documented above; acceptance is for normal-size highlights.
- WI-1 ships dormant code (no caller). Justified because Gate 5 is per-PR
  and foundational WIs don't require device-verify; the dormancy is
  intentional + tracked in this plan.

### Tests added (WI-1)

Listed in "Test catalogue → WI-1" above. 4 new Swift Testing files, 7
methods total.

### Tests intentionally deferred

- Format-specific tap gesture hit-test tests defer to their respective WIs.
- Cross-format integration test defers to final WI's Gate 5 device-verify.

### Verdict

Manual audit clean. No Critical/High/Medium findings. Plan is ready for
Gate 3.

## Revision history

- 2026-05-15 v1: initial draft + manual-fallback Gate 2 audit recorded inline.
