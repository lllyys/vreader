---
branch: fix/issue-1561-epub-double-scroller
threadId: 019e9c6d-189e-7142-b9bd-2afc8a00fef3
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Codex audit — Bug #327 (GH #1561): EPUB double-scroller (Feature #85 regression)

Independent Codex audit (gpt-5.4, read-only) via `scripts/run-codex.sh`. `RUN-CODEX RESULT: SUCCEEDED`.

## Scope
`vreader/Views/Reader/EPUBWebViewBridge.swift` — disable the OUTER `WKWebView.scrollView`
in the legacy continuous-stitch path (`continuousScroll != nil`) so the inner
`#vreader-scroll-root` is the sole scroller, via a pure `outerScrollEnabled(isPaged:hasContinuousConfig:)`
helper used at both `makeUIView` and `updateUIView`.

## Findings

**No findings.** Codex verified:
- (a) **SAFE** — the inner `#vreader-scroll-root` (`overflow-y:auto; -webkit-overflow-scrolling:touch`)
  is a real iOS/WebKit scroll container that scrolls INDEPENDENTLY of the main `WKWebView.scrollView`
  on iOS 13+ (cited Apple Safari CSS docs + WebKit bugs 117059/292603). Disabling the outer scrollView
  removes the competing scroller, it does NOT break the inner one.
- (b) Gating correct — truth table: paged=false, continuous-stitch=false, legacy-single-chapter=true.
  Paged/Readium + non-continuous EPUB paths untouched (the container only passes `continuousScroll` when `!isPaged`).
- (c) `makeUIView` preserves prior paged behavior + adds the missing continuous case via the helper.
- (d) No bad interaction with `applyScrollLock` (outer-only) or safe-area handling.
- (e) `nonisolated static` helper correct (pure boolean, no actor state).

**Residual gap (Codex):** "tests cover the helper truth table but not the representable wiring or
real touch behavior. For this specific bug, device/simulator verification still matters." — matches
the conditional-skip device-verification test (synthetic XCUITest swipes cannot drive WKWebView
inner-overflow scroll on this host; a real finger / idb HID swipe can).

## Verdict
**ship-as-is.** Zero findings; the fix is confirmed safe + correctly gated.

## Tests
- `EPUBWebViewBridgeOuterScrollEnabledTests` (4 decision tests) GREEN; full `EPUBWebViewBridgeTests`
  suite GREEN (no regression).
- `Bug1561DoubleScrollerVerificationTests` — device-verification test; SKIPS on this synthetic-gesture
  harness (documented), asserts advancement on a physical-display device.
