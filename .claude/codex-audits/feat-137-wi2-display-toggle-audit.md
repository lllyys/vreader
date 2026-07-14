---
branch: feat/137-wi2-display-toggle
threadId: 019f616f-3422-7860-85d7-d33cb37ce386
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #137 WI-2 (Display-sheet Layout toggle + onLayout wiring)

**Auditor:** Codex gpt-5.5 / reasoning=high (rule 53 `scripts/run-codex.sh`, stdin-isolated).
**Scope:** the designed Layout (Paged/Scroll) segmented control added to
`ReaderSettingsSheet.kt` (`LayoutSegmentedToggle` + `LayoutGlyph`, placed between
Theme and Font) + `onLayout` threading to `ReaderSettingsStore.setLayout` in the two
hosts that present the sheet (`TxtReaderActivity.kt`, `ReaderActivity.kt`), plus the
connected test `ReaderSettingsSheetUiTest.kt`.

## Files reviewed
- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheetUiTest.kt`

## Findings

| Severity | Count |
| --- | --- |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

## Auditor summary (verbatim highlights)

- `LayoutSegmentedToggle` is placed between Theme and Font, matches the designed
  Paged/Scroll segmented control and glyph geometry from `vreader-panels.jsx`
  (`:112` control, `:197` `LayoutGlyph`), and exposes `selected` semantics on the
  active segment.
- Callback threading in both hosts mirrors Theme exactly: `nextSeq()` is stamped
  synchronously in the UI callback, then `store.setLayout(v, o)` is launched
  fire-and-forget on `container.appScope` in both `TxtReaderActivity.kt` and
  `ReaderActivity.kt`. `ReaderSettingsStore` already has per-field latest-wins
  handling for `LAYOUT` (WI-1).
- The connected UI test covers rendering, callbacks for both segments, and selected
  semantics for default Scroll and explicit Paged.

## Verdict

**ship-as-is** — zero Critical/High/Medium/Low findings. 1 round.

## Test gate (independently run by the lane)
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:connectedDebugAndroidTest`
`ReaderSettingsSheetUiTest`, 9/9 tests passed (4 pre-existing #129 + 5 new WI-2) on
emulator-5554.
