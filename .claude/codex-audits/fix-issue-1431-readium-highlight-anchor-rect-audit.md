---
branch: fix/issue-1431-readium-highlight-anchor-rect
threadId: codex-exec (run-codex.sh, 2 rounds)
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Bug #316 (GH #1431): Readium highlight popover anchored card

## Fix summary

The Readium EPUB highlight popover opened as the barren full-width bottom SHEET
instead of the designed anchored CARD: Readium's `OnDecorationActivatedEvent.rect`
is nil for these decorations → `ReaderHighlightTapEvent.sourceRect = .zero` →
`HighlightPopoverPresenter.form` returns `.sheet` (it returns `.card` only for a
non-zero rect).

Two-part fix:
1. `ReadiumDecorationHighlightAdapter.tapEvent` now also takes the event's tap
   `point` (`OnDecorationActivatedEvent.point`), and when `rect` is nil derives a
   1×1 anchor at the point → a non-zero `sourceRect`.
2. `ReadiumEPUBHost+Body` now supplies the navigator's view as the popover host
   (`hostViewProvider: { highlightAdapter?.hostView }`), where
   `hostView = (navigator as? UIViewController)?.view`. Without a host view,
   `resolvedForm` degrades even a non-zero rect back to `.sheet`.

`event.point`/`rect` and the host view are the SAME coordinate space (the
navigator view), so the card anchors over the tapped word with no conversion.

## Round 1 — HIGH (incomplete fix)

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReadiumEPUBHost+Body.swift:64 | High | The point-fallback rect alone didn't restore the card: the host mounted the popover presenter with the default `hostViewProvider: { nil }`, and `resolvedForm` degrades a non-zero rect to `.sheet` when `hasHostView == false`. | **Fixed.** Exposed `ReadiumDecorationHighlightAdapter.hostView` (the navigator's `UIView`) and passed it as `hostViewProvider`. |
| ReadiumDecorationTapEventTests.swift | Low | The new test asserted "non-zero rect → card" but the runtime also needs `hasHostView`. | **Fixed.** Corrected the assertion and added `pointAnchor_withHost_resolvesToCard`: `resolvedForm(point-rect, hasHostView: true) == .card`, `hasHostView: false → .sheet`. |

Round-1 non-defects: the 1×1 rect is a valid `UIPopoverPresentationController.sourceRect`; backward compat preserved (`point` defaults nil); Rule 51 = restore-to-designed.

## Round 2 (verify) — CLEAN

Codex confirmed: the `hostViewProvider` captures the SAME `@State highlightAdapter`
instance that's `attach`ed to the live navigator (`ReadiumEPUBHost+Body:148` →
`ReadiumNavigatorRepresentable:110`), so `hostView` is non-nil during a tap; the
`as? UIViewController` cast is safe; the weak capture avoids a retain cycle; the
coordinate space is internally consistent (host == navigator view). The only
residual (activation before `attach` / after `detach` → nil host → sheet) is
by design.

## Verdict

`ship-as-is` — zero open Critical/High/Medium after round 2. The end-to-end
anchored-card render on a Readium decoration tap is the same hard-CU-free
verification as #302 (webview decoration), so this merges
`awaiting-device-verification`.
