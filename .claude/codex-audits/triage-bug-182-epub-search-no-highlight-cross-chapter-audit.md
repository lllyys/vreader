---
branch: triage/bug-182-epub-search-no-highlight-cross-chapter
bug: 182
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #182 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `EPUBWebViewBridge.swift` `updateUIView` (line ~242-341): URL-change block calls
  `webView.loadFileURL()` (async), then the separate `pendingJS` block immediately calls
  `evaluateJavaScript(pendingJS)` before the new page's DOM is ready.
- `window.find()` in `searchHighlightJS` (EPUBHighlightBridge.swift:224) runs on the
  old/loading page → returns false → no span injected.
- `onPendingJSCompleted()` then clears `pendingHighlightJS` so `webView(_:didFinish:)` 
  never sees it.
- `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)` (line 169): `onPageDidFinishLoad`
  calls only `restoreHighlightsOnLoad` (persisted `HighlightRecord`s), not search highlight.
- Same-chapter searches (no URL change) work because `pendingJS` evaluates on the already-
  loaded page where `window.find()` succeeds.
- Contrast: `pendingScrollFraction` stored in coordinator, consumed in `didFinish` — the
  fix pattern is identical.

## Verdict

ship-as-is — documentation only, no code risk.
