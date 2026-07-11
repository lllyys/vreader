---
title: Module — persistence and data model
updated: 2026-07-10
status: verified
---

# Module — persistence and data model

## Purpose

Owns all durable app state: the user's library (books, covers, import provenance), reading positions, annotations (highlights, bookmarks, notes), reading sessions/stats, collections, web-novel sources, content replacement rules, the bilingual translation cache, and AI chat sessions. Most of this SwiftData state is written through `PersistenceActor`, which serializes writes made through any one instance of itself and hands them back as Sendable value-type records so `@Model` instances never cross an actor boundary — but that serialization is per-instance, not global. `PersistenceActorEnvironment.swift` injects one shared actor via `\.persistenceActor` for a few call sites (`ReaderContainerView`, the WebDAV/Settings views), but most production views instead construct their own fresh `PersistenceActor(modelContainer: modelContext.container)` per call — `LibraryView`, `LibraryViewSheets`, the `ReaderContainerView` sheet hosts (`ReaderFormatHosts.swift`), and multiple Foliate views (`FoliateSpikeView`, `FoliateReaderContainerView`, `FoliateBilingualContainerView+Position`) among them. Those independently-constructed instances can execute concurrently against the same `ModelContainer`, so there is currently no single globally-serialized writer actor in production. On top of that, `ChapterTranslationStore` (a separate actor), `SwiftDataSessionStore` (`@MainActor`, `ReadingSession` saves/deletes), and two SwiftUI views (`BookSourceListView`, `ReplacementRulesView`, both mutating via `@Environment(\.modelContext)`) write directly — see "Dependencies and concurrency" below.

## Key files and types

Not every file under `vreader/Models/` is persistence territory — the SchemaV10 `@Model` set below is the scope. Reassigned elsewhere: `FormatCapabilities.swift`/`ReaderEngine.swift` → [[Architecture — reader dispatch and format hosts]]; `ReaderThemeV2.swift`/`TypographySettings.swift`/`TapZoneConfig.swift`/`EPUBLayoutPreference.swift`/`FontSizeCalibration.swift` → [[Module — settings and preferences]]; `AnnotationAnchor.swift`/`NamedHighlightColor.swift` → [[Module — annotations and highlights]]; `ExportedAnnotation.swift` → [[Module — export]]; `Locator.swift`/`VReaderLocator.swift` → [[Module — locator]]; `TranslationUnitID.swift` → [[Module — bilingual translation]].

Entities (`vreader/Models/`, all `@Model`; the SchemaV10 model set is 12 entities):

