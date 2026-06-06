---
branch: fix/issue-1546-selection-tint
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Gate-4 audit — Bug #324 (GH #1546): theme-accent selection tint for TXT/MD

The TXT/MD `UITextView`s never set `tintColor`, so selection (caret, grab handles,
selection highlight) fell to the system default blue, clashing with the warm
sepia/paper themes. `TXTViewConfig.accentColor` was already populated from
`ReaderThemeV2.accentColor` (`ReaderSettingsStore.txtViewConfig:279`); only the
`tintColor` assignment was missing.

## Manual fallback — why
The independent Codex runner wedged repeatedly this session (rule-53 0%-CPU ghost).
Per rule 47, manual fallback for this trivial, fully-tested theming fix.

## Manual Audit Evidence
- **Fix**: `applyTintColor(to:config:)` (guarded on change) applied where each TXT/MD
  UITextView is configured: `TXTTextViewBridge.makeUIView` + `applySourceText`
  (config/theme-change path); `TXTChunkedReaderBridge.cellForRowAt` (theme change
  reloads the table → per-cell refresh); `NativeTextPagedView.applyConfig` (runs on
  every theme change). MD routes through the same shared bridges (covered transitively).
- **No new UI** (Rule-51 N/A — parity theming with the existing accent token). Pure
  `tintColor` assignment from an already-wired config value; no behavior change beyond
  the selection chrome color.
- **Tests**: new `TXTSelectionTintTests` (6) — apply in makeUIView + refresh on a
  second config with a different accent, across the scroll / chunked / paged paths;
  related suites (`NativeTextPagedViewSideTapTests`, `HighlightableTextViewTests`,
  `TXTTextViewBridgeSafeAreaInsetTests`) green (no regression).
- EPUB/AZW3 select via WKWebView `::selection` CSS (a separate path, out of scope —
  matches the bug row). Swift 6 / @MainActor correct (bridges are MainActor).

`ship-as-is`.
