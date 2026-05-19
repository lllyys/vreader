---
branch: feat/feature-54-wi-4-remove-picker-ui
threadId: 019e3dd7-e727-7761-bf29-636beefbfe70
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — feature #54 WI-4 (remove Reading Mode + Tap Zones from settings panel)

## Scope

`git diff main` on branch `feat/feature-54-wi-4-remove-picker-ui` (feature-#54 WI-4 changes only; unrelated origin/main merge files excluded):

- `vreader/Views/Reader/ReaderSettingsPanel.swift` — delete `readingModeSection` + `shouldShowReadingModeSection`; delete `tapZoneSection`/`tapZonePicker` + `shouldShowTapZonesSection` + `unifiedDispatchInstallsTapZoneOverlay` + `tapZoneStore` property; rewrite `chineseConversionDisableReason` as a format-only gate; rewrite `.nativeMode` copy; remove the `readingMode` `.onChange`; drop the dead `chineseConversionSupported`.
- `vreader/Views/Reader/ReaderContainerView.swift` — delete `@State var tapZoneStore` + the sheet argument.
- `vreaderTests/Views/Reader/ReaderSettingsPanel{ReadingMode,TapZones,ChineseConversion}GateTests.swift` — repurposed/rewritten.
- `vreaderUITests/Reader/ReaderSettingsPanelTests.swift` — repurposed.
- `docs/architecture.md`, `README.md` — doc-sync.
- `project.yml` / pbxproj — version bump → 3.31.9.

## Round 1

**Verdict: follow-up-recommended.** No product-code correctness findings. The auditor confirmed:
- `chineseConversionDisableReason(for:)` rewrite is spec-consistent; dropping the now-unused `capabilities:` param is the right call (format-only gate, no branch uses it).
- `savePerBookSnapshot` correctly omits `readingMode:` (`PerBookSettingsOverride.readingMode` still defaulted in WI-4; WI-5 removes the field).
- The `.nativeMode` copy rewrite is accurate; doc updates respect the WI-4/WI-5 boundary.
- The three rewritten unit-test files are acceptable for a deletion-heavy WI.

- **Low** — `vreaderUITests/Reader/ReaderSettingsPanelTests.swift`: still hard-asserted (`XCTAssertTrue`) that the Tap Zones section + Reading Mode picker exist — both removed by WI-4, so the UI tests would fail. Fix: repurpose to assert absence.

## Resolution (round 1 → round 2)

Repurposed `ReaderSettingsPanelTests.swift`:
- `testReaderSettingsExposesTapZonesSection` → `testReaderSettingsHasNoTapZonesSection` (`XCTAssertFalse` the header exists after scrolling).
- `testReaderSettingsExposesReadingModeSection` → `testReaderSettingsHasNoReadingModePicker` (`XCTAssertFalse` "Native"/"Unified" options exist).
- `testReaderSettingsPanelOpens` + accessibility audit unchanged; file header updated.

`Feature21PaginatedModeVerificationTests.swift` left untouched — it already `XCTSkip`s when the picker label is absent, so WI-4 doesn't break it (it's a feature-#21 verification test, outside scope).

## Round 2

**Verdict: ship-as-is.** No findings. UI test repurpose confirmed correct; the feature-#21 note checked out.