| Entity | Unique key | Notable fields |
| --- | --- | --- |
| `Book` (`Book.swift`) | `@Attribute(.unique) fingerprintKey: String` | `fingerprint: DocumentFingerprint` (private(set), mutate via `updateFingerprint(_:)`), derived `format: String` + `fileByteCount: Int64`, `originalExtension: String?` (V5), `fileState: String` default `"local"` + `blobPath: String?` (V6), `sourceCanonicalKey: String?` (V10), `seriesName`/`seriesIndex`, indexing metadata `totalWordCount`/`totalPageCount`/`totalTextLengthUTF16`, cascade relationships to `readingPosition`, `bookmarks`, `highlights`, `annotations`, `chatSessions`, plus `bookCollections` |
| `ReadingPosition` | — (`locatorHash` derived) | `locator: Locator`, `vreaderLocatorData: Data?` (V8 envelope blob), `updatedAt`, `deviceId` |
| `Highlight` | `highlightId: UUID` | `profileKey`, `locator`, `anchorData: Data?` (V2) with `@Transient var anchor: AnnotationAnchor?` decoded via `try?`, `selectedText`, `color`, `note` |
| `Bookmark` | `bookmarkId: UUID` | `profileKey`, `locator`, `title?` |
| `AnnotationNote` | `annotationId: UUID` | `profileKey`, `locator`, `content` |
| `ReadingSession` | `sessionId: UUID` | `bookFingerprintKey`, clamped `durationSeconds`/`pagesRead`/`wordsRead`, `startLocator`/`endLocator`, `isRecovered` |
| `ReadingStats` | `bookFingerprintKey: String` | aggregates recomputed from sessions via `recompute(from:)`; pages/words use `addingReportingOverflow` clamped to `Int.max`, but total reading seconds accumulate via a plain unchecked `Int64 +=` that is only clamped to `Int.max` afterward — the addition itself can overflow/trap first |
| `BookCollection` | — (name unique at app layer) | `name` (trimmed, 100-char cap), `.nullify` inverse to `Book.bookCollections` |
| `BookSource` (V4) | `sourceURL: String` | Legado-compatible; rules stored as `Data?` JSON blobs (`ruleSearchData` etc.) with `@Transient` decoded accessors |
| `ContentReplacementRule` (V4) | `ruleId: UUID` | `pattern`, `replacement`, `isRegex`, `scopeKey` (empty = global) |
| `ChapterTranslation` (V7) | `lookupKey: String` | key = `book|unit|lang|prompt` (Bug #342: `providerProfileID` is provenance, not identity); `translatedJSON` is a JSON-encoded `[String]` |
| `ChatSession` (V9) | `sessionId: UUID` | `bookFingerprintKey`, `messagesData: Data?` blob + `@Transient messages`, denormalized `lastMessageSnippet`/`messageCount` |

Identity: `DocumentFingerprint` (`vreader/Models/DocumentFingerprint.swift`) = `{contentSHA256, fileByteCount, format}`; `canonicalKey` is `"{format}:{contentSHA256}:{fileByteCount}"`; `isValidSHA256` requires 64 lowercase hex chars; parseable back via `init?(canonicalKey:)`. `BookFormat` (`epub/pdf/txt/md/azw3`; `.azw3` subsumes `azw/mobi/prc` extensions). Annotation sync keys are `profileKey = "{bookFingerprint.canonicalKey}:{locator.canonicalHash}"` — see [[Module — locator]] for the canonical-JSON hash. `Book.sourceCanonicalKey` (`azw3:{sha256_of_source}:{source_byte_count}`) is the cross-platform identity for converted-Kindle books per `contracts/identity/DECISION.md` ([[Module — cross-platform contracts]]).

Record DTOs (returned across the actor boundary, never `@Model`): `BookRecord` (in `vreader/Services/PersistenceActor.swift`), `HighlightRecord` / `BookmarkRecord` / `AnnotationRecord` / `ChatSessionRecord` (in `vreader/Services/`), `LibraryBookItem` + `ChapterTranslationRecord` (in `vreader/Models/`), `BackupBookProjection` (in `PersistenceActor+Backup.swift`), stats models in `vreader/Services/Stats/ReadingStatsModels.swift`. `LibraryBookItem` also carries UI logic: `readingProgressState` (notStarted/inProgress/finished from `progressFraction`), `isReadable`/`needsDownload`/`canShare` from `BookFileState`.

`BookFileState` (`vreader/Models/BookFileState.swift`): 5 cases `local / remoteOnly / downloading / failed / missingRemote`, persisted as raw String on `Book.fileState`; `canDownload` is true only for `.remoteOnly`/`.failed`.

## The actor and its extensions

`actor PersistenceActor` (`vreader/Services/PersistenceActor.swift`, `init(modelContainer: ModelContainer)`) conforms to `BookPersisting`. Every method opens a fresh `ModelContext(modelContainer)`, uses `#Predicate` + `FetchDescriptor` with `fetchLimit = 1` for point lookups, and `try context.save()`. `insertBook` is idempotent (fetch-first) and race-safe: a unique-constraint violation (NSCocoaErrorDomain codes in `constraintViolationCodes` = {133021, 1550, 1551, 1560}) retries as a fetch. Extension files split CRUD by feature:

- `+Library.swift` — `LibraryPersisting`: `fetchAllLibraryBooks()` (joins `ReadingStats` by key in one pass), `deleteBook` (explicitly deletes `ReadingSession`/`ReadingStats` since they are key-linked, not relationships; also `CustomCoverStore.removeCover`).
- `+ReadingPosition.swift` — `ReadingPositionPersisting` + `VReaderLocatorPersisting`: `savePosition` (clears stale `vreaderLocatorData` on a legacy write), `saveVReaderLocator` (dual-write of Feature #42's `VReaderLocator` envelope + legacy `Locator` in one save), `loadVReaderLocator` (decode with `try?` → nil on corrupt blob).
- `+Highlights.swift` — `HighlightPersisting` + `HighlightLookup`: dedupe on `(profileKey, anchorHash)`; `highlight(withID:forBookWithKey:)` is a scoped single-row fetch (feature #55); `countAllHighlights()` via `fetchCount`.
- `+Bookmarks.swift` / `+Annotations.swift` — `BookmarkPersisting` / `AnnotationPersisting`, same shape.
- `+AnnotationBus.swift` — `nonisolated postAnnotationsDidChange()` posts `.readerAnnotationsDidChange` after every successful annotation-mutation save (feature #86 WI-2) — see [[Architecture — notification bus]].
- `+Collections.swift` — collection CRUD, `CollectionError` (case-insensitive name uniqueness at app layer).
- `+Stats.swift` — `recomputeStats(bookFingerprintKey:bookFingerprint:)` upsert; DEBUG-only `seedSyntheticReadingSessions` (bug #263 harness).
- `+ReadingWindow.swift` — `LibraryStatsReading` (feature #67 WI-1): `sumReadingSeconds(in:)` (store-side half-open `[start, end)` predicate), `countLibraryBooks()` via `fetchCount`.
- `+Backup.swift` / `+ReadingHistory.swift` / `+ChatSessionsBackup.swift` — backup fetch/restore for [[Module — backup and WebDAV]]: `fetchAllBooksForBackup() -> [BackupBookProjection]` (sorted by fingerprintKey; nil `originalExtension` coalesced to the format's canonical extension), UUID-then-profileKey dedupe on annotation restore, verbatim ReadingStats restore (no recompute), upsert-by-`sessionId` chat restore honoring the never-clobber blob contract.
- `+RemoteOnly.swift` — feature #47 helpers: `fingerprintKeys(withFileState:)`, `setBookFileState`, `promoteToLocalClearBlob` (bug #118: one atomic save for `.local` + `blobPath = nil`), `insertRemoteOnlyBookRecords` (forces `.remoteOnly`, never downgrades `.local`, partial-success via `PersistenceError.partialBulkInsert(insertedKeys:underlyingDescription:)` — bug #119; single synchronous context block per record to close the find/insert TOCTOU window).
- `+ChatSessions.swift` — `ChatSessionPersisting` (feature #88 WI-2), maintains the denormalized snippet columns.

## Dependencies and concurrency

Internal: `BookImporter` inserts through `BookPersisting` ([[Module — import pipeline]]); backup collectors/restorers, the lazy-download coordinator, and library/reader ViewModels all consume the boundary protocols. `PersistenceActorEnvironment.swift` (`vreader/Utils/`) injects the live actor into SwiftUI via `\.persistenceActor`. External: SwiftData, Foundation, CryptoKit (hashes). Direct writers outside `PersistenceActor` (not a single exception — at least six, not an exhaustive count): among production-feature-runtime writers, `ChapterTranslationStore` (`vreader/Services/ChapterTranslationStore.swift`) is a separate actor writing `ChapterTranslation` rows over the same `ModelContainer` (configured from `VReaderApp` at launch) so bulk translation writes don't block library work — see [[Module — bilingual translation]]; `SwiftDataSessionStore` (`vreader/Services/SwiftDataSessionStore.swift`, `@MainActor`, `SessionPersisting`) opens its own fresh `ModelContext` per call to save/update/delete `ReadingSession` rows directly (upsert-by-`sessionId`, used by `ReadingSessionTracker`); `BookSourceListView` and `ReplacementRulesView` (`vreader/Views/BookSource/`, `vreader/Views/Settings/`) both read `@Environment(\.modelContext)` and call `modelContext.insert`/`.delete`/`.save` directly on `BookSource` / `ContentReplacementRule` rows rather than routing through the actor. Two more sit outside that "feature runtime" frame but still bypass the actor: DEBUG-only `TestSeeder.seedReplacementRule` (`vreader/App/TestSeeder.swift`) opens its own `ModelContext` to insert a fixture `ContentReplacementRule` for UI-test seeding, and the launch-time `LocatorKeyBackfillMigration` (`vreader/Models/Migration/LocatorKeyBackfillMigration.swift`, feature #109) opens its own `ModelContext` to recompute/repair `Highlight`/`Bookmark`/`AnnotationNote`/`ReadingPosition` keys once per install, outside any SwiftData migration stage.

Representative inventory of view-layer files that construct their own `PersistenceActor(modelContainer:)` instance (genuine actor-constructing callers, confirmed via `grep -rn "PersistenceActor(modelContainer" vreader/Views/` — 40+ call sites across ~20 files, not exhaustive; distinct from files that merely reference the `PersistenceActor` type/protocol by name):

- `vreader/Views/Reader/ReaderFormatHosts.swift:35` (plus 4 more `.task`-scoped sites in the same file)
- `vreader/Views/LibraryView.swift:124`
- `vreader/Views/Library/LibraryViewSheets.swift:150`
- `vreader/Views/Reader/FoliateSpikeView.swift:175`
- `vreader/Views/Reader/EPUBReaderContainerView.swift:188`
- `vreader/Views/Reader/PDFReaderContainerView.swift:226`
- `vreader/Views/Reader/TXTReaderContainerView.swift:570`
- `vreader/Views/Reader/Annotations/HighlightsSheet.swift:101`

By contrast, `vreader/Utils/PersistenceActorEnvironment.swift` (injects the shared instance via `\.persistenceActor`) and the DTO/record files under `vreader/Services/` (`HighlightRecord.swift` etc.) name the `PersistenceActor` type without constructing a fresh instance — not counted above.

## Edge cases and invariants

- `insertBook` guards `record.fingerprintKey == record.fingerprint.canonicalKey` (`PersistenceError.invalidContent` on mismatch); `Book.init` trims titles, falls back to `"Untitled"`, caps at 255 chars; `updateBookTitle` re-applies the same cap (bug #247 restore-title path).
- Derived-field sync is explicit (`updateFingerprint`/`updateLocator`/`recomputeKey`) because SwiftData `@Model` `didSet` observers are unreliable.
- Non-finite locators are repaired at every write boundary (`repairedForCanonicalization()` in `savePosition`, `addHighlight`, `addBookmark`, `addAnnotation`, backup `decodeLocator`) — feature #109 / bug #356.
- Codable blobs are always stored as raw `Data?` and decoded with `try?` (Highlight.anchorData, ReadingPosition.vreaderLocatorData, BookSource rule data, ChatSession.messagesData) — never a Codable enum column, avoiding decode crashes on legacy rows.
- `ReadingSession`/`ReadingStats` clamp negatives; `recompute(from:)` accumulates pages/words with `addingReportingOverflow` (clamped to `Int.max`), but total reading seconds use an unchecked `Int64 +=` — the later conversion clamps to `Int.max`, but the Int64 addition itself can overflow and trap before that clamp runs.
- Doc drift note: `docs/architecture.md` calls the ChatSession blob `payloadData: Data?`; the code field is `messagesData: Data?` (`vreader/Models/ChatSession.swift`).

## History

Bug #118 (atomic promote), #119 (partial bulk insert + TOCTOU), #151 (disk-backed store for relaunch UI tests), #155 (collectionNames on LibraryBookItem), #186/GH #633 (skip migration plan on fresh install), #247 (restore title override), #342 (translation lookup key drops profile UUID), #356 (NFC canonicalization); features #34, #42 (WI-2/WI-6 envelope), #46, #47, #55, #56, #58, #60 (WI-8 progress state), #64, #67, #86, #88, #89, #108, #109. Schema evolution details in [[Architecture — schema migration history]].

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
**Verified.** 2026-07-11 — checked against: vreader/Models/Book.swift, vreader/Models/ReadingPosition.swift, vreader/Models/Highlight.swift, vreader/Models/Bookmark.swift, vreader/Models/AnnotationNote.swift, vreader/Models/ReadingSession.swift, vreader/Models/ReadingStats.swift, vreader/Models/BookCollection.swift, vreader/Models/BookSource.swift, vreader/Models/ContentReplacementRule.swift, vreader/Models/ChapterTranslation.swift, vreader/Models/ChatSession.swift, vreader/Models/DocumentFingerprint.swift, vreader/Models/BookFormat.swift, vreader/Models/BookFileState.swift, vreader/Models/LibraryBookItem.swift, vreader/Models/ChapterTranslationRecord.swift, vreader/Models/Migration/SchemaV2.swift, vreader/Models/Migration/SchemaV4.swift, vreader/Models/Migration/SchemaV5.swift, vreader/Models/Migration/SchemaV6.swift, vreader/Models/Migration/SchemaV7.swift, vreader/Models/Migration/SchemaV8.swift, vreader/Models/Migration/SchemaV9.swift, vreader/Models/Migration/SchemaV10.swift, vreader/Services/PersistenceActor.swift, vreader/Services/PersistenceActor+Library.swift, vreader/Services/PersistenceActor+ReadingPosition.swift, vreader/Services/PersistenceActor+Highlights.swift, vreader/Services/PersistenceActor+Bookmarks.swift, vreader/Services/PersistenceActor+Annotations.swift, vreader/Services/PersistenceActor+AnnotationBus.swift, vreader/Services/PersistenceActor+Collections.swift, vreader/Services/PersistenceActor+Stats.swift, vreader/Services/PersistenceActor+ReadingWindow.swift, vreader/Services/PersistenceActor+Backup.swift, vreader/Services/PersistenceActor+ReadingHistory.swift, vreader/Services/PersistenceActor+ChatSessionsBackup.swift, vreader/Services/PersistenceActor+RemoteOnly.swift, vreader/Services/PersistenceActor+ChatSessions.swift, vreader/Services/HighlightRecord.swift, vreader/Services/BookmarkRecord.swift, vreader/Services/AnnotationRecord.swift, vreader/Services/ChatSessionRecord.swift, vreader/Services/Stats/ReadingStatsModels.swift, vreader/Utils/PersistenceActorEnvironment.swift, vreader/Services/ChapterTranslationStore.swift, vreader/App/VReaderApp.swift, vreader/Views/Reader/ReaderNotifications.swift, vreader/Services/BookImporter.swift, contracts/identity/DECISION.md, docs/bugs.md, docs/features.md, docs/architecture.md, archive/bugs-history.md.
