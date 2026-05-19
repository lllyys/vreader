# Codex Audit — feat/67-wi-2-settings-icon-row

Feature #67 (Settings profile-header card + grouped-row restyle), WI-2 —
"`SettingsRowPalette` design data + `SettingsIconRow` row-style component".
Gate 4 (implementation audit loop) per `.claude/rules/47-feature-workflow.md`.

- **Auditor**: Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
- **Thread**: `019e4153-7284-7a53-ba87-82fc5acd7ccd`
- **Date**: 2026-05-20
- **Rounds**: 2 (round 1 — 1 High + 2 Medium; round 2 — clean, ship-as-is).

## Scope audited

Production:
- `vreader/Models/SettingsRowPalette.swift` (new) — Foundation-only design data
  (`RGBComponents`, `SettingsRowSpec`, `enum SettingsRowPalette` with the six
  core-group row specs).
- `vreader/Views/Settings/SettingsRowStyle.swift` (new) — `enum SettingsRowColors`,
  `enum SettingsRowMetrics`, `struct SettingsIconRow<Trailing: View>` with a
  `where Trailing == EmptyView` convenience init.

Tests:
- `vreaderTests/Models/SettingsRowPaletteTests.swift` (new)
- `vreaderTests/Views/Settings/SettingsIconRowTests.swift` (new)

## Round 1 — findings (1 High + 2 Medium)

- **High — icon fidelity** (`SettingsRowPalette.swift`): the initial symbols
  (`externaldrive.badge.icloud`, `globe`, `character.textbox`,
  `questionmark.circle`, `info.circle`) did not faithfully match the design
  `Row` glyphs (`Icons.Cloud` / `Icons.Library` / `Icons.Note` / literal `?` /
  `Icons.Note`) — a rule-51 fidelity miss that would mount visibly wrong icons.
- **Medium — spacing contract** (`SettingsRowStyle.swift`): the component did
  not encode the design `Row`'s `padding: '12px 14px'` or the `marginRight: 4`
  value→chevron gap.
- **Medium — test weakness**: the palette tests pinned hex but not the symbol
  tokens; the row tests mostly asserted "builds" without metric assertions.

## Round 1 → fixes applied

1. **High**: `SettingsRowPalette` symbols changed to design-faithful SF Symbols
   — `cloud` (Icons.Cloud), `books.vertical` (Icons.Library), `note.text`
   (Icons.Note ×2), `speaker.wave.2` (Icons.Volume), `questionmark` (the
   design's circle-less literal "?"). All five verified to resolve via
   `UIImage(systemName:)` in `everySymbolNameResolvesToARealSFSymbol`.
2. **Medium (spacing)**: added `enum SettingsRowMetrics` pinning the design
   `Row`'s metrics (30pt tile, `borderRadius: 8`, 17pt glyph, `gap: 12`, `12px`
   vertical padding, `marginTop: 1`, `marginRight: 4`, font sizes 15/11/14/13);
   `body` + `iconTile` consume the constants. The `14px` horizontal padding is
   intentionally left to WI-4's `.listRowInsets` (the row mounts inside a
   `Form` `Section` — baking it into the component would double-apply it);
   documented in the `SettingsRowMetrics` doc comment and the `body` inline
   comment.
3. **Medium (tests)**: added `everySpecPinsItsDesignSymbol` (exact symbol-token
   pin per spec), `everySpecPinsItsPaletteKey`, `rowMetricsMatchTheDesignRow` +
   `rowFontMetricsMatchTheDesignRow`.

## Round 2 — re-audit

All three round-1 findings verified genuinely resolved. No new
Critical/High/Medium. Confirmed: Foundation types `Sendable`, view tests
`@MainActor`, no dead code, all files under the ~300-line guideline,
component stays within WI-2's non-mounted scope.

## Verdict

final_verdict: ship-as-is

Gate 4 clean in 2 rounds (rule-47 maximum is 3). WI-2 ships. The row-vs-`Form`
composition (`.listRowInsets`, live row content) is verified at WI-4, not here
— WI-2 delivers the component only.
