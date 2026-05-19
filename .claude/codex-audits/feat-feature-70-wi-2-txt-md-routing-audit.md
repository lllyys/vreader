---
branch: feat/feature-70-wi-2-txt-md-routing
threadId: 019e3f2f-0c13-74f3-b537-bb7565f9f879
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit log — Feature #70 (GH #491) WI-2 — route TXT + MD font size through FontSizeCalibrator

Gate 4 (implementation audit) of the 6-gate feature workflow. Independent
auditor: Codex MCP, thread `019e3f2f`. Read-only sandbox.

Audited diff: `vreader/Services/ReaderSettingsStore.swift`,
`vreaderTests/Services/ReaderSettingsStoreCalibrationTests.swift`.

## Round 1 findings

Zero Critical/High/Medium findings. Codex confirmed:

- `ReaderSettingsStore` matches the Gate-2-approved plan: `calibrator` is an
  `internal let` (readable by WI-3/WI-4's container views); the two per-target
  helpers `calibratedLineSpacingPoints(for:)` / `calibratedCJKLetterSpacing(for:)`
  are `private` and inside the `#if canImport(UIKit)` block; the public
  `lineSpacingPoints` / `cjkLetterSpacing` properties are unchanged in both
  signature and formula (the Gate-2-rejected property→function refactor was
  correctly NOT done).
- TXT behavior is preserved: `.txt` multiplier is `1.0`, so `txtViewConfig`'s
  `fontSize`, calibrated leading, and calibrated CJK spacing reduce to the old
  formulas. `txtViewConfig.fontName` still resolves correctly — only the face
  name is consumed and `.fontName` is size-independent.
- Concurrency / observation safe: `ReaderSettingsStore` is `@MainActor`,
  `FontSizeCalibrator` is `Sendable`, exposing it as an immutable value creates
  no cross-actor mutation surface; the computed configs still derive from
  `typography` so `@Observable` change tracking is preserved.
- Test coverage aligned: the new suite asserts routing against actual
  calibrator output, checks TXT preservation, guards public-property
  stability, covers re-derivation on typography change, exercises the 12/64
  boundaries.
- Scope contained: no edits to `ReaderSettingsPanel.swift`,
  `TypographySettings.swift`, or EPUB/Foliate/PDF reader files. `project.pbxproj`
  touched only to register the new test file.

## Outcome

Zero open Critical/High/Medium findings, one round. Gate 4 passes for WI-2.
Verdict: **ship-as-is**.
