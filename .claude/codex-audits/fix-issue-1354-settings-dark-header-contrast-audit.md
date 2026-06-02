---
branch: fix/issue-1354-settings-dark-header-contrast
threadId: 019e86ea-9223-7b72-8969-ca3c012b60c8
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #300 (GH #1354): Settings section headers faint in Dark Mode

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the fix that paints the app Settings sheet's section
headers with the designed `sub` token (`SettingsSectionHeader`) instead of the
system `secondaryLabel` (which resolves ~1.07:1 over the pinned cream sheet in
system Dark Mode).

## Scope audited

- `vreader/Views/Settings/SettingsSectionHeader.swift` (new — themed header + `color(for:)` seam)
- `vreader/Views/Settings/SettingsView.swift` (Cloud & Sync / Reading / About sections)
- `vreader/Views/Settings/AISettingsSection.swift` (AI section)
- `vreaderTests/Views/Settings/SettingsSectionHeaderTests.swift` (new, 3 contrast/token tests)

## Findings — none (zero Critical/High/Medium/Low)

## Auditor confirmations

- **Correctness / appearance-independence**: `color(for:)` returns `theme.subColor`,
  a fixed light-theme UIKit token (not appearance-aware) — so the header resolves
  the same in Light and Dark, fixing the Dark-Mode faintness. No system-appearance
  color path remains.
- **Typography safe (the main Rule-51 risk)**: a custom `header: { Text(...).foregroundStyle(...) }`
  keeps the platform Form section-header text style; this is the SAME pattern the repo
  already uses at `ReaderSettingsPanel.swift:273`. The auditor explicitly advised
  AGAINST adding an explicit `.font` (it would diverge from platform styling). So
  this is a pure restore-to-designed recolor, not a typography redesign.
- **All four root sections converted** — Cloud & Sync, AI, Reading, About.
- **Correct background target**: headers sit in the Form section-header area,
  outside the `.listRowBackground(sheetCardSurfaceColor)` rows, so the test's
  contrast assertion over `sheetSurfaceColor` is right.
- **`AISettingsSection` uses its own `.paper` theme**, matching the sheet root.
- **No cross-feature import** of the reader's `BilingualSectionLabel` — the
  component is Settings-local (correct).
- Out of scope: other `Section("…")` in nested settings/editor sub-screens are not
  the four root groups #300 names; left untreated by design.

## Verdict

**ship-as-is.** Zero findings; build + 3 tests GREEN.
