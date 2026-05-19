---
branch: feat/56-wi-1-translation-model-wt
threadId: 019e413e-4ad3-7780-9a7c-b93af2b51b43
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/56-wi-1-translation-model-wt

**Feature**: #56 — bilingual reading mode (WI-1, foundational).
**Scope**: `TranslationUnitID` value type, `ChapterTranslation` SwiftData
`@Model`, `SchemaV7`, `VReaderMigrationPlan` schema append, `bilingualReading`
feature flag — plus the tests and the stale `V5toV6` plan-length / FeatureFlags
flag-count assertions corrected.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e413e-4ad3-7780-9a7c-b93af2b51b43`. Gate 4 — implementation audit.

## Round 1 — 3 findings (0 Critical, 0 High, 0 Medium, 3 Low)

Codex confirmed the WI-1 contract is aligned with the plan: `lookupKey` is a
stored, unique primitive (not computed); `unitStorageKey` replaces
`chapterHref`; `translatedJSON` is a stored `String`; `providerProfileID` is
`UUID`; no `Book` relationship; `SchemaV7` = SchemaV6's 10 models +
`ChapterTranslation`; the migration plan stays stage-less. `TranslationUnitID`
is sound for Swift 6 strict concurrency.

1. **Low — "all-defaulted entity" rationale is inaccurate.** The `SchemaV7`
   header and the `migrationPlanHasNoExplicitStages` test said the migration is
   safe because `ChapterTranslation` is "all-defaulted", but only `createdAt`
   has a default. No migration bug (a brand-new independent entity is lightweight
   regardless), just an inaccurate documented reason.
   **Fix**: reworded `SchemaV7.swift` header and the test comment to say the
   migration is lightweight because it introduces a new independent model with
   no backfill of existing rows.

2. **Low — SchemaV7 structure test too weak.** `schemaV7AddsExactlyOneModelOverV6`
   + `schemaV7IncludesChapterTranslation` would miss a regression where one V6
   model is dropped while `ChapterTranslation` is added and the count holds at 11.
   **Fix**: replaced both with `schemaV7IsV6PlusChapterTranslationExactly` —
   an exact set assertion `Set(V7 names) == Set(V6 names) ∪ {ChapterTranslation}`.

3. **Low — unique-key test comment overstates.** `lookupKeyUniqueConstraintIsHonored`
   proves only deduplication (`rows.count == 1`), not which payload survives,
   but its comment claimed "SwiftData upsert-on-unique".
   **Fix**: tightened the comment to uniqueness-only and noted the idempotent
   in-place upsert (last-writer-wins) lands with `ChapterTranslationStore` (WI-2).

## Disposition

Zero Critical/High/Medium. All 3 Low findings fixed (comment/test-quality
only — no production-behavior change, so no re-audit required). Final verdict:
**ship-as-is**.
