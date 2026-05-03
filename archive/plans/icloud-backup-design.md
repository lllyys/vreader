# iCloud Backup & Restore — Design Document

**WI-015 (Feature #10)** | **Status**: Design Only — Implementation Deferred to V2
**Date**: 2026-03-14

---

## 1. Problem Statement

VReader stores reading data locally on a single device. Users face two problems:

1. **Data loss risk**: A lost, broken, or wiped device destroys all reading positions, bookmarks, highlights, annotations, and reading statistics. Reimporting books is possible (files can be re-downloaded), but all user-generated metadata is gone.

2. **No cross-device continuity**: A user reading on an iPad at home cannot pick up where they left off on an iPhone during a commute. Each device is an isolated silo with independent reading state.

iCloud backup and restore solves both: user data is durably stored in Apple's cloud and available on every device signed into the same Apple ID.

---

## 2. Data Scope

### 2.1 Data Categories

| Category | Examples | Size Profile | Update Frequency | Sync Priority |
|----------|----------|-------------|-----------------|---------------|
| **Book files** | Imported EPUBs, PDFs, TXT, MD | Large (KB–hundreds of MB per file) | Write-once at import | Low (can re-download) |
| **Annotations** | Highlights, notes, bookmarks | Small (< 1 KB each, tens to thousands per book) | Medium (user-driven) | High |
| **Reading positions** | Current page/offset, progress % | Tiny (< 100 B per book) | High (every page turn) | Critical |
| **Settings/preferences** | Sort order, view mode, theme, AI config, feature flags | Tiny (< 1 KB total) | Low (occasional toggle) | Medium |
| **Reading statistics** | Sessions, total time, pages/words read | Small (< 1 KB per session, accumulates) | Medium (per reading session) | Medium |
| **Library metadata** | Book title, author, tags, isFavorite, addedAt | Small (< 1 KB per book) | Low (manual edits rare) | Medium |

### 2.2 VReader Model Mapping

| SwiftData Model | iCloud Layer | Sync Key | Notes |
|-----------------|-------------|----------|-------|
| `Book` | CloudKit (metadata) + iCloud Documents (file) | `fingerprintKey` | Metadata syncs via CloudKit; file bytes via iCloud Documents |
| `ReadingPosition` | CloudKit | `book.fingerprintKey` | One per book; LWW by `updatedAt` |
| `Bookmark` | CloudKit | `bookmarkId` (UUID) | Tombstone-aware for deletes |
| `Highlight` | CloudKit | `highlightId` (UUID) | Tombstone-aware; field-level merge |
| `AnnotationNote` | CloudKit | `annotationId` (UUID) | Tombstone-aware LWW |
| `ReadingSession` | CloudKit | `sessionId` (UUID) | Append-only; deduplicate by ID |
| `ReadingStats` | Derived | N/A | Recomputed from `ReadingSession` records — not synced directly |
| Preferences | NSUbiquitousKeyValueStore | String keys | `sortOrder`, `viewMode`, theme, AI toggle |

### 2.3 What Does NOT Sync

- **Cover image cache** — regenerated from book file on each device.
- **Search index** — rebuilt locally from book content.
- **AI conversation history** — session-scoped (V1), not persisted.
- **Import provenance** — device-local import path is not meaningful on other devices.
- **Feature flag overrides** — session-scoped debug state.

---

## 3. Technology Options

### 3.1 Comparison

| Technology | Best For | Size Limit | Structured Query | Conflict Handling | Offline | Complexity |
|------------|---------|-----------|-----------------|-------------------|---------|------------|
| **CloudKit** | Structured records with relationships | 1 MB per record (assets up to 250 MB) | Yes (predicates, zones, subscriptions) | Per-record conflict detection | Full offline queue | High |
| **iCloud Documents** | Opaque file blobs | 50 GB iCloud quota shared | No (file-level only) | NSFileVersion-based | Depends on NSFileCoordinator | Medium |
| **NSUbiquitousKeyValueStore** | Key-value settings | 1 MB total, 1024 keys max | No | Last-write-wins (automatic) | Yes (local cache) | Very low |
| **SwiftData + CloudKit** | SwiftData models with automatic sync | Same as CloudKit | SwiftData predicates | Automatic (last-write-wins) | Yes | Medium (but opinionated) |

### 3.2 Recommendation: Hybrid Approach

| Data Type | Technology | Rationale |
|-----------|-----------|-----------|
| Settings/preferences | **NSUbiquitousKeyValueStore** | Trivially simple for < 10 key-value pairs. Automatic LWW. No schema needed. |
| Annotations, positions, sessions, metadata | **CloudKit (private database, custom zone)** | Fine-grained conflict resolution needed (the app already has `SyncConflictResolver`). Custom zones enable atomic zone-level commits and change tokens for efficient incremental sync. |
| Book files | **iCloud Documents (via `FileManager.url(forUbiquityContainerIdentifier:)`)** | File-based, handles large binaries naturally. Download-on-demand via `startDownloadingUbiquitousItem`. User sees files in iCloud Drive. |

**Why not SwiftData + CloudKit automatic sync?**
- SwiftData's automatic CloudKit sync uses last-write-wins for everything. Our existing `SyncConflictResolver` implements richer strategies: tombstone-aware LWW, field-level merge for highlights, append-only sessions, user-edit-wins for metadata. Automatic sync would discard this nuance.
- Automatic sync does not support custom zones, so we lose zone-level change tokens and atomic commits.
- Migration is harder to control — schema changes require careful coordination with CloudKit dashboard.

---

## 4. Architecture

### 4.1 Layer Diagram

```
┌──────────────────────────────────────────────┐
│              VReader App Layer                │
│  PersistenceActor  PreferenceStore  ViewModel │
└──────────────┬───────────┬───────────┬───────┘
               │           │           │
┌──────────────▼───────────▼───────────▼───────┐
│              SyncService (actor)              │
│  SyncConflictResolver  TombstoneStore         │
│  FileAvailabilityStateMachine                 │
│  SyncStatusMonitor                            │
└──────────┬───────────┬───────────┬───────────┘
           │           │           │
    ┌──────▼──────┐ ┌──▼──────┐ ┌─▼──────────────────┐
    │  CloudKit   │ │ NSUKVS  │ │ iCloud Documents    │
    │  (records)  │ │ (prefs) │ │ (book files)        │
    └─────────────┘ └─────────┘ └─────────────────────┘
```

### 4.2 CloudKit Schema

**Zone**: `VReaderData` (custom zone in private database)

| Record Type | Fields | Notes |
|-------------|--------|-------|
| `VRBook` | `fingerprintKey`, `title`, `author`, `format`, `fileByteCount`, `addedAt`, `tags`, `isFavorite`, `detectedEncoding`, `isUserEdited`, `updatedAt` | 1:1 with `Book` minus file data |
| `VRReadingPosition` | `bookFingerprintKey`, `locatorJSON` (Locator as JSON blob), `updatedAt`, `deviceId` | LWW by `updatedAt` |
| `VRBookmark` | `bookmarkId`, `bookFingerprintKey`, `locatorJSON`, `title`, `createdAt`, `updatedAt`, `isDeleted` | Tombstone-aware |
| `VRHighlight` | `highlightId`, `bookFingerprintKey`, `locatorJSON`, `selectedText`, `color`, `note`, `createdAt`, `updatedAt`, `isDeleted` | Tombstone-aware, field-level merge |
| `VRAnnotation` | `annotationId`, `bookFingerprintKey`, `locatorJSON`, `content`, `createdAt`, `updatedAt`, `isDeleted` | Tombstone-aware LWW |
| `VRReadingSession` | `sessionId`, `bookFingerprintKey`, `startedAt`, `endedAt`, `durationSeconds`, `pagesRead`, `wordsRead`, `deviceId`, `isRecovered` | Append-only |

**Key design decisions**:
- `Locator` is stored as a JSON blob string (`locatorJSON`) rather than flattened fields. This avoids CloudKit schema changes when `Locator` gains new format-specific fields (e.g., EPUB CFI, PDF rect for annotation anchors from WI-C00).
- `isDeleted` soft-delete field on bookmarks/highlights/annotations enables tombstone sync (matching existing `TombstoneStore` pattern).
- `bookFingerprintKey` is the cross-reference key (not a CKReference) to allow records to exist even when the book record hasn't synced yet.

### 4.3 NSUbiquitousKeyValueStore Keys

| Key | Value Type | Default | Notes |
|-----|-----------|---------|-------|
| `library.sortOrder` | String (raw value) | `"title"` | Maps to `LibrarySortOrder` |
| `library.viewMode` | String (raw value) | `"grid"` | Maps to `LibraryViewMode` |
| `reader.theme` | String (raw value) | (system default) | Maps to `ReaderTheme` |
| `ai.enabled` | String (`"true"/"false"`) | `"false"` | AI feature toggle |
| `schemaVersion` | String (integer as string) | `"1"` | For future migration |

**Total estimated size**: < 500 bytes (well within 1 MB limit).

### 4.4 iCloud Documents Layout

```
iCloud Container: iCloud.com.vreader.app
└── Documents/
    └── Books/
        ├── {fingerprintKey}/
        │   ├── book.{epub,pdf,txt,md}    ← original imported file
        │   └── manifest.json             ← FileManifest metadata
        └── ...
```

- Directory named by `fingerprintKey` ensures uniqueness.
- `manifest.json` contains `FileManifest` (version, checksum) for integrity verification.
- Files are evictable — iOS can purge downloaded copies when storage is low. `FileAvailabilityStateMachine` tracks state.

---

## 5. Conflict Resolution Strategy

The existing `SyncConflictResolver` (in `vreader/Services/Sync/`) already implements the algorithms needed. This section maps each data type to its resolution strategy.

### 5.1 Resolution Matrix

| Data Type | Strategy | Tie-Breaker | Implementation |
|-----------|----------|------------|----------------|
| **Reading position** | LWW by `updatedAt` | Lexicographic `deviceId` | `SyncConflictResolver.resolvePosition()` |
| **Bookmarks** | Tombstone-aware LWW | Keep earliest `createdAt` | `SyncConflictResolver.resolveBookmark()` |
| **Highlights** | Tombstone-aware LWW with field-level merge | Newest `updatedAt` wins per field set | `SyncConflictResolver.resolveHighlight()` |
| **Annotations** | Tombstone-aware LWW | Delete bias on equal timestamps | `SyncConflictResolver.resolveAnnotation()` |
| **Library metadata** | User-edited wins over extracted; among same type, newest wins | N/A | `SyncConflictResolver.resolveLibraryMetadata()` |
| **File manifest** | Monotonic version; higher wins | Checksum mismatch at same version forces stale | `SyncConflictResolver.resolveFileManifest()` |
| **Reading sessions** | Append-only | Skip if `sessionId` exists locally | `SyncConflictResolver.resolveSession()` |
| **Settings** | Automatic LWW | N/A (NSUbiquitousKeyValueStore handles it) | Built-in |

### 5.2 Conflict Flow

```
CloudKit push notification arrives
  → Fetch changed records (via CKFetchRecordZoneChangesOperation)
  → For each record:
      1. Find local counterpart by sync key
      2. If no local: insert (new from remote)
      3. If local exists: call SyncConflictResolver
      4. Apply winner to SwiftData via PersistenceActor
      5. Update local change token
```

### 5.3 Tombstone Lifecycle

1. User deletes a bookmark/highlight/annotation locally.
2. `SyncService.recordTombstone()` creates a `Tombstone` entry.
3. CloudKit record is updated with `isDeleted = true` and new `updatedAt`.
4. Remote devices receive the update, apply tombstone-aware resolution.
5. After 30 days, `SyncService.purgeStaleTombstones()` removes old tombstones.
6. CloudKit record can be hard-deleted after all devices have synced.

---

## 6. Migration and Versioning Plan

### 6.1 Schema Version Strategy

- A `schemaVersion` integer is stored both in NSUbiquitousKeyValueStore and as a field in a `VRSyncMetadata` CloudKit record.
- Every CloudKit record type includes a `recordSchemaVersion` field (integer) indicating which schema version wrote it.
- The app reads the remote `schemaVersion` before processing records.

### 6.2 Version Compatibility Rules

| Scenario | Behavior |
|----------|----------|
| Local == Remote | Normal sync |
| Local > Remote | Process remote records; ignore unknown fields in older records |
| Local < Remote | **Read-only mode**: display remote data but do not write. Prompt user to update the app. |

### 6.3 Forward-Compatible Record Format

- New fields added to CloudKit records use nullable types. Older app versions ignore unknown fields (CloudKit SDK drops them silently).
- `Locator` is stored as a JSON blob (`locatorJSON`) rather than individual CloudKit fields. New `Locator` fields (from WI-C00 annotation anchors or future formats) are automatically carried through as opaque JSON. Older app versions that decode the JSON will use `Codable` default (nil for unknown optional fields).
- Enum raw values (e.g., `BookFormat`) must never reuse deleted cases. New cases are appendable.

### 6.4 Data Migration on App Update

```swift
// Pseudocode — runs once on first launch after update
func migrateIfNeeded(from oldVersion: Int, to newVersion: Int) async {
    guard oldVersion < newVersion else { return }
    
    if oldVersion < 2 {
        // Example: V2 adds annotation anchors
        // Re-encode locators with new anchor fields
        await migrateLocatorsToV2()
    }
    
    if oldVersion < 3 {
        // Example: V3 changes reading session schema
        await migrateSessionsToV3()
    }
    
    // Update stored version
    NSUbiquitousKeyValueStore.default.set("\(newVersion)", forKey: "schemaVersion")
}
```

---

## 7. Privacy Implications

### 7.1 Data Residency

| Aspect | Detail |
|--------|--------|
| Storage location | User's personal iCloud container (private database) |
| Encryption at rest | Apple encrypts iCloud data at rest (AES-128 or AES-256) |
| End-to-end encryption | Available if user enables Advanced Data Protection |
| Developer access | **None** — private database is accessible only by the user's devices |
| Cross-user sharing | Not supported (private database only) |

### 7.2 Data Classification

| Data | Classification | Sensitivity |
|------|---------------|-------------|
| Book files | User content | Medium — may contain copyrighted material |
| Annotations/highlights | User-generated | Low — personal reading notes |
| Reading positions | Behavioral | Low — reading progress |
| Reading sessions | Behavioral | Low — timestamps and durations |
| Settings | Configuration | None |

### 7.3 Regulatory Compliance

- **GDPR (EU)**: User can delete all iCloud data via Settings > Apple ID > iCloud > Manage Storage. No developer-side data processing occurs. Privacy policy must disclose iCloud usage.
- **CCPA (California)**: Same as GDPR — no sale or sharing of data. Data is exclusively in user's iCloud account.
- **App Store guidelines**: Must declare iCloud usage in App Store Connect. Privacy Nutrition Label should list "Reading History" and "User Content" under "Data Linked to You" with "App Functionality" purpose.

### 7.4 Book File Privacy Considerations

- Imported book files may be copyrighted. iCloud stores them in the user's personal container — this is equivalent to the user copying a file to their own iCloud Drive, which is standard iOS behavior.
- The app does not share, transmit, or make book files accessible to anyone other than the signed-in Apple ID.
- Selective sync (Phase 3) lets users choose which books consume iCloud quota.

---

## 8. Implementation Phases

### Phase 1: Settings + Reading Position Sync (Low Risk, High Value)

**Technology**: NSUbiquitousKeyValueStore (settings), CloudKit custom zone (positions)

**Scope**:
- Sync `sortOrder`, `viewMode`, theme preferences via NSUbiquitousKeyValueStore
- Sync `ReadingPosition` records via CloudKit
- Feature-flagged behind `FeatureFlags.sync` (default OFF)
- `SyncStatusMonitor` shows sync state in Settings

**Why first**: Highest user pain point (losing reading position). Smallest data volume. NSUbiquitousKeyValueStore is nearly zero effort. Reading position has the simplest conflict resolution (LWW).

**Estimated effort**: M (medium)

**Dependencies**: WI-D00 (FeatureFlags must be shared reference)

### Phase 2: Annotation Sync (Medium Risk, High Value)

**Technology**: CloudKit custom zone

**Scope**:
- Sync `Bookmark`, `Highlight`, `AnnotationNote` records
- Tombstone tracking for deletes (existing `TombstoneStore`)
- CKSubscription for push-based change notification
- Incremental sync via zone change tokens

**Why second**: Annotations are the most valuable user data (irreplaceable). More complex conflict resolution but `SyncConflictResolver` already implements it. No large file transfer.

**Estimated effort**: L (large)

**Dependencies**: Phase 1, WI-C00 (annotation anchor schema for EPUB/PDF locators)

### Phase 3: Book File Sync (High Risk, Medium Value)

**Technology**: iCloud Documents

**Scope**:
- Upload imported book files to iCloud Documents container
- Download-on-demand via `FileAvailabilityStateMachine`
- `FileManifest` integrity verification
- Selective sync UI (user chooses which books to sync)
- Storage quota monitoring and warnings

**Why last**: Largest data volume, most iCloud quota impact. Books can be re-imported from original source. Complex error handling (quota exceeded, partial downloads, network interruptions).

**Estimated effort**: XL (extra large)

**Dependencies**: Phase 2

### Phase Summary

```
Phase 1 (M):  [Settings + Positions]  ← Start here
                     │
Phase 2 (L):  [Annotation Sync]       ← After WI-C00
                     │
Phase 3 (XL): [Book File Sync]        ← Highest risk, lowest urgency
```

---

## 9. Risks and Mitigations

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|-----------|------------|
| R1 | iCloud quota exhaustion (book files) | User cannot sync; upload fails | High (users with many PDFs) | Phase 3 adds selective sync + quota monitoring UI. Show warning at 80% quota. Sync metadata even when files can't sync. |
| R2 | Sync latency (CloudKit eventual consistency) | User opens book on Device B before position syncs from Device A | Medium | Show "Last synced: X ago" indicator. Manual pull-to-sync option. Position uses LWW so stale data is overwritten on next sync, not lost. |
| R3 | Offline-first requirement | User reads without connectivity; sync must catch up later | High (commute use case) | All writes go to local SwiftData first. `SyncService` queues pending changes and syncs on next connectivity. CloudKit has built-in offline queue for `CKModifyRecordsOperation`. |
| R4 | SwiftData + CloudKit integration complexity | Dual write path (local SwiftData + remote CloudKit) may diverge | Medium | `PersistenceActor` is the single writer for SwiftData. `SyncService` coordinates CloudKit reads/writes and calls `PersistenceActor` for local updates. No direct CloudKit-to-SwiftData bridging. |
| R5 | Data corruption during migration | Schema version mismatch causes data loss | Low | Read-only mode for newer schemas (Section 6.2). Backup local database before migration. Reversible migrations only. |
| R6 | Battery impact from frequent sync | Reading position updates on every page turn trigger CloudKit writes | Medium | Debounce position uploads (batch every 30 seconds, not on every page turn). Use `CKModifyRecordsOperation` batching. NSUbiquitousKeyValueStore has built-in coalescing. |
| R7 | iCloud account change | User signs out of iCloud or switches Apple ID mid-use | Low | Detect `NSUbiquitousKeyValueStore.didChangeExternallyNotification` with `NSUbiquitousKeyValueStoreAccountChange` reason. Reset sync state, keep local data, prompt re-sync with new account. |
| R8 | Large annotation sets on EPUB/PDF | Books with hundreds of highlights produce many CloudKit records | Low | Batch CloudKit operations (max 400 records per operation). Use zone-level change tokens for efficient incremental sync. |

---

## 10. Open Questions

| # | Question | Impact | Default if Undecided |
|---|----------|--------|---------------------|
| Q1 | **Selective sync**: Should users choose which books to sync? | UX complexity vs iCloud quota management | Yes — essential for quota control. Implement in Phase 3 with per-book toggle in Info sheet (WI-006). |
| Q2 | **Cross-Apple-ID sharing**: Should users be able to share annotations with other Apple IDs? | Major scope expansion (CloudKit shared zones, permissions UI) | No for V2. Defer to V3+. Would require CKShare and shared database, which is a significant architecture change. |
| Q3 | **Sync frequency vs battery**: How often should reading position sync? | Battery life vs data freshness | Debounce to 30-second intervals during active reading. Flush on app background (UIScene lifecycle). |
| Q4 | **Conflict resolution UI**: Should users ever see a conflict prompt? | UX complexity | No — all conflicts are resolved automatically. Annotation notes use LWW (not user prompt). Simpler UX, risk of losing a concurrent edit is low for a single-user app. |
| Q5 | **Full export/import**: Should there be a manual backup option (ZIP export) independent of iCloud? | Useful for users without iCloud or for migration to other apps | Defer. Useful but orthogonal to iCloud sync. Could be a separate feature. |
| Q6 | **Reading statistics sync strategy**: Sync raw sessions or aggregated stats? | Data volume vs accuracy | Sync raw `ReadingSession` records (append-only). Recompute `ReadingStats` locally from all sessions. This matches the existing `ReadingStats.recompute(from:)` pattern and avoids aggregate merge conflicts. |
| Q7 | **Initial sync on first enable**: Should enabling sync upload all existing local data? | First sync could be large (many books, annotations) | Yes, with progress indicator. Batch upload in background. Allow cancellation. |

---

## 11. Relationship to Existing Infrastructure

VReader already has sync infrastructure in `vreader/Services/Sync/` that was built for this purpose:

| Component | Status | Role in iCloud Sync |
|-----------|--------|-------------------|
| `SyncTypes.swift` | Implemented | Defines `FileAvailability`, `SyncConflictResult`, `Tombstone`, `FileManifest`, `SyncError` — all directly usable |
| `SyncConflictResolver.swift` | Implemented | All 7 conflict resolution algorithms ready to use |
| `FileAvailabilityStateMachine.swift` | Implemented | Tracks book file download state — maps directly to iCloud Documents on-demand download |
| `SyncService.swift` | Implemented (stub) | Actor-isolated coordinator. Currently a no-op (sync flag OFF). Needs CloudKit integration layer. |
| `SyncStatusMonitor.swift` | Implemented | Monitors and exposes sync status for UI |
| `TombstoneStore.swift` | Implemented | In-memory tombstone tracking with purge — needs SwiftData persistence for durability across app launches |
| `FeatureFlags.sync` | Implemented (OFF) | Guards all sync operations. Enable when Phase 1 is ready. |

**Gap analysis for implementation**:
1. `TombstoneStore` is in-memory only — needs SwiftData backing for persistence.
2. `SyncService` has no CloudKit integration — needs `CKContainer`, zone management, record mapping.
3. No CloudKit record ↔ SwiftData model mapping layer exists.
4. No NSUbiquitousKeyValueStore integration exists in `PreferenceStore`.
5. No UI for sync status, sync toggle, or quota display.
6. `ReadingPosition.deviceId` is empty string by default — needs real device identifier population.

---

## 12. References

- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)
- [Managing Files in iCloud](https://developer.apple.com/documentation/uikit/documents_data_and_pasteboard/synchronizing_documents_in_the_icloud_environment)
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine) (iOS 17+ — alternative to manual CKOperation management; evaluate for Phase 2)
- Existing sync infrastructure: `vreader/Services/Sync/`
- Existing conflict resolver: `vreader/Services/Sync/SyncConflictResolver.swift`
- Feature roadmap: `docs/codex-plans/2026-03-11-features-roadmap.md` (WI-015)
