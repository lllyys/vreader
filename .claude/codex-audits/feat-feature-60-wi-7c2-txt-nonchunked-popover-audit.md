---
branch: feat/feature-60-wi-7c2-txt-nonchunked-popover
threadId: 019e2ebd-9fdd-77d1-be48-70f0cfb9e07c
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7c2 TXT non-chunked bridge swap

## Round 1 — 1 High + 1 Low

### High — TXT/MD highlight consumer ignores `userInfo["color"]`
- **`vreader/Views/Reader/ReaderNotificationModifier.swift:48`** | High
  WI-7c2 is the first production path that exposes the 4 color
  swatches, but the TXT/MD highlight consumer hardcoded
  `color: "yellow"` in the `highlightCoordinator.create` call.
  `SelectionPopoverActionRouter` posts the chosen
  `NamedHighlightColor.rawValue` in `userInfo["color"]`, but it
  was being dropped — users tapping pink/green/blue would still
  get a yellow highlight.

**Fix applied**:
- Added `resolveHighlightColor(from notification: Notification) -> String` free function in `ReaderNotifications.swift`. Reads `userInfo["color"] as? String ?? "yellow"`.
- `ReaderNotificationModifier` swapped from hardcoded `"yellow"` to `resolveHighlightColor(from: notification)`.
- Added `ResolveHighlightColorTests.swift` with 4 tests pinning the contract: (a) all 4 NamedHighlightColor values round-trip; (b) nil userInfo → "yellow"; (c) missing "color" key → "yellow"; (d) wrong-type "color" → "yellow".

`ReaderNotificationHandlers.handleHighlightRequest:137` (separate static method) also hardcodes "yellow", but `grep -rn "handleHighlightRequest\b"` returns only the definition — no production call sites. Dead code; left alone. WI-7c3..7c5 cleanup can address.

### Low — producer API uses TXTBridgeShared.postSelectionNotification instead of SelectionPopoverRequest.post
- **`vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift:336`** | Low
  WI-7c1 introduced `SelectionPopoverRequest.post(selection:on:)`
  as the typed producer API. The TXT non-chunked swap bypasses it
  and reuses `TXTBridgeShared.postSelectionNotification(...)`.
  Functionally equivalent (both produce `TextSelectionInfo` in
  `notification.object`) but duplicates the producer-side wire
  contract.

**Fix applied** (accepted with rationale via inline comment): the shared `TXTBridgeShared.postSelectionNotification` already implements the range→TextSelectionInfo extraction with UTF-16 + bounds validation matching `UITextView` delegate semantics. `SelectionPopoverRequest.post(selection:on:)` is only the notification-posting seam — it expects a pre-built `TextSelectionInfo`. Routing the bridge call through `SelectionPopoverRequest.post` would require re-implementing extraction on the producer side. Reusing the established extraction helper avoids the duplication. The presenter reads via `notification.object as? TextSelectionInfo` — same wire shape both helpers produce. Codex round 2 accepted: "I would keep that rationale."

## Round 2 — clean

Codex verified: "The High fix is correct end-to-end for WI-7c2.
The flow is now `SelectionPopoverActionRouter.route(.highlight(...))`
posting `.readerHighlightRequested` with `userInfo["color"]`,
`ReaderNotificationModifier` reading that via
`resolveHighlightColor(from:)` and passing it into
`highlightCoordinator.create(...)`. That closes the regression I
called out."

## Residual risk (device-verify-only)

Codex flagged in both rounds: "device verification is still needed
to confirm iOS 16 does not show a visible empty edit-menu flash
before the sheet appears." Apple's `UITextViewDelegate`
documentation states `editMenuForTextIn` returns the menu to
display, and `UIMenu(children: [])` is a reasonable suppression
strategy — but the no-flash claim must be confirmed on device.
This is Gate 5a's job for WI-7c2.

## Verdict statement

**ship-as-is** after round 1 (1 High color-userInfo-ignored + 1 Low producer-API-duplication → both addressed). Round 2 clean.

All 8 audit dimensions clean:
1. Correctness — color flows end-to-end from router → notification → consumer. The empty UIMenu suppresses the legacy surface. Sheet presentation handled by WI-7c1's presenter.
2. Edge cases — zero-length range (no popover), missing userInfo (fallback to yellow), wrong-type userInfo (fallback), latest-wins coalescing (inherited from WI-7c1).
3. Security — pure SwiftUI/NotificationCenter; no JS interop in this path.
4. Duplicate code — none (producer side uses the established extraction helper; consumer side has the single resolveHighlightColor seam).
5. Dead code — `ReaderNotificationHandlers.handleHighlightRequest` is dead (no call sites), but it pre-existed; not introduced by this WI.
6. Shortcuts / patches — none.
7. VReader compliance — `@MainActor` on `resolveHighlightColor` + the modifier; Swift 6 strict concurrency satisfied (test files use the established `nonisolated(unsafe)` pattern for sync observer captures); file sizes well under 300 lines.
8. Bridge safety — `TXTBridgeShared.postSelectionNotification`'s existing UTF-16 + bounds validation covers Unicode/newline selections.

## Test results

- `TXTBridgeShared` suite: +1 test (8/8 pass with the new `postSelectionNotificationOnPopoverRequestRoundTrips`)
- `TXTTextViewBridgeEditMenuTests`: 3 new tests pass (empty menu, popover-request post, zero-length no-post)
- `ResolveHighlightColorTests`: 4 new tests pass (round-trip + 3 fallback cases)
- Total in scope: 16/16 pass

Full vreaderTests run has 2 pre-existing parallel-execution flakes in `ReplacementTransformTests` (regex tests; pass in isolation). Unrelated to this WI.

## Strengths called out by Codex

- The coordinator gets the zero-length case right: no popover request for caret placement, while still suppressing the legacy menu.
- `TXTBridgeShared.postSelectionNotification` is still the right range-extraction path for Unicode/newline selections.
- `TXTReaderContainerView` mounts the presenter at the container level, so the swap covers the non-chunked TXT surface cleanly (including the chapter-based single-UITextView path).
- The new tests are targeted and useful. `TXTTextViewBridgeEditMenuTests` pins the coordinator contract directly.
- `nonisolated(unsafe)` test usage is consistent with the repo's established pattern.
- The color-resolution helper is small and testable.
- The modifier comment clearly documents the mixed legacy/new-producer transition period.
- The bridge comment makes the producer/consumer boundary explicit.
