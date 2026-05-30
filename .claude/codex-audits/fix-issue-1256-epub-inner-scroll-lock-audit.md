---
branch: fix/issue-1256-epub-inner-scroll-lock
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Manual audit — Bug #279 (REOPENED) / GH #1256 (EPUB inner scroller pan/zoom)

CSS-only gesture lock on a generated bootstrap document; manual-fallback per rule 47.

## Manual Audit Evidence

- **Files read**: `EPUBContinuousScrollJS.bootstrapDocumentHTML` (the default
  continuous-scroll path's WKWebView document), `FoliateSpikeView.swift:268`
  (the `user-scalable=no` pattern mirrored), the REOPENED note (the prior #1269
  fix locked only the OUTER WKWebView scrollView; the INNER DOM
  `#vreader-scroll-root` was unconstrained).
- **Change**: on `#vreader-scroll-root` + `html, body` added `touch-action: pan-y`
  (blocks horizontal pan AND pinch-zoom on the inner scroller) + `overflow-x: hidden`
  (clips horizontal overflow); capped media width (`img/video/table/pre { max-width:
  100% }`) so wide content can't force a horizontal scroll; added `user-scalable=no`
  to the bootstrap viewport meta (matches Foliate). Defense-in-depth with the
  existing `maximum-scale=1` + the #1269 outer scrollView lock.
- **Edge cases checked**: paged mode is unaffected (continuous bootstrap not used;
  `isScrollEnabled=false` there). Vertical scroll preserved (`pan-y` allows it +
  `overflow-y: auto`). `box-sizing: border-box` + `width:100%` keeps the column at
  viewport width. Theme CSS still injected after the lock rules (caller CSS can
  override colors but the lock is structural — a theme is unlikely to re-enable
  horizontal overflow, and `overflow-x: hidden` clips regardless).
- **Risks accepted**: `max-width: 100%` on media could letterbox an intentionally
  wide figure — acceptable vs. free horizontal pan; the design renders reflowable
  text, not fixed-layout. A theme that sets `overflow-x: visible` on the root could
  fight the lock, but `touch-action: pan-y` still blocks the gesture.
- **Tests**: `EPUBContinuousScrollJSTests.bootstrapInnerScrollLock` pins
  `touch-action: pan-y` + `overflow-x: hidden` + `max-width: 100%` + `maximum-scale=1`.

## Verdict: ship-as-is.
