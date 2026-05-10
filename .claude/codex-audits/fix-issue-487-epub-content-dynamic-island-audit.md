---
branch: fix/issue-487-epub-content-dynamic-island
threadId: 019e12fa-605d-7e90-a296-7aeed615f4ef
rounds: 3
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex audit — bug #163 fix (EPUB content obscured by Dynamic Island at chapter start)

GH issue: #487. Severity: high.

Files changed:

Production:
- `vreader/Views/Reader/EPUBWebViewBridge.swift` — added `safeAreaTopInset: CGFloat = 0` property; called `applySafeAreaTopInset(to:top:)` in makeUIView; live re-applied in updateUIView with change detection; paged-mode rebuild triggered by `safeAreaChanged || boundsChanged` while paged + URL stable.
- `vreader/Views/Reader/EPUBWebViewBridgeJS.swift` — added `applySafeAreaTopInset(to:top:)` static seam (clamps negative inputs, writes both `contentInset.top` AND `verticalScrollIndicatorInsets.top`).
- `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` — added `safeAreaTopInset: CGFloat` and `lastPagedBounds: CGRect` fields; `setupPagination(...)` now subtracts the safe-area inset from viewport height and snapshots the bounds for change-detection.
- `vreader/Views/Reader/EPUBReaderContainerView.swift` — wrapped `EPUBWebViewBridge(...)` in `GeometryReader { proxy in ... }` and threaded `proxy.safeAreaInsets.top` into the new property.

Tests:
- `vreaderTests/Views/Reader/EPUBWebViewBridgeTests.swift` — added 5 tests in `EPUBWebViewBridgeSafeAreaInsetTests` (writes-input, preserves-other-insets, zero-clears, negative-clamps-to-zero, matches-scrollIndicatorInsets) + 3 tests in `EPUBPaginationHelperSafeAreaTests` (literal viewportHeight, reduced-height-with-inset, zero-height-guard math).

## Round 1 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | High | `EPUBWebViewBridgeCoordinator.swift:217` | Paged EPUB regressed: pagination used `webView.bounds.height` while `contentInset.top` shifted columns down by `safeAreaTopInset`, clipping the bottom of each column off-screen. | **Fixed**. `setupPagination(...)` now reads the coordinator's `safeAreaTopInset` and computes `viewportHeight = max(bounds.height - safeAreaTopInset, 0)`. `updateUIView` re-injects pagination CSS when the inset changes. 3 new regression-guard tests pin the CSS shape. |
| 2 | Low | `EPUBWebViewBridge.swift:43` | File at 320 lines, over the ~300 guideline. | **Accepted with rationale** — splitting makeUIView/updateUIView across files makes the pair harder to read; future refactor PR can revisit. |

## Round 2 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | `EPUBWebViewBridge.swift:301` | Paged-mode rebuild trigger only watched `safeAreaTopInset` changes. Pure bounds changes (iPad split-screen / Stage Manager / multitasking resize) keep the inset constant but change `bounds.width`/`height` — pagination would stay stale. | **Fixed**. Added `lastPagedBounds: CGRect = .zero` field on the coordinator; `setupPagination(...)` snapshots `webView.bounds` after computing pagination. `updateUIView` rebuild trigger is now `safeAreaChanged || boundsChanged` while paged + URL stable. |

## Round 3 verification

No new findings. Codex confirmed:
- `CGRect` structural `==` correctly detects any positional/size change (split-view, Stage Manager).
- `.zero` initial value doesn't cause spurious first-call rebuild because the `currentURL == contentURL` guard blocks the branch until `didFinish` runs `setupPagination(...)` for the first time and seeds the field.
- The weak "zero or negative effective height" test (left in place per round-2 discussion) is harmless documentation, not a regression risk.

Final verdict: `ship-as-is`.

> "I found no new blocking issue. The rebuild path is valid. The `.zero` initial value does not cause an unwanted first rebuild. No new issue from the additions." — Codex round 3

## Test gate

`xcodebuild test -only-testing:{EPUBWebViewBridgeSafeAreaInsetTests,EPUBPaginationHelperSafeAreaTests,EPUBWebViewBridgeScrollBackgroundTests}` — **16/16 green**.

## Plan compliance

Fix scope per the issue body matches:
- [x] EPUB chapter start no longer clipped behind Dynamic Island (root cause: `contentInsetAdjustmentBehavior = .never` with no compensating top inset).
- [x] Safe area is read from SwiftUI via GeometryReader and threaded into the bridge.
- [x] Both `contentInset.top` and `verticalScrollIndicatorInsets.top` are set so the scrollbar isn't clipped either.
- [x] Live updates on rotation / multitasking via change-detection in updateUIView.
- [x] Paged-mode column height is reduced to match the visible viewport-below-notch (round-1 audit fix).
- [x] iPad split-screen / Stage Manager bounds changes trigger pagination rebuild (round-2 audit fix).

## Cross-format scope (per the issue body)

The bug body called out AZW3/Foliate as potentially affected. Codex audited `FoliateViewBridge.swift` and `FoliateSpikeView.swift`: neither sets `contentInsetAdjustmentBehavior = .never`, and both disable scrolling (`scrollEnabled = false`). The same root cause does NOT apply there. Treated as "unverified / deferred" rather than "same fix omitted." If a user reports Foliate-specific DI clipping, that's a separate bug.

## Files OUT of scope

- `FoliateViewBridge.swift`, `FoliateSpikeView.swift` — different scrollEnabled behavior, no contentInsetAdjustmentBehavior = .never.
- TXT/PDF/MD readers — different render pipelines (UITextView/PDFView), separate inset handling.
