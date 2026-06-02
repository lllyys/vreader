---
branch: fix/issue-1429-ai-tab-picker-contrast
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, /tmp/fix1429-audit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Gate-4 Codex audit — Bug #315 / #1429 (AI panel tab picker contrast)

Independent audit (Codex gpt-5.4, high, read-only) of the diff replacing the AI
panel's system `Picker(.segmented)` with the landed `ThemedSegmentedPicker`
(#298/#1329 — controlTrack trough + per-theme legible pill). One round.

**Auditor: no functional issues.** Options mapping preserves the tab/value
contract; `selection: $selectedTab` still drives the `switch selectedTab` body;
the `aiReaderTabPicker` a11y id is preserved (and stronger — written directly on
the backing `UISegmentedControl`); padding unchanged; Rule-51-safe reuse.

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `AIReaderPanel.swift:126` | Low | The control swap has no in-tree regression test that `aiReaderTabPicker` resolves + tapping each segment switches the tab body. | **ACCEPTED (device-verified).** This is a view-recolor reusing a component whose contrast is already pinned (`ReaderSettingsPanelContrastTests.controlTrackReadsOverCreamPanel`, #298); the swap correctness is audit-confirmed + compile-verified; tab-switch + legibility is exercised in Gate-5 device verification. A dedicated AI-sheet XCUITest (needs `--enable-ai` + navigation) is disproportionate for a Low on a recolor; the device pass covers it. |

## Verdict

`ship-as-is` — no functional issues; the lone Low is a recolor test-coverage note
resolved by the existing #298 component contrast test + Gate-5 device verification.
