---
branch: feat/feature-123-wi-3-epub-selection
threadId: codex-exec-f123-wi3
rounds: 2
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #123 WI-3 (behavioral) — EPUB selection → highlight + decoration render

Wires Readium's selection (`selectionActionModeCallback` + `currentSelection()`) →
the designed floating `SelectionPopover` → create highlight/note + `applyDecorations`
re-render on open. Readium 3.3.0 API confirmed via `javap` against the cached AAR.

Files: `annotations/{EpubAnnotationMapper,SelectionPopover,SelectionPopoverViewModel}.kt`,
`annotations/AnnotationAnchor.kt` (+ `Epub.readiumLocatorJSON`), `reader/ReaderHighlightController.kt`,
`reader/ReaderActivity.kt`; tests `EpubAnnotationMapperTest`/`SelectionPopoverViewModelTest` (JVM),
`SelectionPopoverUiTest`/`AnnotationsConnectedTest`/`ReaderActivityTest.seededHighlight…` (emulator).

## Round 1 — findings

| # | file | severity | issue | resolution |
|---|---|---|---|---|
| 1 | ReaderActivity selectionCallback | **High** | `onCreateActionMode` returned `false` → relied on the WebView selection surviving action-mode cancellation; untested live → flaky/dead risk. | FIXED — keep the mode alive (`return true`, cleared menu), read `currentSelection()` WHILE alive, set `pendingSelection` + show popover, then `mode.finish()`. No longer depends on cancellation order. + added `ReaderActivityTest.seededHighlight_appliesAsDecoration_onLiveNavigator` exercising the live navigator/WebView decoration-render path. |
| 2 | SelectionPopover / ReaderActivity | Medium | `Translate` was a dead no-op user-visible action (plan says OUT). | FIXED — removed the Translate action/icon/handler (+ test); commented it lands with #119. |
| 3 | ReaderActivity PopoverOverlay | Medium | positioning ignored `anchorX`, no viewport clamp / above-below flip. | FIXED — `BoxWithConstraints`: center on `anchorX`, clamp horizontally, flip above when overflowing the bottom. |
| 4 | ReaderActivity overlay | Low | no outside-tap dismissal. | FIXED — full-screen no-indication scrim → `clearSelectionAndDismiss()`. |

## Round 2 — verify

Findings 1–4 confirmed resolved. One new Medium: `appliedHighlightCount` was set to
`highlights.size` (rows observed) rather than decorations actually built. **FIXED** —
`ReaderHighlightController.applyHighlights` now returns the built-decoration count;
the activity assigns that, so the live test proves ≥1 decoration was genuinely
built from the seeded highlight's reconstructed Readium locator. Zero open
Critical/High/Medium.

## Slice verification (Gate-5a)

- **On-device (emulator API 35):** popover renders + every action fires + note compose (`SelectionPopoverUiTest` ×4); persist→reload→Readium-locator-reconstruct + dedupe through real Room (`AnnotationsConnectedTest` ×2); **a stored highlight builds + applies as a decoration on the LIVE EpubNavigatorFragment/WebView** (`ReaderActivityTest.seededHighlight…`). JVM: mapper + popover VM.
- **Deferred to WI-4 final acceptance:** the raw finger long-press-drag that triggers `onCreateActionMode` (not headlessly automatable). Everything downstream of the gesture (currentSelection→popover→create→persist→render) is verified; the trigger uses the documented Readium `selectionActionModeCallback` keep-alive pattern.

## Verdict
**ship-as-is.** The Readium selection/decoration integration is implemented against
the confirmed 3.3.0 API, the create + reopen-render substance is verified on the live
navigator, and all audit findings are fixed.
