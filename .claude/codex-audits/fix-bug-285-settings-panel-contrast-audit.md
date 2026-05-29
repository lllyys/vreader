---
branch: fix/bug-285-settings-panel-contrast
threadId: 019e74e2-17ef-70b2-acb2-09dbdd400f84, 019e74e6-04f1-78a1-a388-56667bc72f96
rounds: 2
final_verdict: ship-as-is
date: 2026-05-30
---

# Gate-4 Codex audit — Bug #285 / GH #1265 (Display panel low-contrast in Paper/Sepia)

Independent Codex audit (read-only sandbox, `codex exec`) of the diff fixing the
Reader Display settings panel's low-contrast native chrome in the Paper / Sepia
themes. Author/auditor separation preserved (Codex is a separate process from the
implementing Claude session).

## What changed
- `vreader/Views/Reader/ReaderSettingsPanel.swift`: added a testable
  `ChromeLabelPalette` (primary = `theme.inkColor`, secondary = `theme.subColor`,
  destructive = design's `#c44`). Routed the native `List` chrome through these
  tokens — list-wide `.foregroundStyle(primary)` + `.tint(accent)`; Section
  headers and footers via explicit `secondaryLabelColor` helpers; plain captions
  to secondary; the destructive "Remove Background" `Label` to the design's `#c44`.
- `vreaderTests/Views/Reader/ReaderSettingsPanelContrastTests.swift`: 7 tests
  pinning the resolved chrome colours against the project's two-bar WCAG
  convention (primary ≥ 4.5:1, secondary ≥ 3.0:1) over the cream sheet surface,
  the theme-token resolution (not system label colours), the destructive
  semantic (≠ ink, == `#c44`, ≥ ~4.4:1), and no dark-family regression.

## Round 1 — threadId 019e74e2-17ef-70b2-acb2-09dbdd400f84
- **Medium**: list-wide `.foregroundStyle(primaryLabelColor)` (theme ink) repaints
  the destructive "Remove Background" button's system red in ink, losing the
  destructive affordance — outside the bug's stated chrome-label scope.
  → **FIXED**: `ChromeLabelPalette.destructive` = the design's documented danger
  value `#c44` (`vreader-panels.jsx` line 823: `danger ? '#c44' : t.ink`), applied
  via `.foregroundStyle(destructiveLabelColor)` on the Label. `#c44` over cream =
  4.43:1, an improvement over the ~3.35:1 system red it replaces, and a
  restore-to-design value (not invented).
- **Low**: tests validate token values / contrast math but not the SwiftUI render
  path or the destructive/segmented semantics.
  → **ADDRESSED**: added 3 tests pinning the destructive semantic (≠ primary ink,
  == `#cc4444`, clears ~4.4:1 over cream). (Full SwiftUI render-path / pixel
  testing is out of scope per the repo's "test behaviour, not pixels" convention.)
- **Checks (all clean)**: design-token mapping faithful (primary→ink, secondary→sub,
  tint→accent); NO invented `sub` alpha or slider-track opacity; Rule-51 escalation
  reasoning sound; AA thresholds correctly framed; dark themes safe; preview row's
  own `.foregroundStyle(store.uiTextColor)` not overridden.

## Round 2 — threadId 019e74e6-04f1-78a1-a388-56667bc72f96
- **No blocking findings.** Destructive row correctly excluded from the ink
  repaint; no other control wrongly inherits ink (PhotosPicker "Choose Image"
  stays ink/accent as intended; segmented picker text + `.tint` accent consistent).
  `#c44` confirmed a real committed design value (Rule-51-clean reuse, not
  invented). No new functional issue from the round-1 fix; added tests pin the
  important semantics.
- **Verdict: ship-as-is.**

## Rule-51 escalation (recorded, not a finding)
The slider unfilled-track opacity (design's `rgba(0,0,0,0.1)` ≈ 1.25:1 over cream)
was NOT changed: it is decorative furniture (the accent fill + 22pt white thumb
convey the value/state, so it is not a WCAG 1.4.11 state-identification failure),
and darkening it would be an invented aesthetic value with no design source.
Escalated to `needs-design` GH #1273 (labels `enhancement` + `needs-design`,
`Refs #285`) rather than self-designed. The text-legibility defect — the
substantive part of #285 — is fully fixed and verified by the contrast tests.

## Test gate
All 7 contrast tests pass; the existing `WCAGContrastTests` suite passes; the full
`vreaderTests` population is green when not hit by an unrelated simulator
launchd/runner restart flake (8209/8218; the only 3 "failures" —
`case3_noMark_throwsSettleTimeout`, `resolveHighlightTap_returnsViewLocalRect…`,
`URLSession … ATS … non-loopback HTTP` — are in unrelated files and pass cleanly
in isolation).
