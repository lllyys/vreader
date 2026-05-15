---
branch: fix/issue-740-txt-chapter-tap-highlight
threadId: 019e2d4d-451a-7bf3-bcef-ea3bcfb9f161
rounds: 1
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #202 / GH #740 (TXT chapter-mode tap-on-highlight)

## Summary

Bug #202: in chapter mode, `TXTReaderContainerView.chapterReaderContent` was missing three of the WI-2/WI-2b parameters that the small-file path (`readerContent`) and chunked path (`chunkedReaderContent`) both pass to `TXTTextViewBridge`:
- `persistedHighlightLookup`
- `highlightActionPresenter`
- `onHighlightTapAction`

Without these, the bridge's `persistedHighlightLookup` defaulted to `[]`, so the coordinator's `handleContentTap` always missed the hit-test and fell through to `TXTBridgeShared.postContentTappedNotification()` (chrome-toggle). User-visible: tap on a yellow-highlighted word in chapter mode toggled chrome instead of opening the inline edit/delete menu — Feature #53 acceptance criterion (a)+(b) failed for TXT chapter mode.

## Fix

1. New pure-function helper `TXTChapterHighlightHelper.lookupForChapter(chapterIndex:chapters:globalLookup:)` — UUID-preserving sibling of the existing `highlightsForChapter`. Translates global lookup entries to chapter-local; clips spanning entries; drops outside-chapter entries; preserves UUIDs through `compactMap`.
2. `chapterReaderContent` computes the chapter-local lookup via the new helper and threads the same `highlightActionPresenter: UIKitHighlightActionPresenter()` + `onHighlightTapAction` closure the other two paths use.

## Round 1 Findings

`no findings`. Codex confirmed:

- Lookup translation semantics match `highlightsForChapter` exactly (half-open chapter bounds, clip-to-boundary, filter-outside). Start-boundary inclusion and end-boundary exclusion correct.
- Edge cases covered (empty input, single-element, multi-element interleaved, exact start/end boundary, zero-length highlight, out-of-bounds chapter, negative `globalStartUTF16`).
- UUID preservation correct (`compactMap` preserves entry order; `entry.id` copied unchanged).
- The chapter-path `onHighlightTapAction` closure (`{ [highlightCoordinator] action, id in await highlightCoordinator?.handleTapAction(action, highlightID: id) }`) matches the other two call sites exactly. No new concurrency concerns: the callback is `@MainActor async`, and `[highlightCoordinator]` capture is consistent with existing wiring.
- Source-check tests in `TXTReaderContainerHighlightCoordinatorWiringTests` are brittle by design (string occurrence count, ≥ 3) but acceptably so — the tradeoff for pinning the exact 3-path wiring.
- Swift 6 isolation clean — new helper is pure and nonisolated; the chapter view path stays on the view's MainActor context; no extra actor hops.
- `MDReaderContainerView` does not have a chapter-mode path. Its only `TXTTextViewBridge` call already passes all three parameters at `MDReaderContainerView.swift:321`, so the same bug does not appear there.

## Optional cleanup (deferred, not findings)

- The duplication between `highlightsForChapter` and `lookupForChapter` is small (~10 lines of clipping math). Refactoring into a shared private clipping helper is acceptable cleanup but not required for this fix.
- A stronger UUID regression guard could test two overlapping translated entries to verify the post-translation lookup order makes the "last-added wins" rule in `TextHighlightHitTester` work correctly. The existing 6th test pins simple order preservation.

## Test gate

- 6 new helper tests in `TXTChapterHighlightHelperTests`: all green.
- 3 new source-check wiring tests in `TXTReaderContainerHighlightCoordinatorWiringTests`: all green (≥ 3 occurrences for each of `highlightActionPresenter:`, `onHighlightTapAction: { [highlightCoordinator] action, id in`, `persistedHighlightLookup:`).
- Full `vreaderTests` suite: only 2 pre-existing failures remain (`BookFormatAZW3Tests.azw3 supports tts` and `azw3 capabilities match EPUB simple capabilities` — tracked as Bug #200 / GH #737).

## Pre-FIXED device verify (iPhone 17 Pro Sim iOS 26.5, v3.23.2 with fix patched in)

Reset → seed war-and-peace TXT → open → advance to Chapter 1 body → long-press "Prince" → tap Highlight → "Prince" highlighted yellow + snapshot.highlightCount = 1.

**Pre-fix behavior** (verified earlier today in PR #741 verify-cron): tap on yellow "Prince" toggled chrome OFF — chrome-toggle won the gesture race.

**Post-fix behavior** (this iteration): tap on yellow "Prince" did NOT toggle chrome (it stayed ON), confirming the hit-test path is firing and the `return` early-exit is suppressing the fall-through to `TXTBridgeShared.postContentTappedNotification()`. Tap on non-highlight text (still in chapter mode) correctly toggled chrome, confirming criterion (d) "tapping non-highlighted text preserves existing scroll/chrome-toggle behavior" remains intact.

Visual inline-menu appearance was inconclusive in CU screenshots (timing artifact + iOS 26.5 `UIEditMenuInteraction` popover quirks), but the wiring is identical to the small-file path which previously passed criterion (a) in adjacent verification iterations. Evidence: `dev-docs/verification/artifacts/bug-202-prefixed-tap-no-chrome-toggle-20260516.png`.

## Verdict

`ship-as-is`. Mark `awaiting-device-verification` for the menu-appearance portion of acceptance criterion (a); the chrome-toggle suppression is empirically confirmed.
