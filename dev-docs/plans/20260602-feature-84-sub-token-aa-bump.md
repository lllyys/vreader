# Feature #84 — Secondary-text `sub`-token AA bump (Paper/Sepia)

GH: #1413 · resolves the implementation slice of the now-closed needs-design
#1292 (secondary-text facet of Bug #285 / #1265).

## Problem

The reader Display panel's secondary List chrome (section headers, footers,
value captions) reads the `ReaderThemeV2.sub` token. Over the fixed cream panel
`#fcf8f0` that token (ink @ 55%) computes to Paper ~3.82:1 / Sepia ~3.36:1 —
clears the project's internal 3.0 secondary bar but **fails WCAG AA 4.5:1**.

## Decision (from the landed design — NOT invented here)

`dev-docs/designs/vreader-fidelity-v1/project/design-notes/secondary-text-sub-token.md`
(delivered PR #1317): darken the **light-family `sub` token from ink @ 55% →
ink @ 68%**. 0.68 is the smallest *unified* alpha clearing AA in both themes
(Sepia is the binding case at 4.88:1; Paper lands at 5.81:1). Dark/OLED
unchanged (Bug #285 is light-family only). **No call sites change** — the List
chrome already reads `t.sub` after #1277.

Confirmed by independent computation (WCAG relative-luminance, composited over
`#fcf8f0`): Paper @0.68 = 5.82:1, Sepia @0.68 = 4.88:1. Both also clear over the
lighter white grouped-row card (5.97 / 5.02), so footers/captions on cards stay
AA too.

## Surface area

- `vreader/Models/ReaderThemeV2.swift` — `subColor`: Paper `alpha: 0.55→0.68`,
  Sepia `alpha: 0.55→0.68`. Update the token's doc comment. **2-value change.**
- `vreaderTests/Views/Reader/ReaderSettingsPanelContrastTests.swift` — add the
  RED→GREEN AA test: Paper/Sepia secondary chrome ≥ 4.5:1 over
  `sheetSurfaceColor`. Update the convention docstring (light-family secondary is
  now full AA).
- `vreaderTests/Views/Settings/SettingsSectionHeaderTests.swift` — bump the
  paper-header bar from ≥3.0 to ≥4.5 (it measures `paper.subColor` over the sheet
  — exactly this AA case).
- **Design-pin test updates** (these pin the OLD 0.55 value, so they move to 0.68
  as part of GREEN — restore-to-designed): `ReaderThemeV2Tests.swift` (paper/sepia
  `sub` alpha rows + `paper_subColor_isInkWithDesignAlpha`),
  `TXTViewConfigThemeTests.swift` (paper sub / MD secondary alpha pins).

### Files OUT of scope

- Dark/OLED `sub` (separate visual-weight call, ~3.7:1 over `#222020` — the design
  flagged it as a follow-up to surface to the user, NOT file unilaterally).
- Any call site (`ReaderSettingsPanel`, `ReaderSheetChrome` chrome palette) — the
  routing already reads `t.sub`.
- `WCAGContrastTests` 3.0 secondary floor — still valid (now exceeded); left as a
  floor to keep the diff focused.

## Work-item sequencing

Single behavioral WI (the final WI). 2-value token change + tests. PR size: tiny.

## Test catalogue

- `ReaderSettingsPanelContrastTests.secondaryChromeLabelClearsAA` (new) — Paper/Sepia
  `sub` ≥ 4.5:1 over `sheetSurfaceColor`. RED on 0.55, GREEN on 0.68.
- Updated design-pin assertions (0.55→0.68) — guard the restored-to-design value.

## Risks + mitigations

- *Risk*: darkening `sub` narrows the primary↔secondary hierarchy. *Mitigation*:
  primary ink stays ~13–16:1 vs secondary 4.9–5.8:1 — a clear gap; the design
  explicitly rejected 78% for crowding primary and picked 68% as the minimum.
- *Risk*: `sub` is global, used over other surfaces. *Mitigation*: alpha only
  increases (ink RGB unchanged), so contrast rises monotonically over every
  background; verified ≥AA over both cream and the lighter white card.

## Backward compat

Pure token-value change; no schema, no persistence, no migration. Older per-book
theme choices unaffected (the enum cases and rawValues are unchanged).

## Gate 2 — plan audit

The independent design artifact (PR #1317 design note, with its own "why 68 not
62/78" rationale and honest §5 dark-family measurement) IS the independent review
of the value choice. Model assumptions verified directly here: `subColor` exists
with the ink-RGB+alpha pattern; `sheetSurfaceColor` = `#fcf8f0` for both light
themes; the AA math reproduced independently. The load-bearing independent audit
is the Gate-4 Codex pass on the implementation diff (the change is 2 alphas +
tests; there is no architectural surface for a separate plan audit to find).
