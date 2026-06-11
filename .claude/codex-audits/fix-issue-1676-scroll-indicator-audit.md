---
branch: fix/issue-1676-scroll-indicator
threadId: 019eb6b5-a90c-7940-b4ac-c86840865a20
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Bug #348 — Codex audit

Fix: `ReaderScrollIndicatorPolicy` (shared hide + recursive traversal)
applied across every reading surface (TXT plain/chunked, legacy EPUB
native + the stitched root's CSS overlay scrollbar, Foliate, Readium
attach + per-update re-apply for lazy spine webviews, PDFView).
Runner: `scripts/run-codex.sh`. Round-2 session: `019eb6bd-dbb4-7482-b8c7-2fda112b9015`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| The legacy EPUB safe-area seam still maintained `verticalScrollIndicatorInsets` (dead once the indicator is hidden) and its test pinned the old behavior | Low | **Fixed** — the write removed with a bug-348 note; the test now pins that indicator insets are NOT written while `contentInset.top` is preserved. |

Round 1 explicitly confirmed: MD paged is not a missed scroller
(non-scrollable UITextView), the chunked path has no other reader
scroller, the Readium per-update re-apply is sufficient (every
locationDidChange forces an update), the CSS is scoped to the stitched
root with no layout-width side effect, traversals don't reach non-reader
surfaces.

## Round 2 (verify)

Clean — the dead write removed everywhere, the updated pin matches.

## Verdict

ship-as-is. Policy/CSS/safe-area suites green; live-DOM verification on
device: the stitched root computes `scrollbar-width: none` with the
`::-webkit-scrollbar` rule present.
