---
branch: feat/feature-60-wi-7c3-txt-chunked-popover
threadId: 019e2ed2-a117-7653-84e2-4466013d7717
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7c3 TXT chunked bridge swap

## Round 1 — 2 Lows

### Low #1 — `TXTBridgeShared.buildReaderEditMenu` is dead after WI-7c3
- **`vreader/Views/Reader/TXTBridgeShared.swift:51`** | Low
  After WI-7c3 removes the chunked bridge caller, no production
  call sites remain. The function and its AI-availability branch
  are unexercised stale code.

**Resolution**: Accepted with rationale, deferred to follow-up. The
helper itself is dead in production, but `TXTBridgeSharedTests.swift`
still has 3 tests that exercise it directly
(`buildReaderEditMenuIncludesTranslateWhenAvailable`, `…
OmitsTranslateWhenAIUnavailable`, `… PassesThroughSuggestedActions
ForEmptyRange`). Removing the helper requires removing those tests
too — widens WI-7c3's diff from "bridge swap + contract tests" into
unrelated cleanup. MD doesn't use editMenuForTextIn at all, so
WI-7c4 won't naturally retire the helper either; this needs a
dedicated cleanup WI (or absorption into WI-7c5 if EPUB doesn't use
it). Codex round 2 accepted: "I would keep it as an explicit
follow-up cleanup item unless you want this PR to absorb that extra
diff."

### Low #2 — negative tag crash class
- **`vreader/Views/Reader/TXTChunkedReaderBridge.swift:513,548`** | Low
  The defensive "out-of-range tag falls back to 0" check only
  handled `tag >= count`. A negative `textView.tag` would still
  subscript `chunkStartOffsets` with a negative index and crash —
  in both `textViewDidChangeSelection` (pre-existing, line 513)
  and the new `editMenuForTextIn` post (line 548).

**Resolution**: Fixed both sites with the clamped check
`(chunkIndex >= 0 && chunkIndex < chunkStartOffsets.count) ? chunkStartOffsets[chunkIndex] : 0`. Pinned via a new
`negativeTag` regression test (chunk-index = -1 falls back to offset
0 without crashing). Codex round 2 accepted the line-513 sibling fix
as reasonable scope: "It is the same bug class in the same coordinator
and keeps `textViewDidChangeSelection` and `editMenuForTextIn`
behavior symmetric."

## Round 2 — clean

Codex verified: "No new findings. The negative-tag fix is correct
end-to-end... The chunked-TXT swap still matches the WI-7c2 producer
contract, and the added defensive clamp does not alter normal
runtime behavior where `cellForRowAt` assigns non-negative tags."

## Verdict statement

**ship-as-is** after round 1 (1 Low fixed, 1 Low deferred with
rationale). Round 2 clean.

All 8 audit dimensions clean:
1. Correctness — chunked-TXT swap matches WI-7c2 producer contract; chunk-offset translation preserved via the existing `TXTBridgeShared.postSelectionNotification`'s `chunkOffset:` parameter.
2. Edge cases — high-side overflow (covered), zero-offset chunk (covered), zero-length range (covered), negative tag (now covered).
3. Security — none (pure SwiftUI/NotificationCenter).
4. Duplicate code — pattern intentionally mirrors WI-7c2 with the chunk-offset extra step. Codex confirmed it's not worth extracting a shared helper given the divergence.
5. Dead code — `buildReaderEditMenu` is now dead in production; deferred cleanup item.
6. Shortcuts / patches — none.
7. VReader compliance — `@MainActor` correctness preserved (coordinator method is `UITextViewDelegate`-implicit), Swift 6 satisfied, `TXTChunkedReaderBridge.swift` was already >300 lines pre-existing; +29 here doesn't change that.
8. Bridge safety — `TXTBridgeShared.postSelectionNotification` handles UTF-16 + bounds for chunked NSRange via the chunkOffset translation.

## Test results

- 6 `TXTChunkedReaderBridgeEditMenuTests`: empty UIMenu return, popover-request post with chunk offset (200→206-211), chunk-zero correctness, zero-length no-post, out-of-range tag fallback, negative tag fallback. All pass.

Full vreaderTests run pending; expected to be clean modulo the 2 pre-existing parallel-execution `ReplacementTransformTests` flakes documented in WI-7c2's audit log.

## Strengths called out by Codex

- The swap is correct against the WI-7c2 pattern: `editMenuForTextIn` now posts `.readerSelectionPopoverRequested` and suppresses the UIKit menu exactly as planned.
- The chunk-offset math matches the legacy path because it still routes through `TXTBridgeShared.postSelectionNotification`, preserving the same UTF-16 bounds validation and global-range construction.
- The container-side wiring is already in place (WI-7c2 attached the presenter to `TXTReaderContainerView`), so no extra integration work missing.
- The contract tests cover the key slices: empty-menu suppression, chunk-offset translation, zero-offset, zero-length no-post, out-of-range and negative tag fallbacks.
- Cell reuse / scroll drift: `cellForRowAt` reassigns `textView.tag` on every dequeue before the cell is interactive, so no realistic tag/offset drift regression.

## Follow-up items

1. **`buildReaderEditMenu` cleanup**: now dead in production. Remove the helper from `TXTBridgeShared.swift` + the 3 tests in `TXTBridgeSharedTests.swift` in a dedicated cleanup WI (or fold into WI-7c5 if EPUB doesn't introduce a new caller).
2. **`applyHighlight` / `clearHighlight` negative-tag check** (line 604 area, in `TXTChunkedHighlightHelper.swift`): same bug class, different defensive shape (uses `guard ... else { return }`). Not addressed here; could be a small follow-up if it becomes a real concern.
