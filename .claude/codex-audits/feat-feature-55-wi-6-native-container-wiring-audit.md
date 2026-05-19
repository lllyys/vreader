---
branch: feat/feature-55-wi-6-native-container-wiring
threadId: 019e3f01-292e-7b00-bd23-3ff0bf5c88b7
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #55 WI-6 (native TXT/MD/PDF note-preview wiring)

WI-6 wires `NotePreviewModifier` into the three native reader containers
(`TXTReaderContainerView`, `MDReaderContainerView`, `PDFReaderContainerView`)
via the `notePreviewPresenterIfAvailable` attach helper, and re-homes feature
#53's inline delete menu from the tap gesture to a `UILongPressGestureRecognizer`
in the TXT non-chunked, chunked, and PDF bridges. A tap now opens the #55 note
preview; a deliberate long-press opens #53's delete menu.

## Round 1 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `TXTTextViewBridge.swift:102` / `TXTTextViewBridgeCoordinator.swift:307` / `TXTChunkedReaderBridge.swift:604` | High | The WI-6 long-press is added on the same `UITextView` surface as the system text-selection long-press, and the coordinator still unconditionally allows simultaneous recognition (`gestureRecognizerShouldRecognizeSimultaneously() == true`). A long-press on a highlighted passage fires `handleHighlightLongPress` AND lets UITextView proceed into selection / edit-menu — so "long-press opens only #53's delete menu" is not enforced for TXT/MD/chunked. | Make the custom long-press mutually exclusive with the built-in selection recognizer when the press lands on a persisted highlight. Gate recognition up front with a highlight hit-test (`gestureRecognizerShouldBegin`) and avoid unconditional simultaneous recognition for that path. |
| `PDFViewBridge.swift:99` | Medium | PDF has the same arbitration problem — `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` returns `true` for everything, and `handleHighlightLongPress` fires on `.began` before PDFKit has necessarily established `currentSelection`. | Apply the same gesture arbitration as TXT. |
| `Feature55NativeWiringTests.swift:27` | Low | The suite does not pin the behavior swap (tap must not call `present(...)`, long-press must be the only path that does). | Add a seam so coordinator-level tests can assert "tap posts notification only" and "long-press invokes presenter only". |

### Round 1 resolutions

- **High + Medium (gesture arbitration)** — fixed. Approach: instead of
  no-op'ing inside the long-press handler, the recognizer is *gated* so it
  never even begins on plain body text.
  - `TXTBridgeShared.swift` — added `highlightLongPressName` (the
    `UIGestureRecognizer.name` stamped on WI-6's long-press) and
    `simultaneousRecognitionAllowed(for:)` (returns `false` only for the
    highlight long-press).
  - `TXTTextViewBridge.swift`, `TXTChunkedReaderBridge.swift`,
    `PDFViewBridge.swift` — each stamps `highlightLongPress.name =
    TXTBridgeShared.highlightLongPressName` in `makeUIView`.
  - All three coordinators — `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`
    now denies simultaneity when *either* side of the pair is the named
    highlight long-press; the content-tap keeps the legacy `true`.
  - All three coordinators — new `gestureRecognizerShouldBegin(_:)` runs the
    SAME highlight hit-test the handler reuses (`resolveHighlightTap` /
    `resolveChunkedHighlightTap` / `resolveHighlightTapEvent`) and returns
    `true` only on a confirmed highlight hit. A long-press on plain text
    never engages WI-6's recognizer → native text selection proceeds
    undisturbed; on a highlight hit the recognizer begins AND is denied
    simultaneity → UITextView/PDFKit never co-start a selection.
- **Low (test seam)** — partially addressed in round 1 (8 arbitration tests
  added); fully resolved in round 3 (see below).

## Round 2 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `Feature55NativeWiringTests.swift:172` | Low | The new arbitration tests prove the named-recognizer policy and `gestureRecognizerShouldBegin` guards, but the suite still does not pin WI-6's core behavior swap: tap must post `.readerHighlightTapped` without invoking `present(...)`; long-press must be the path that invokes `present(...)`. A regression reintroducing menu-on-tap would still pass. | Add coordinator-level tests with a fake presenter + view-backed recognizers driving `handleContentTap` / `handleHighlightLongPress` directly. |

Round 2 confirmed the round-1 High and Medium are resolved.

### Round 2 resolution

- **Low (behavior-swap seam)** — fixed. Added to `Feature55NativeWiringTests.swift`:
  - `SpyHighlightActionPresenter: HighlightActionPresenting` — records
    `present(...)` call count + last event.
  - `FixedPointTap` / `FixedPointLongPress` — gesture-recognizer subclasses
    overriding `location(in:)` (and `state` for the long-press) so the
    coordinator handlers can be driven deterministically.
  - 3 behavior tests: tap-on-highlight posts `.readerHighlightTapped` with
    `presentCallCount == 0`; long-press-on-highlight calls `present` exactly
    once; long-press in `.changed` state does not re-fire the menu.

## Round 3 — verdict

Zero open Critical/High/Medium/Low findings. The round-2 Low is resolved —
the suite now directly pins the WI-6 behavior swap at the coordinator layer.

## Summary verdict

**ship-as-is.** Three audit rounds. Round 1 found a High + Medium
gesture-arbitration gap (the re-homed long-press was not isolated from
native text selection) and a Low test-seam gap; round 1 fixed the
arbitration via a named recognizer + `gestureRecognizerShouldBegin`
hit-test gate + name-aware non-simultaneous recognition. Round 2 confirmed
the High/Medium fixes and refined the Low to require pinning the core
tap→notification / long-press→menu behavior swap; round 2 added 3
coordinator-level behavior tests. Round 3 is clean. WI-6's behavioral
end-to-end (tap → preview, long-press → #53 menu on all 3 native formats)
is exercised at Gate-5 device verification.
