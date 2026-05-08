---
branch: fix/issue-433-search-tap-navigation-anchor
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-08
---

## Why manual fallback

Codex MCP unreachable this iteration — `mcp__plugin_codex-toolkit_codex__codex`
ping returned `stream disconnected before completion: error sending request for
url (https://chatgpt.com/backend-api/codex/responses)`. Manual mini-audit per
`/fix-issue` Phase 4f + `.claude/rules/47-feature-workflow.md` Manual Audit
Evidence section.

## Manual audit evidence

### Files read

- `vreader/Services/TXT/TXTOffsetMapper.swift` (modified — added
  `scrollOffsetForVisibleMatch`)
- `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift` (modified —
  added `scrollToMatchedOffset`)
- `vreader/Views/Reader/TXTTextViewBridge.swift` (modified — wired
  `scrollToOffset` path through the new method)
- `vreaderTests/Services/TXT/TXTOffsetMapperTests.swift` (modified — 7 new tests)
- `vreader/Views/Reader/TXTReaderContainerView.swift` (read-only — confirmed
  the chapterReaderContent / readerContent paths both pass `uiState.scrollToOffset`
  to the bridge identically)
- `vreader/Views/Reader/ReaderNotificationModifier.swift` (read-only — confirmed
  the search-tap flow sets `uiState.scrollToOffset` from the locator's
  `charOffsetUTF16` or `charRangeStartUTF16`, plus `highlightRange`)
- `vreader/Services/Search/SearchHitToLocatorResolver.swift` (read-only —
  confirmed TXT search results emit a Locator with both `charOffsetUTF16` and
  `charRangeStartUTF16` set to `globalStart = segBase + matchStartOffsetUTF16`)
- `vreader/Services/TXT/TXTService.swift` (read-only — confirmed synthetic
  single-chapter case for the position-test fixture)
- `vreader/App/TestSeeder.swift` (read-only — confirmed
  `--seed-position-test` produces 100 paragraphs of stable shape)

### Symbols / signatures verified

- `NSLayoutManager.lineFragmentRect(forGlyphAt:effectiveRange:) -> CGRect`
  — exists in UIKit. Returns text-container coordinates.
- `UIScrollView.setContentOffset(_:animated:)` — automatic clamping to
  `[0, contentSize.height - bounds.height]` is documented behavior.
- `UITextView.scrollRangeToVisible(_:)` — minimum-scroll-to-make-range-visible
  semantics; no-op if range already visible.
- `UITextView.textContainerInset.top` — UIEdgeInsets, exists.
- `NSRange(location: NSNotFound)` guard pattern — matches existing usage in
  the codebase (e.g., TXTOffsetMapper.selectionToUTF16Range).

### Edge cases checked

- **charOffset out of range**: `min(max(charOffset, 0), textLength)` clamp
  matches `attemptScrollRestore`'s pattern.
- **textView.bounds.width == 0** (early-layout race): retries up to
  `Self.maxRestoreRetries = 5` with 0.1s delay — same pattern as
  `attemptScrollRestore`. Note: `restoreRetryCount` is shared; by the time a
  search-tap happens, the textView is already laid out so this path is rarely
  hit. Theoretical concern — not a real-world issue.
- **highlightRange == nil**: guard short-circuits — no `scrollRangeToVisible`
  call. Search-tap nav always supplies a highlightRange (per
  `ReaderNotificationModifier`); bookmarks/TOC nav don't.
- **highlightRange invalid** (NSNotFound, negative location, beyond
  textLength): guard at the call site validates all three.
- **headroomFraction negative or > 0.9**: clamped to `[0, 0.9]` inside the
  helper. Test coverage: `scrollOffsetForVisibleMatch_clampsHeadroomFractionAtUpperBound`,
  `scrollOffsetForVisibleMatch_clampsNegativeHeadroomFractionAtZero`.
- **Match near document start** (lineY < viewport*headroom - topInset):
  `max(0, ...)` clamp returns 0, line lands in the upper portion of the
  viewport. Test coverage: `scrollOffsetForVisibleMatch_nearDocumentStart_clampsToZero`,
  `scrollOffsetForVisibleMatch_documentStart_clampsToZero`.
