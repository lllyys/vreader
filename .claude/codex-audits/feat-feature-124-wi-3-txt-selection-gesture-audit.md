---
branch: feat/feature-124-wi-3-txt-selection-gesture
threadId: codex-exec-f124-wi3
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #124 WI-3 (behavioral) — TXT custom selection gesture + popover create

`TxtSelectionController` (chunk layout/coords registry; pointer→window→chunk-local→source offset;
long-press `getWordBoundary`; drag extend anchored on the initial word; selection accent;
`selectionEndAnchorWindow`). `TxtBody` installs `detectDragGesturesAfterLongPress` + the selection
accent (TXT only). `TxtReaderActivity` hosts the `SelectionPopover` overlay + create/copy/share.

## Round 1 — findings

| # | file | severity | issue | resolution |
|---|---|---|---|---|
| 1 | TxtSelectionController.extendTo | Medium | Backward/cross-anchor drag used the moving endpoint as the anchor → dropped the initial word / collapsed. | FIXED — store `anchorRange` (the initial word) in `beginAt`; `extendTo` grows relative to the FIXED anchor (before→grow start, after→grow end, inside→keep word). The anchor word is never dropped. |
| 2 | TxtSelectionController.beginAt | Medium | Reconstructed the chunk-local offset via `chunkBaseFor(sourceOff)` → at a chunk boundary it resolved to the next chunk while `layout` was the hit chunk (selection shifted). | FIXED — `hitAt` now returns the hit chunk index + rendered offset + source; `beginAt` uses that SAME chunk for `getWordBoundary` + base. `chunkBaseFor` removed. |
| 3 | TxtReaderActivity.createTxtHighlight | Medium | `note` param was ignored — a TXT note save persisted a plain highlight. | FIXED — pass `note = note` to `addHighlight`. |
| 4 | TxtReaderActivity popover positioning | Low | Only left/top clamped → a near-edge selection could push the popover off-screen. | FIXED — capture `boxSize`; clamp X into `[margin, boxW-popW-margin]`; flip above when below overflows. |

Codex checked clean: the window-space coordinate round-trip is the right model; chunk unregister is
tied to lazy disposal with a stable `key`; TXT `requireSameBook` holds from the locator identity
triple; MD can't reach the gesture (its controller is null).

## Slice verification (emulator API 35)

- `TxtReaderActivityTest.longPressOnText_selectsWord_showsSelectionPopover` — a **real long-press** gesture (via the Compose test harness — automatable, unlike #123's WebView) selects a word + shows the popover.
- `TxtReaderActivityTest.longPress_thenTapColor_createsAndPersistsHighlight` — **full create E2E**: long-press → tap a color → highlight persists to Room.
- `rendersWithSeededHighlight_drawsWash_noCrash` + `TxtHighlightConnectedTest` (WI-2) still green.

## Verdict
**ship-as-is.** The custom TXT selection gesture + popover create is implemented and verified
end-to-end on-device (the gesture itself is automatable); all audit findings fixed.
