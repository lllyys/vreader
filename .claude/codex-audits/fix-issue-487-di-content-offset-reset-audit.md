---
branch: fix/issue-487-di-content-offset-reset
threadId: 019e1b6c-24f2-7f31-8043-d4b9cc9deef6
rounds: 2
final_verdict: ship-as-is
date: 2026-05-12
---

## Round 1 Findings

| file:line | severity | issue | fix |
|-----------|----------|-------|-----|
| EPUBWebViewBridgeCoordinator.swift:216 | High | 0.05s delayed contentOffset reset has no load-guard — stale resets from rapid chapter navigation could fire on the wrong page | Added `let expectedURL = currentURL` capture + `guard self.currentURL == expectedURL` in closure — stale closures are now no-ops |
| EPUBWebViewBridgeCoordinator.swift:214 | Medium | Same-URL `fraction=0.0` path in `updateUIView` calls `scrollToFractionJS(0.0)` → `window.scrollTo(0,0)` → UIScrollView contentOffset.y=0, undoing the safe-area offset | Added `fraction <= 0` gate: calls `applyInitialContentOffset` (native) instead of JS when fraction ≤ 0; JS path only for fraction > 0 |
| EPUBWebViewBridgeTests.swift:296 | Low | 5 new tests only verify the pure seam; coordinator-level async/timing tests not present | Accepted — WKWebView harness required for coordinator tests; same documented coverage-gap rationale as applySafeAreaTopInset and applyScrollViewBackground. Device verification (Phase 9) is the wiring lock. |

## Round 2 Findings

| file:line | severity | issue | fix |
|-----------|----------|-------|-----|
| EPUBWebViewBridgeCoordinator.swift:204 | Medium | Positive-fraction 0.15s delayed JS scroll has no URL guard — same stale-load hazard as chapter-top branch | Added `let expectedURL = currentURL` + `guard self?.currentURL == expectedURL` to fraction > 0 branch as well |

Round 2 re-audit: **zero new findings**.

## Summary Verdict

Both delayed branches in `webView(_:didFinish:)` are now guarded against stale chapter loads. The `fraction <= 0` same-URL branch uses native `applyInitialContentOffset` instead of `window.scrollTo(0,0)`. The new `applyInitialContentOffset` seam is tested by 5 unit tests covering the contentOffset write, x-reset, zero-inset no-op, contentInset preservation, and negative clamp. Verdict: **ship-as-is**.

## Manual Audit Evidence (supplement — Low accepted)

- Files read: EPUBWebViewBridgeCoordinator.swift, EPUBWebViewBridgeJS.swift, EPUBWebViewBridge.swift, EPUBWebViewBridgeTests.swift
- Symbols verified: `applyInitialContentOffset`, `applySafeAreaTopInset`, `currentURL`, `pendingScrollFraction`, `safeAreaTopInset`, `UIScrollView.contentOffset`
- Edge cases checked: fraction=nil, fraction=0.0, fraction=0.5, safeAreaTopInset=0, rapid chapter navigation (URL guard), paged mode (not affected — separate branch)
- Risks accepted: coordinator async/timing not unit-tested (WKWebView harness out of scope; device verification is the lock)
