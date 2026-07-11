---
title: Architecture — schema migration history
updated: 2026-07-10
status: verified
---

# Architecture — schema migration history

## Purpose

Records how vreader's SwiftData schema evolved from V1 to V10, what each version changed and which feature drove it, and the two mechanisms that live OUTSIDE the migration plan (the fresh-install plan skip and the launch-time locator-key backfill). Every claim below is verifiable in `vreader/Models/Migration/`.

## Key files and types

- `vreader/Models/Migration/SchemaV1.swift` — `enum SchemaV1: VersionedSchema` (baseline) AND `enum VReaderMigrationPlan: SchemaMigrationPlan`, whose `schemas` array lists `[SchemaV1.self, ..., SchemaV10.self]` and whose `stages` is the **empty array** — every shipped change has been additive/lightweight. Each `SchemaVN` uses `Schema.Version(N, 0, 0)`.
- `vreader/Models/Migration/SchemaV2.swift` ... `SchemaV10.swift` — one file per version; `SchemaV10.models` is literally `SchemaV9.models` (column-only change).
- `vreader/Models/Migration/V1toV2Migration.swift` — documentation-only file (imports only, no executable code) explaining why V1→V2 needs no explicit `MigrationStage`.
- `vreader/Models/Migration/LocatorKeyBackfillMigration.swift` — `enum LocatorKeyBackfillMigration` with `static let completionFlagKey = "vreader.migration.locatorKeyNFC.v1"` and `static func run(container:defaults:)` — the feature #109 one-shot launch backfill (NOT a migration stage).
- `vreader/App/ModelContainerFactory.swift` — `shouldApplyMigrationPlan(storeURL:fileManager:)` + `makeContainer(schema:configuration:)`: applies `VReaderMigrationPlan` only when the store file already exists on disk (bug #186 / GH #633 first-launch freeze fix). Its header comment still says "6-stage" — stale wording; the plan has 10 schemas and zero stages.
- `vreader/App/VReaderApp.swift` — builds `Schema(SchemaV10.models)` (line 85 at time of writing), calls `ModelContainerFactory.makeContainer`, then runs `LocatorKeyBackfillMigration.run(container:defaults: .standard)` — skipped for in-memory (UI-test) stores so the shared UserDefaults gate flag can't be set without touching the real on-disk library.

## Version-by-version

| Version | Change | Driver |
| --- | --- | --- |
| V1 | Baseline 7 models: `Book`, `ReadingPosition`, `Bookmark`, `Highlight`, `AnnotationNote`, `ReadingSession`, `ReadingStats`. File header carries the CloudKit+SwiftData feasibility spike findings: `@Attribute(.unique)` is not enforced server-side by CloudKit, and unique constraints cannot sit on Codable structs — hence primitive String/UUID sync keys (`fingerprintKey`, `sessionId`, `profileKey`) | initial library |
| V2 | `Highlight` gains `anchorData: Data?` (raw JSON bytes of `AnnotationAnchor`), decoded via a `try?` computed property — the pattern every later blob column copies | annotation anchors |
| V3 | New `BookCollection` entity; `Book` gains `seriesName: String?`, `seriesIndex: Int?`, `bookCollections: [BookCollection]` | collections + series |
| V4 | New independent entities `BookSource` and `ContentReplacementRule` | web-novel sources ([[Module — book sources]]) + replacement rules |
| V5 | `Book.originalExtension: String?` — preserves the import-time file extension for backup blob naming | feature #46 (WebDAV materializing restore) |
| V6 | `Book.fileState: String` (default `"local"`, so upgraded rows light up as local with no backfill) + `Book.blobPath: String?` | feature #47 (selective restore + lazy download) |
| V7 | New `ChapterTranslation` entity (independent, no relationship to `Book`) | feature #56 (bilingual translation cache) |
| V8 | `ReadingPosition.vreaderLocatorData: Data?` — the JSON-encoded engine-agnostic `VReaderLocator` envelope; model set unchanged from V7 | feature #42 WI-2 (Readium engine, [[Module — locator]]) |
| V9 | New `ChatSession` entity + the to-many cascade `Book.chatSessions` | feature #88 WI-1 (AI conversation sessions) |
| V10 | `Book.sourceCanonicalKey: String?` — cross-platform canonical identity for converted-Kindle books (`azw3:{sha256_of_source}:{source_byte_count}`, per `contracts/identity/DECISION.md`); nil for native imports and pre-#108 rows (their source bytes were discarded — grandfathered, un-re-keyable) | feature #108 |

All nine migrations (V1→V2 through V9→V10) are lightweight: additive optional columns, defaulted columns, or brand-new entities. `VReaderMigrationPlan.stages` has never contained a custom stage.

## What is deliberately NOT a schema migration

Feature #109 (NFC canonicalization of `Locator.canonicalJSON`, fixing bug #356) required recomputing the persisted derived keys (`Highlight`/`Bookmark`/`AnnotationNote.profileKey`, `ReadingPosition.locatorHash`) and repairing non-finite locators. The `SchemaV10.swift` header records that an earlier, shape-identical SchemaV10 for #109 was removed: SwiftData keys migration on entity-shape hashes, so a `MigrationStage.custom` between two shape-identical schemas never fires (verified empirically per the file comments). The transform instead ships as `LocatorKeyBackfillMigration.run`:

- Synchronous, at launch, BEFORE the `PersistenceActor` / DebugBridge / UI are constructed, so a fresh `ModelContext` owns the store race-free.
- Gated by the UserDefaults flag `vreader.migration.locatorKeyNFC.v1`; runs once per install, idempotent if re-run (`recomputeKey()` is deterministic). On error the flag stays UNSET so the next launch retries.
- One fetch + one save per entity type (`recomputeAll`); offset paging was rejected because the only stable sort columns (`createdAt`/`updatedAt`) are non-unique, so paging could skip/double-process rows on timestamp ties.
- Never invoked for in-memory stores — `VReaderApp` guards on the store kind.

## Container construction path

`VReaderApp.init()` → `Schema(SchemaV10.models)` → `ModelContainerFactory.makeContainer(schema:configuration:)`. The factory calls `shouldApplyMigrationPlan(storeURL: configuration.url)`: only if the store file exists on disk does the container get `migrationPlan: VReaderMigrationPlan.self`. Rationale (bug #186 / GH #633): passing the plan forces SwiftData to materialize and validate every schema in the plan while building the migration graph, on `@MainActor`, even on a fresh install with nothing to migrate — the multi-second first-launch freeze. In DEBUG UI-testing, seeds that exercise terminate-then-relaunch persistence (`seedPositionTest`, `seedKeepExisting`, etc.) get a disk-backed `ModelConfiguration()`; all other UI-test seeds get `isStoredInMemoryOnly: true` (bug #151 / GH #423: an in-memory store dies on `app.terminate()`).

## Edge cases and invariants

- A new schema version is REQUIRED only for entity-shape changes; a pure data transform must run outside the plan (the #109 lesson) — the shape-hash matcher cannot distinguish shape-identical schemas.
- Defaulted-column additions (V6 `fileState = "local"`) upgrade legacy rows without any backfill pass.
- `SchemaV10` is the only version whose `models` references the prior version's list directly (`SchemaV9.models`); every earlier version — column-only (V5/V6/V8) and entity-adding alike — restates the full model list.
- `BackupBookProjection` coalesces V4-era nil `originalExtension` to the format's canonical extension (`BookFormat.fileExtensions.first`) so backup consumers never see the optional.

## History

Bug #151 / GH #423 (in-memory store vs relaunch tests), bug #186 / GH #633 (fresh-install plan skip), bug #356 + feature #109 (NFC backfill, plus the rejected shape-identical SchemaV10), features #42/#46/#47/#56/#88/#108 as the per-version drivers above. Entity details live in [[Module — persistence and data model]]; the V8 envelope's dual-write behavior in [[Module — locator]].

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
**Verified.** 2026-07-11 — checked against: vreader/Models/Migration/SchemaV1.swift, vreader/Models/Migration/SchemaV2.swift, vreader/Models/Migration/SchemaV3.swift, vreader/Models/Migration/SchemaV4.swift, vreader/Models/Migration/SchemaV5.swift, vreader/Models/Migration/SchemaV6.swift, vreader/Models/Migration/SchemaV7.swift, vreader/Models/Migration/SchemaV8.swift, vreader/Models/Migration/SchemaV9.swift, vreader/Models/Migration/SchemaV10.swift, vreader/Models/Migration/V1toV2Migration.swift, vreader/Models/Migration/LocatorKeyBackfillMigration.swift, vreader/App/ModelContainerFactory.swift, vreader/App/VReaderApp.swift, vreader/Models/Book.swift, vreader/Models/BookFileState.swift, vreader/Models/ChapterTranslation.swift, vreader/Models/Highlight.swift, vreader/Models/ReadingPosition.swift, vreader/Models/ChatSession.swift, vreader/Models/Bookmark.swift, vreader/Models/AnnotationNote.swift, vreader/Models/Locator.swift, vreader/Services/PersistenceActor+Backup.swift, vreader/Services/Backup/BackupSectionDTOs.swift, contracts/identity/DECISION.md, contracts/vectors/backup-sections.json, docs/bugs.md, docs/features.md, archive/bugs-history.md.
