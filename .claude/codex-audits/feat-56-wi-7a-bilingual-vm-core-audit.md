---
branch: feat/56-wi-7a-bilingual-vm-core
threadId: 019e4187-9943-7013-9a96-59dbab8e4b60
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/56-wi-7a-bilingual-vm-core

**Feature**: #56 — bilingual reading mode (WI-7a, foundational).
**Scope**: `BilingualReadingViewModel`'s persistence/state core — the per-book
on/off toggle backed by `PerBookSettings`, target language + granularity, the
per-unit translation dictionary, the first-enable setup-sheet flag.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e4187-9943-7013-9a96-59dbab8e4b60`. Gate 4 — implementation audit.

## Round 1 — 2 findings (0 Critical, 0 High, 0 Medium, 2 Low)

Codex confirmed:

- **Scope is clean for WI-7a** — no notification posting, no prefetch logic,
  no `ChapterTextProviding` injection, no trigger behavior leaked from WI-7b.
- The persistence read-modify-write preserves the typography fields correctly
  (`PerBookSettingsStore.save` uses atomic writes; for a `@MainActor` VM doing
  local file IO the read-modify-write is sufficient).
- The setup-sheet logic is correct for fresh / already-configured /
  configured-then-disabled books — `hasBeenConfigured` keys on the presence of
  any bilingual key, not just `bilingualEnabled == true`.
- The init fallback for an invalid stored granularity (`?? .paragraph`) is safe.
- Strict concurrency is fine; `project.pbxproj` wiring is correct.

The 2 Low findings are both missing **test coverage** of correct-but-unpinned
behavior — no production-code change:

1. **Low — no reload-from-disk test** for "configured-then-disabled book does
   not re-raise the setup sheet on re-enable" (the existing test only proved
   same-instance behavior after `dismissSetupSheet()`).
   **Fix**: added `configuredThenDisabledBook_doesNotReRaiseSetupSheetOnReEnable`
   — pre-writes `PerBookSettingsOverride(bilingualEnabled: false,
   bilingualTargetLanguage: "Chinese")`, inits a fresh VM, `setEnabled(true)`,
   asserts `needsSetupSheet == false`.

2. **Low — no garbage/future-value granularity test.**
   **Fix**: added `garbageStoredGranularity_fallsBackToParagraph` — pre-writes
   `bilingualGranularity: "future-value"`, asserts the VM inits with
   `granularity == .paragraph`.

## Disposition

Zero Critical/High/Medium. Both Low findings were test-coverage-only (the
production code Codex reviewed is unchanged — the two tests pin
correct-as-audited behavior, so no re-audit is required). Final verdict:
**ship-as-is**.
