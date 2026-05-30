---
branch: fix/issue-1283-default-font-size
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-30
---

# Manual audit — Bug #290 / GH #1283 (default body font size too large)

Trivial config-value change (single default constant + test updates); a full
Codex audit is disproportionate, so manual-fallback per rule 47.

## Manual Audit Evidence

- **Files read**: `vreader/Models/TypographySettings.swift` (init default + Codable
  fallback), `vreader/Services/ReaderSettingsStore.swift` (`loadTypography` returns
  `TypographySettings()` for non-customized users → the effective new-user default),
  `vreader/Services/MD/MDTypes.swift` (separate MD default).
- **Change**: introduced `TypographySettings.defaultFontSize = 16` (was an inline
  `18` at two sites that could drift); routed the init default + the Codable
  `?? 18` fallback through it. #280's calibration (18pt == TXT cap-height parity)
  is unchanged — only the default VALUE the user sees out of the box.
- **Edge cases checked**: empty-object decode + missing-fontSize decode → fall back
  to 16 (new test `defaultFontSizeUsedWhenDecodingWithoutFontSize`); explicit
  persisted fontSize is preserved unchanged (clamp 12…64 unchanged) — an existing
  user who set 18 keeps 18 (`ReadingModeMigrationTests` still asserts the explicit
  18.0 is preserved). Round-trip + empty-object default tests updated to 16.
- **Other default sites swept**: only `TypographySettings` (the unified EPUB/AZW3/
  TXT/PDF store) carried the reported default. `MDTypes.fontSize = 18` is Markdown's
  SEPARATE default — out of the reported EPUB scope; left unchanged (consistency
  follow-up if MD is later reported).
- **Risks accepted**: the exact value (16) is a taste call from the triage
  recommendation; trivially tunable. No behavior change beyond the default value.
- **Tests**: `TypographySettingsTests` (default == 16, == defaultFontSize, decode
  fallback), `ReaderSettingsStoreTests` (default typography + uiFont pointSize == 16)
  — all GREEN.

## Verdict: ship-as-is.
