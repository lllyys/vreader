---
branch: fix/issue-1329-control-track-contrast
threadId: codex-exec-gpt-5.5-20260601
rounds: 2
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Bug #298 / GH #1329 (Reader Display panel control-track contrast)

## Scope

On the Reader Display panel, `.tint(accent)` only colors the ON toggle track / the
selected segment; the OFF toggle track and the unselected segmented troughs fell
through to iOS `.systemFill` (~1.19:1 over the cream sheet — "no track"). Per the
landed design (`control-track-token.md`), add a per-theme `controlTrack` token
(light family = ink@30%, dark family = white@16%) and drive the inactive control
surfaces with it.

Files:
- `vreader/Models/ReaderThemeV2.swift` (+ `controlTrack` token)
- `vreader/Views/Reader/ReaderDisplayControls.swift` (NEW — `ControlTrackToggleStyle`
  + `ThemedSegmentedPicker`)
- `vreader/Views/Reader/ReaderSettingsPanel.swift` (panel-wide `.toggleStyle`; 3
  segmented `Picker`s → `ThemedSegmentedPicker`; `displaySectionList` extraction
  to dodge a SwiftUI type-checker timeout)
- `vreaderTests/Views/Reader/ReaderSettingsPanelContrastTests.swift` (+ 3 tests)

## Round 1 — findings

Codex (gpt-5.5, read-only). 0 Critical/High. **1 Medium + 2 Low — all fixed.**

| # | file:line | sev | issue | resolution |
|---|---|---|---|---|
| 1 | ReaderDisplayControls.swift:52 | Medium | `ControlTrackToggleStyle` attached the tap only to the 51×31 switch → hit target < 44pt and tapping the row label/body no longer toggled (native `Toggle` toggles on whole-row tap). | FIXED — moved `.contentShape(Rectangle()).onTapGesture` to the whole `HStack` (whole row toggles), switch column gets `.frame(minHeight: 44)`, gated on `@Environment(\.isEnabled)`. |
| 2 | ReaderDisplayControls.swift:113 | Low | `updateUIView` never reconciled segments if `options` changed (the generic component could show stale titles / set a non-existent index). Static call sites today, but unsafe. | FIXED — added `reconcileSegments(_:)` comparing current vs wanted titles; rebuilds (no animation) only on drift, then re-syncs selection. |
| 3 | ReaderDisplayControls.swift:99 | Low | `makeUIView` selected index 0 even when `selection` wasn't in `options` (empty/invalid) → false "selected" segment. | FIXED — both `makeUIView` + `updateUIView` use `options.firstIndex { … } ?? UISegmentedControl.noSegment`. |

Round-1 notes: `controlTrack` derivation matches the design (Paper/Sepia = ink@30%,
Dark/OLED/Photo = white@16%); coordinator holds a value-copy parent refreshed on
update — no retain cycle.

## Round 2 — verification

Codex (gpt-5.5, read-only) re-read the actual file. **No findings.** All three
round-1 issues verified resolved; `@MainActor`/Sendable, coordinator ownership,
target/action lifetime, disabled handling, and invalid-index paths re-checked —
no retain cycle, no new regression.

## Test evidence

- `vreaderTests/ReaderSettingsPanelContrastTests` — 12 tests green (incl. the 3 new
  control-track tests: token derivation, ≥1.8:1 over the cream sheet, OFF≠accent
  Δ≥2.5:1).
- Regression sweep green: `ReaderSettingsPanelChineseConversionGateTests` (7 — the
  disabled segmented picker), `SheetReSkinSnapshotTests` (27 — panel builds),
  `ReaderSettingsStoreTests` (29 — store bindings).

## Verdict

**ship-as-is** — 1 Medium + 2 Low all fixed in round 1, verified clean in round 2.
