---
branch: fix/issue-482-tap-zone-no-op-native-mode
threadId: 019e0feb-faaf-7e73-ae64-ce5fdabb70ec
rounds: 2
final_verdict: ship-as-is
date: 2026-05-10
---

# Codex Audit — bug #162 / GH #482 (Tap Zones config no-op on native readers)

Cheap-path mitigation matching bug #156 / #158 capability-gate pattern, plus a runtime mode check and a dispatch-switch parity check. Hides the Tap Zones section in `ReaderSettingsPanel` whenever the configured zones would silently no-op.

## Round 1

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/ReaderSettingsPanel.swift:274` | Medium | Initial gate keyed off `(.unifiedReflow capability) AND (currentMode == .unified)`. That correctly hides the picker for TXT / PDF (no `.unifiedReflow`) and for capable formats in Native mode, but it left two runtime no-op paths visible: AZW3 in unified mode falls to `UnifiedPlaceholderView` (`ReaderUnifiedDispatch.swift:81-83`) without ever installing `.tapZoneOverlay`, and complex EPUB falls back to `nativeReaderView` (`ReaderUnifiedDispatch.swift:73-76`) for the same reason. The picker would still appear with no effect for those runtime paths. | **Fixed.** Added `var bookFormat: BookFormat? = nil` parameter to `ReaderSettingsPanel`. Updated gate signature to `shouldShowTapZonesSection(for: capabilities, format: bookFormat, currentMode: store.readingMode)`. Added private static helper `unifiedDispatchInstallsTapZoneOverlay(for: BookFormat) -> Bool` that mirrors the `ReaderUnifiedDispatch.unifiedReaderView` switch — true for `.txt`, `.md`, `.epub`; false for `.pdf`, `.azw3`. Production caller in `ReaderContainerView.swift:265-272` now passes `BookFormat(rawValue: book.format.lowercased())`. Complex-EPUB runtime fallback remains a documented limitation (gate sees the simple-EPUB capability set; threading `isComplexEPUB` runtime signal through is feature-class scope — same gap as `chineseConversionSupported`). |
| `vreaderTests/Views/Reader/ReaderSettingsPanelTapZonesGateTests.swift:62` | Low | Initial test suite locked in the same loose assumption — explicitly expected AZW3 to show Tap Zones in unified mode. | **Fixed.** Replaced with `gate_hidden_forAZW3_evenInUnifiedMode_dueToPlaceholderDispatch` and added 3 sibling parity tests covering the dispatch-switch dimension. Updated `gate_helperSemantics_complexEPUBStillShowsAtRuntime` to test the helper-explicit complex-EPUB caps case (returns false when explicit caps supplied; runtime-fallback gap stays documented in the bug row). |

## Round 2

Zero open findings. Codex acknowledged the remaining complex-EPUB runtime fallback as a pre-existing accepted limitation, not a new regression. Noted residual risk: future drift if `ReaderUnifiedDispatch` changes and this mirrored helper is not updated; the parity tests reduce but do not eliminate that risk.

## Summary verdict

`ship-as-is`. The fix correctly hides the Tap Zones picker in three classes of no-op situations:
1. Format lacks `.unifiedReflow` capability (PDF, TXT)
2. User is currently in Native mode (any format)
3. Format's unified dispatch path doesn't install `.tapZoneOverlay` (AZW3 placeholder; PDF excluded from switch)

15/15 gate tests pass (9 new TapZones + 6 ReadingMode regression-guard). Production sheet caller in `ReaderContainerView` updated to pass the new `bookFormat` parameter.

The same-shape-as-bug-#158 helper API and the explicit dispatch-mirror keep the cheap-path scope honest. Proper fix (per-renderer gesture wiring with TapZoneStore threaded into native bridges) remains feature-class scope per the bug row's option (b).
