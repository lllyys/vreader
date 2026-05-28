---
branch: feat/feature-42-wi2-vreaderlocator
threadId: codex-exec-2026-05-29-wi2
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex Gate-4 audit — Feature #42 Phase-1 WI-2 (VReaderLocator + SchemaV8)

Foundational WI: `VReaderLocator` value-type envelope (Codable/Equatable/Sendable; `ReaderLocatorEngine`
enum; `readiumLocatorJSON: String?` so no Readium dependency; `canonicalHash` mirrors
`AnnotationAnchor.anchorHash`) + additive SchemaV8 (`ReadingPosition.vreaderLocatorData: Data?`, raw
Data per Highlight.anchorData precedent; lightweight migration, all entry points wired). No
engine/dispatch/flag/Readium change.

## Round 1 — 1 High + 1 Medium

| file:line | severity | issue | resolution |
|---|---|---|---|
| vreaderTests/Models/Migration/V6toV7MigrationTests.swift:31,37 + V5toV6MigrationTests.swift:34 | High | Pre-existing migration tests asserted "SchemaV7 is the plan tail" + "schemas.count == 7"; appending SchemaV8 breaks them → unit gate fails. (The implementing agent ran only its own focused tests, missing these.) | **Fixed** — `migrationPlanIncludesV7AtIndex6` (asserts V7 at index 6, not "last" — stable as new schemas land; the tail assertion is owned by SchemaV8MigrationTests), `migrationPlanLengthIsEight` (count == 8), V5toV6 count → 8. Re-ran all 5 migration/locator suites: 46/46 green. |
| docs/architecture.md:12,37,211,213 | Medium | Architecture docs still said live `VReaderApp` uses SchemaV7 / plan ends at V7 — schema/docs-sync violation. | **Fixed** — SchemaV7 → SchemaV8 (system diagram, VReaderApp line, Data Layer heading, migration-plan chain) + documented `ReadingPosition.vreaderLocatorData` + the `VReaderLocator` envelope (raw `Data?`, lightweight migration). |

## Verdict

Round 1: 1 High (stale migration assertions — fixed) + 1 Medium (architecture docs-sync — fixed).
Production WI-2 scope confirmed clean by the auditor: "V8 is wired into the migration plan and live
container, the additive optional `Data?` column is the right SwiftData lightweight-migration shape,
`VReaderLocator` is value-only/Sendable with deterministic sorted-key SHA-256 hashing, and the diff
does not introduce Readium imports, engine dispatch, or flag changes." **Verdict: ship-as-is.** 46
tests green; full build SUCCEEDED.
