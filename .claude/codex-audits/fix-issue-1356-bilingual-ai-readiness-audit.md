---
branch: fix/issue-1356-bilingual-ai-readiness
threadId: 019e86a2-b8c6-7520-966b-49b8e2f6c258
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #301 (GH #1356): bilingual setup-sheet engine strip truthful

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the slice-1 fix: the bilingual setup-sheet engine
strip now reflects the REAL AI-provider state instead of the hardcoded
`BilingualEngineDescriptor(configured: true)` every host shipped.

- Round 1 session id: `019e86a2-b8c6-7520-966b-49b8e2f6c258`
- Round 2 session id: `019e86ae-a324-7e31-9962-940f39177b6c`

## Scope audited

- `vreader/Services/AI/BilingualAIReadiness.swift` (new probe)
- `vreader/ViewModels/BilingualReadingViewModel.swift` (`aiConfigured` + `refreshAIConfigured`)
- All six bilingual hosts (`*+Bilingual.swift` + `FoliateBilingualContainerView.swift`)
- `vreaderTests/Services/AI/BilingualAIReadinessTests.swift` (new, 8 tests)
- Context: `AIService` (the gate mirrored), `ProviderProfileStore`,
  `ProviderProfileMigrator`, `KeychainService`, `AIConsentManager`.

## Round 1 — findings

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `*+Bilingual.swift` (all six hosts) | Medium | `aiConfigured` was refreshed only when the VM was created, not before each setup-sheet presentation → a stale strip if the user changed AI settings/consent/provider/key before first enabling bilingual. | FIXED — added `.task { await bilingualViewModel?.refreshAIConfigured() }` to the `BilingualSetupSheet` content in all six hosts, so readiness is re-resolved each time the sheet appears; `@Observable aiConfigured` propagates into the rebuilt descriptor. |
| `BilingualAIReadinessTests.swift` | Low | The negative tests didn't actually seed a legacy `AIService.apiKeyAccount` key, so they didn't *prove* the new probe ignores the legacy gate. | FIXED — added legacy-key tests. Investigation found that reading the store triggers `ensureMigrated`, which migrates a legacy-only key into a new ACTIVE profile (matching the live pipeline). Tests now assert: `legacyKeyMigratesToActiveProfile` → true; `legacyKeyButActiveProfileMissingPerProfileKey` → false (the clean old-gate-vs-new-probe differentiator: the old `hasAPIKey` gate would say true, the new probe says false); `emptyPerProfileKey` → false. |

Round-1 correctness confirmation (verbatim from the auditor): in steady state
`BilingualAIReadiness.resolve` matches the `AIService` gate (aiAssistant flag +
consent + active profile + that profile's per-profile key); no extra gate and no
Sendable hazard crossing the `ProviderProfileStore` actor; the production default
singletons match what the live hosts use; the fire-and-forget refresh task is
fail-safe (defaults to `false`).

## Round 2 — verification

> "Findings: none. Round-1 finding 1 is resolved … all six hosts attach
> `.task { await bilingualViewModel?.refreshAIConfigured() }` to the actual
> `BilingualSetupSheet` content … Round-1 finding 2 is resolved … matches
> `ProviderProfileStore.ensureMigrated()` and `DefaultProviderProfileMigrator`."

Zero open findings. Test suite GREEN (8/8) under
`scripts/run-tests.sh vreaderTests/BilingualAIReadinessTests`.

## Verdict

**ship-as-is.** The fix mirrors the real bilingual gate, the stale-strip race is
closed, and the regression suite pins the gate (including the migration path the
old legacy-key gate diverged from).

## Scope note (tracked follow-up, not in this PR)

Bug #301's fix direction had three slices. This PR ships slice 1 (truthful engine
strip) + the failure now being surfaced AT the setup sheet — which fixes the
reported repro (the sheet falsely claiming "AI provider configured"). Slice 2
(`onOpenSettings → AI Providers`) needs an in-reader → AI-settings navigation
path that does not exist today (the reader's `showSettings` presents only
`ReaderSettingsPanel`; the full `SettingsView` AI section is Library-only) — a
new in-reader navigation surface, filed as a separate `needs-design` follow-up.
