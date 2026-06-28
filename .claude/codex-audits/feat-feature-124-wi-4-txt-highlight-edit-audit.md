---
branch: feat/feature-124-wi-4-txt-highlight-edit
threadId: codex-exec-f124-wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #124 WI-4 (final) — TXT tap-to-edit / remove existing highlight

A tap on a TXT highlight opens the EDIT popover (recolor / note / remove). One combined
`awaitEachGesture` distinguishes a tap (edit) from a long-press-drag (new selection);
`rememberUpdatedState` keeps the stable `pointerInput` reading the latest `highlightsList`.

Files: `reader/TxtSelectionController.kt`, `reader/TxtReaderActivity.kt`, `TxtReaderActivityTest.kt`.

## Implementation bugs caught + fixed during testing (pre-audit)

- Two separate `pointerInput` detectors (drag + tap) **conflicted** over the down event → long-press broke. Fixed with ONE `awaitEachGesture`.
- The `pointerInput` (keyed on the stable controller) captured the **initial** `onTapAt` closure (empty `highlightsList`) → tap-to-edit never hit. Fixed with `rememberUpdatedState`.
- Test tapped the node's full-width center → landed past the left-aligned text at the line-end offset (exclusive). Fixed by tapping `percentOffset(0.15f, …)`.
- Tests share the real on-disk Room DB + same `fingerprintKey` (identical `sample.txt` content) → highlights accumulate. Fixed by clearing the book's highlights at the start of the count-asserting test.

## Round 1 — Codex findings

| # | file | severity | issue | resolution |
|---|---|---|---|---|
| 1 | TxtReaderActivity gesture | **High** | `awaitLongPressOrCancellation == null` was treated as a tap, but null also means cancellation (e.g. a scroll wins) → scrolling over a highlight could open the EDIT popover; `drag()`'s completion was ignored. | FIXED — only call `onTapAt` when `!down.isConsumed` (a scroll consumes the down; a real tap doesn't); finalize the selection only on a COMPLETED `drag()` (else `clear()`). |
| 2 | TxtSelectionController.resolveSourceOffset | Medium | reused `hitAt`'s nearest-chunk fallback → a tap in the margin/blank space could resolve to a nearby highlight and edit it. | FIXED — `hitAt(localPoint, allowNearest)`; `resolveSourceOffset` uses `allowNearest = false` (strict — must be inside a text chunk); drag keeps the nearest fallback. |

Codex confirmed the rest consistent: `rememberUpdatedState` fixes the stale closure; create/edit
context clearing is coherent; note/color/remove preserve edit state; hit-tester is half-open + newest-wins.

## Acceptance verification (emulator API 35)

- `tapExistingHighlight_opensEditPopover_andRemoveDeletesIt` — seed a highlight over a line → tap it → EDIT popover (Remove) → Remove deletes it (count 0).
- `longPressOnText_selectsWord_showsSelectionPopover` + `longPress_thenTapColor_createsAndPersistsHighlight` (WI-3) still green.
- `rendersWithSeededHighlight_drawsWash_noCrash` + `TxtHighlightConnectedTest` (WI-2) green.

## Verdict
**ship-as-is.** The full TXT create/edit/remove highlight lifecycle is implemented and verified
end-to-end on-device (the gesture is automatable via the Compose harness); both audit findings fixed.