- **Match near document end**: pre-clamp scrollY may still exceed
  `contentSize.height - bounds.height`; iOS's setContentOffset clamps in
  that case. The headroom helps reduce — not eliminate — clamping; the
  `scrollRangeToVisible` safety net is the second line of defense.
- **Unicode/CJK in match text**: `lineFragmentRect.minY` is in y-axis CGFloat,
  invariant under text encoding. The `glyphRange.location` from
  `glyphRange(forCharacterRange:NSRange(location: clampedOffset, length: 0))`
  works for surrogate pairs because TextKit uses UTF-16 throughout.
- **Empty document**: textLength = 0 → clampedOffset = 0 → lineFragmentRect
  for offset 0 returns minY = 0 → headroom math returns 0. setContentOffset(0,0)
  is a no-op visually. Fine.

### Risks accepted

- **Restore retry counter shared between `attemptScrollRestore` and
  `scrollToMatchedOffset`** — if the counter is at max from a previous
  restore (theoretical: would require 5 consecutive bounds.width == 0
  failures during the saved-position restore), the search-tap retry won't
  fire. Practically unreachable — by the time the user opens search and
  taps a result, the textView is laid out (bounds.width > 0). **Severity:
  Low**. Accepted; not extracting per-method counters because that would
  add complexity for an unreachable path.

- **No `attemptScrollRestore`-style 0.05s second-pass retry in
  `scrollToMatchedOffset`** — saved-position restore uses a phase-1
  (t+0.15s) + phase-2 (t+0.2s) double-tap pattern to handle TextKit 1
  relayout storms during initial open. Search-tap navigation runs against
  an already-laid-out textView; the same race doesn't apply. The
  `scrollRangeToVisible` safety net handles any post-clamp drift.
  **Severity: Low**. Accepted.

### Tests added or intentionally deferred

**Added** (in `TXTOffsetMapperTests.swift`):
1. `scrollOffsetForVisibleMatch_middleOfDocument_appliesHeadroom` — typical case.
2. `scrollOffsetForVisibleMatch_nearDocumentStart_clampsToZero` — line at y=50.
3. `scrollOffsetForVisibleMatch_documentStart_clampsToZero` — line at y=0.
4. `scrollOffsetForVisibleMatch_zeroHeadroom_putsLineAtTopWithInset` —
   headroomFraction=0 puts line at top + inset (regression guard against
   accidentally always applying headroom even when caller asks for none).
5. `scrollOffsetForVisibleMatch_clampsHeadroomFractionAtUpperBound` —
   clamps fraction to 0.9 max.
6. `scrollOffsetForVisibleMatch_clampsNegativeHeadroomFractionAtZero` —
   clamps to 0.
7. `scrollOffsetForVisibleMatch_typicalSearchTapNearDocumentEnd_keepsMatchAboveBottom`
   — bug #153 repro shape (paragraph 100 of 100, lineY ≈ 17820).

**Intentionally deferred**:
- Behavioral test driving a real `UITextView` with a known fixture and asserting
  the matched line is in the visible region. UITextView in unit tests requires
  attaching to a window with non-zero bounds, which is fragile in headless
  unit-test runs. The pure-logic tests cover the math; the device repro
  (CU-driven this iteration) covers the integration.

## Per-round findings

### Round 1 (manual)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `TXTTextViewBridgeCoordinator.swift:scrollToMatchedOffset` | Low | `restoreRetryCount` shared with `attemptScrollRestore` — theoretical exhaustion | Accepted (unreachable in practice) |
| `TXTTextViewBridgeCoordinator.swift:scrollToMatchedOffset` | Low | No phase-2 retry like `attemptScrollRestore` | Accepted (`scrollRangeToVisible` safety net is sufficient; no relayout storm at this point) |

No Critical, High, or Medium findings.

## Summary verdict

**ship-as-is**. The fix is small (208 lines net, mostly tests and a pure-logic
helper), narrowly scoped to the search-tap navigation path (saved-position
restore is untouched), and verified end-to-end on iPhone 17 Pro Sim — the
matched line "Paragraph 100" is now fully visible after tapping the search
result, where previously it was pushed off-screen above the viewport.
