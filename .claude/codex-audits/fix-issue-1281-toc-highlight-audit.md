---
branch: fix/issue-1281-toc-highlight
threadId: codex-exec-2026-05-31-bug288
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #288 / GH #1281 (TXT TOC current-chapter highlight stale + flash)

`codex exec --sandbox read-only`. **No findings.**

Fix: (1) `scrollToGlobalOffset` broadcasts the TARGET offset to the delegate so the
reader's `currentLocator` (TOC highlight + persisted position) deterministically
reflects the tapped chapter, independent of the late/throttled/#289-suppressed
`scrollViewDidScroll` callback that could resolve to the previous chapter. (2) TOC
row `onTap` reordered `onDismiss(); onNavigate(...)` so the sheet animates out before
the locator changes (no whole-list re-instantiation flash).

Auditor confirmations: no save-during-restore conflict (suppression still gates the
settling window; a post-window write is the correct restored position, not a
transient); no feedback loop (dynamic nav gated by `lastScrollToOffset`); early
returns correctly don't broadcast; reorder safe (independent closures, no
cancellation); reopen facet addressed (target persists); flash facet materially
addressed.

Tests: `tocNavBroadcastsTargetOffset` (RED pre-fix — only the flaky callback
reported) + `tocNavNoBroadcastOnEmptyMetadata`, via a Coordinator + mock delegate.

## Verdict: ship-as-is.
