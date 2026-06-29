---
branch: feat/feature-129-wi-2-display-sheet
threadId: brrm1e801
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #129 WI-2 (the "Display" settings sheet)

WI-2 adds the designed "Display" `ReaderSettingsSheet` (vreader-panels.jsx): a Theme 5-swatch row, a
Font serif/sans toggle, and Size/Line-spacing/Margin sliders, bound to `ReaderSettings` + callbacks
(brightness + the layout toggle omitted per #129 scope). Pure function of state; the content is extracted
(`ReaderSettingsSheetContent`) for direct UI testing. Files: `ReaderSettingsSheet.kt`,
`ReaderSettingsSheetUiTest.kt` (connected), + `ReaderTheme.kt` (`displayName`).

## Round 1 (Codex `brrm1e801`, gpt-5.5/high) — 1 Medium, 2 Low

| file | severity | issue | resolution |
|---|---|---|---|
| `ReaderSettingsSheet.kt` | Medium | Sheet chrome/content colors were hard-coded to `VReaderColors` (the Paper palette) instead of the active reader theme — so Dark/OLED/Photo settings rendered on a white sheet with paper ink/accent, missing the design's `theme={t}` surface. | **FIXED** — the sheet now derives all tokens from `settings.theme`: `containerColor`/background = `theme.background`, title/labels = `theme.ink`/sub, the selected swatch ring + slider tint = `theme.accent`, the font toggle's track/fill follow the theme's `isDark` (the design's `#3a3530`/`#fff`). The sheet renders in the active theme. |
| `ReaderTheme` swatch label | Low | `ReaderTheme.Oled` rendered as `Oled`; the design label is `OLED`. | **FIXED** — added `ReaderTheme.displayName` (`OLED` for Oled, stable enum `name` kept for persistence/test tags); the swatch shows `displayName`. New tests `displayName_capitalizesOled` (JVM) + an `OLED` assertion in the connected test. |
| `SegmentedToggle` | Low | The generic toggle carried `ReaderFontFamily`-specific font logic — a misleading abstraction. | **FIXED** — replaced with a dedicated `FontSegmentedToggle` (no misused generic). |

The auditor found no Critical/High; design fidelity to `vreader-panels.jsx` was the main theme.

## Verdict

**ship-as-is.** One round, 1 Medium + 2 Low — all fixed.

## Gate-5a verification note (connected-test environment flakiness — rule 47/52)

`ReaderSettingsSheetUiTest` (connected: theme swatch → onTheme, font toggle → onFontFamily, size slider
→ onFontSize, all 5 themes + OLED label + 3 sliders) could **not be landed green this session** — three
consecutive runs failed at the **instrumentation platform** level, NOT on a test assertion: two wedged at
the `connectedDebugAndroidTest` stage (the documented adb-shell-congestion class — the emulator had been
up 2h24m) and the third, on a freshly cold-booted emulator + cleaned adb + a lighter mac, **crashed the
AndroidX Unified Test Platform** (`com.google.testing.platform.core.telemetry.TelemetryKt.createEvent` →
`NonInteractiveServerStrategy`) after 12 min with `tests="0"` (no test ever executed). This is a tooling/
environment failure on a host that's been running heavy build+audit+emulator workloads for hours.

Per rule 47/52 ("do not let tooling flakiness block a code-proven WI"), the WI is **accepted** on the
evidence that the code is sound: (1) main + androidTest **compile clean**; (2) JVM `ReaderThemeTest` **4/0**
incl. `displayName`; (3) this Gate-4 audit is **ship-as-is**; (4) the **sibling connected sheet tests use
the identical harness + pattern and merged green** — `ManageSheetUiTest` 3/3 (#127 WI-5), `AssignSheetUiTest`
(#127 WI-4), `CollectionShelfBarUiTest` (#127 WI-3) — same `createComposeRule` + extracted-content-composable
+ `testTag`/`useUnmergedTree`. The live connected confirmation of the sheet **rides to WI-8's acceptance
pass** (a fresh cold-booted emulator). This is a behavioral WI whose UI is pure (no host wiring yet — WI-3
wires it), so the JVM + audit + sibling-precedent are an adequate pre-merge slice.
