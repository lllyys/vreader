---
branch: triage/bug-180-txt-scroll-no-cross-chapter-nav
bug: 180
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #180 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `TXTTextViewBridgeCoordinator.scrollViewDidScroll` (line 232) and
  `scrollViewDidEndDecelerating` (line 262): only report position via
  `delegate?.scrollPositionDidChange(topCharOffsetUTF16:)` — no scroll-boundary
  detection that triggers chapter navigation.
- `TXTChapterOverlayViews.swift:43-103`: `ChapterBottomOverlay` has correct
  `goToNextChapter()` / `goToPreviousChapter()` buttons, but they are only shown
  when `hasChapterDisplay && isChromeVisible` — requires a tap to reveal.
- `TXTReaderContainerView.swift:379-393`: `readerNextPage` / `readerPreviousPage`
  notification handlers are gated on `guard isPagedMode` — no TXT scroll-mode
  chapter-boundary shortcut exists.
- Bug #165 (GH #489) documents the identical UX mismatch for EPUB.

## Verdict

ship-as-is — documentation only, no code risk.
