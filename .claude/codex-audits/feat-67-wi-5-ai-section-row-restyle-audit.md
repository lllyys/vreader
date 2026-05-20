---
branch: feat/67-wi-5-ai-section-row-restyle
threadId: 019e459e-cf90-7460-adf6-6ac13c49237a
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — feature #67 WI-5 (restyle AI Provider row to SettingsIconRow — narrowed for rule 51)

## Round 1 — clean

Audit ran against the WI-5 implementation commit `cf28738`. Zero findings across all 8 dimensions (correctness/edge cases/security/duplicate code/dead code/shortcuts/VReader compliance/bridge safety).

The audit's key question was the scope-narrowing decision: the plan said WI-5 "definitively restyles" all three rows of `AISettingsSection`, but Gate-3 audit of `vreader-panels.jsx:868-870` showed the committed design depicts only one — the AI Provider row (`Icons.Sparkle` `#8c2f2f`). I narrowed WI-5 to restyle only that row, filed `needs-design` #1068 for the missing AI Assistant + Data & Privacy toggle row designs, and the two toggle rows kept their plain-`Toggle` chrome.

Auditor verification (per Codex's own search of the design bundle):

> The scope narrowing is rule-51-correct. I searched the committed design bundle and found only the AI settings rows at `vreader-panels.jsx:868-870`: designed `AI provider` plus aspirational `Translation languages`, with no depiction of the `Enable AI Assistant` or `Allow AI data sharing` toggle-row chrome. Under rule 51, there is no valid inheritance path from "similar" rows on another surface.

Per-dimension confirmations:

- **Correctness**: `SettingsRowPalette.aiProvider` maps to `sparkles` + `#8c2f2f` exactly. The `NavigationLink` destination (`AIProviderListView(viewModel:)`) and identifier (`aiProvidersNavLink`) preserved verbatim. `activeProfileSummary` still threads to the row's `trailingValue`.
- **Edge cases**: empty-profile-list state still surfaces as `""` → collapsed to `nil` in `AISettingsProviderRow.body` (the right empty-state for `SettingsIconRow`). `rowPaletteKeysForTesting == []` when AI is disabled is the right contract — the seam reports rendered palette-backed rows, not all visible controls.
- **Duplicate code**: 7 `SettingsIconRow` callsites — auditor recommends keeping the explicit form. The small repetition keeps each row's wiring obvious, and a convenience init would obscure the per-row `Image`/`title` differences.
- **Shortcuts**: `trailingValue.isEmpty ? nil : trailingValue` is a reasonable local normalization; pushing the rule down into `SettingsIconRow` would be premature.
- **VReader compliance**: `AISettingsSection.swift` is 137 lines (under the 300 guideline). Hard-coded `.paper` theme is acceptable because App Settings is already paper-only elsewhere in this surface.

## Summary

- 1 round (rule-47 maximum is 3; ship-as-is at round 1 saves the additional rounds for higher-risk WIs).
- 0 open findings.
- Author/auditor separation held: implementation by Claude Code, audit by Codex MCP (read-only sandbox) in a separate process.
- Final verdict: **`ship-as-is`**.
