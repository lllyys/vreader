---
branch: feat/feature-99-wi-1-edit-model
threadId: 019eb608-b7cd-7190-8fe1-8f29ceafaa2a
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #99 WI-1 — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-99-translation-settings-reentry.md`
(WI-1: `ChapterTranslationStore.cachedLanguages` + the pure
`BilingualSettingsEditModel`). Runner: `scripts/run-codex.sh`. Round-2
session: `019eb611-ee7b-71f2-ab66-a65418e5a6f7`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `BilingualSettingsEditModel.swift:56` — `dirtyKind` compared raw language keys; a stale persisted `currentLanguage` (key removed from the registry) made an untouched sheet look dirty, bypassing the setter equality guards | Medium | **Fixed** — both sides canonicalised via `BilingualLanguage.findOrDefault(key:)` (the draft's `normalised()` rule); the cache lookup uses the canonical draft key. Regression test `stalePersistedCurrentKeyDoesNotFakeDirty`. |

Round 1 explicitly confirmed: `cachedLanguages` actor-safe, corrupt-row
exclusion correct, full-book fetch acceptable for the settings-entry
path, file sizes within budget.

## Round 2 (verify)

Clean — fix confirmed; store helper + tests (empty / distinct /
cross-book / corrupt-row) verified; no new issues.

## Verdict

ship-as-is. 16 WI-1 tests green (+ the 21 pre-existing store-suite
regressions in the same run earlier).
