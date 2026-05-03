# Feature #46 — Implementation Plan

**Source**: `docs/features.md` row #46 (PLANNED, High priority) — "WebDAV backup includes book files — materializing restore reconstructs library"
**GH issue**: #144
**Phase**: 1 of 2 (phase 2 = feature #47, lazy-load + selective picker)
**Status**: REVISED v2 (post-Codex audit 2026-05-03) — implementation can begin

## Revision history

- **DRAFT (v1)** — initial plan, sent to Codex for audit
- **v2 (this)** — incorporated Codex audit findings (see "Audit fixes applied" below)

## Goal

Turn "fresh restore = empty library" into "fresh restore = library back" without redesigning any reader / importer / indexer / delete code path. Preserve the invariant: every `Book` row points to a readable local file at the fingerprint-derived sandbox path.

## Audit fixes applied (Codex 2026-05-03)

| Finding | Resolution |
|---------|-----------|
| `Book.originalFilename` doesn't exist; `LibraryBookItem` doesn't expose `fingerprint`; `Book.fileExtension` doesn't exist either | **Added precondition WI-0a (expanded post-2nd-audit)**: (1) extend `PersistenceActor+Backup` with `fetchAllBooksForBackup()` returning a `BackupBookProjection` value type exposing the raw `DocumentFingerprint` fields. (2) Add `Book.originalExtension: String?` SwiftData field with migration that defaults existing rows to `BookFormat.fileExtensions.first` (so existing MOBI books render as `.azw3` in their first backup — known limitation, documented). (3) `BookImporter` is updated to persist the source URL's pathExtension into the new field. (4) Drop `originalFilename` from manifest entirely. |
| `ImportSource.restore` doesn't exist | **Added precondition WI-0b**: add the case + update tests asserting `allCases.count`. |
| `BookImporter.atomicCopyToSandbox` trusts existing final file without verifying bytes | **Materializer preflight**: when a final file exists at the fingerprint path, hash it. If SHA-256 doesn't match the manifest, delete and re-download. New test covers this. |
| MOBI extension lost in blob path (stored as `.azw3`) | Document this as known phase-1 limitation. Manifest carries the original extension via a new `originalExtension` field (cheap; no model change). Materializer writes the blob to a temp file with `originalExtension`, then `BookImporter` (which reads format from content + extension) handles it. |
| Plan's "no-op `restoreLibraryManifest()` on `BackupDataRestoring`" is API churn | **Dropped**. `WebDAVProvider.restore` extracts the manifest section directly from the ZIP. `BackupDataRestoring` protocol stays unchanged. |
| `BackupBlobStore` transport-neutral interface | **Added**: `BookFileMaterializer` depends on a new `BackupBlobStore` protocol (`download(path:)`, `existsWithSize(path:)`). `WebDAVClient` conforms. Future iCloud / S3 providers conform without touching the materializer. |
| MOVE 501 silent fallback to PUT+DELETE | **Refused**: server capability error with a clear message pointing to README's self-host requirements. No silent atomicity loss. |
| No production observer for `indexingNeededNotification` (Codex couldn't find one) | **Materializer posts one indexing notification per book** as today (preserves existing behavior); we'll audit the indexer separately. If future audit shows restored books aren't indexed, file as a follow-up bug. |
| Verify blob bytes (size only is insufficient) | **Materializer SHA-256-verifies** every downloaded blob against the manifest before importing. Mismatch = delete temp + report per-book failure (no import). |
| "v2 backup" terminology wrong (no archive-level versioning) | Renamed throughout to "manifest-extended backup" or "new-format backup". Per-section `schemaVersion` stays per-section. |
| `totalSizeBytes` semantics ambiguous when blobs join | **Defined**: `totalSizeBytes` = bytes of metadata sections only (current behavior). Add a separate `BackupMetadata.totalBlobBytes: Int64?` (optional, only present in manifest-extended backups). |
| Materialization partial failure must be distinct from metadata partial failure | New error case `BackupError.materializePartiallyFailed([BookMaterializeFailure])` where each failure carries `fingerprintKey`, `title`, `blobPath`, and structured `reason`. UI truncates for display; the data layer carries every failure (not a sample). Returned alongside (not instead of) the existing `restorePartiallyFailed` if both occur. |
| Pre-existing race on `WebDAVProvider.metadataCache` | Out of scope for this feature; file as separate bug. Don't fix in flight. |
| Tmp sweep 7 days too long | Reduced to 24h. |
| Materializer should be serial, not parallel | Confirmed: serial blob downloads with monotonic progress. No `@MainActor`. |

## Surface area (revised)

Files in scope:

| File | Lines | Touch |
|------|-------|-------|
| `vreader/Models/ImportSource.swift` | small | **WI-0b**: add `.restore` case |
| `vreader/Services/PersistenceActor+Backup.swift` | (read) | **WI-0a**: add `fetchAllBooksForBackup()` returning `[BackupBookProjection]` |
| `vreader/Services/Backup/BackupProvider.swift` | 85 | **add** `BackupError.materializePartiallyFailed`; **add** optional `totalBlobBytes` to `BackupMetadata` |
| `vreader/Services/Backup/BackupSectionDTOs.swift` | 209 | **add** `BackupLibraryManifestEnvelope` + `BackupLibraryEntry` (no `originalFilename`; with `originalExtension`) |
| `vreader/Services/Backup/BackupDataCollector.swift` | 220 | **add** `collectLibraryManifest()` using new persistence projection |
| `vreader/Services/Backup/BackupDataRestorer.swift` | 124 | **none** (materialization runs in WebDAVProvider) |
| `vreader/Services/Backup/WebDAVClient.swift` | 294 | **add** `MOVE` builder + `existsWithSize(at:)` PROPFIND Depth:0 + transport methods |
| `vreader/Services/Backup/WebDAVProvider.swift` | 352 (>300 ⚠) | **moderate** — call materializer; integrate blob upload via `BackupBlobStore`; restore-order change; tmp sweep |
| `vreader/Services/Backup/WebDAVProviderFactory.swift` | 93 | **add** `BookImporter` injection + materializer construction |
| `vreader/Services/Backup/BlobPath.swift` (NEW) | ~60 | content-addressed path utility |
| `vreader/Services/Backup/BackupBlobStore.swift` (NEW) | ~30 | transport-neutral blob store protocol |
| `vreader/Services/Backup/BookFileMaterializer.swift` (NEW) | ~150 | download + SHA-256 verify + preflight + import |
| `vreaderTests/Services/Backup/BlobPathTests.swift` (NEW) | ~80 | round-trip per format + edge cases |
| `vreaderTests/Services/Backup/BackupLibraryManifestTests.swift` (NEW) | ~80 | envelope round-trip |
| `vreaderTests/Services/Backup/BackupDataCollectorRestorerTests.swift` | 607 | extend with manifest-collection tests |
| `vreaderTests/Services/Backup/WebDAVClientTests.swift` | 294 | extend with MOVE + existsWithSize tests |
| `vreaderTests/Services/Backup/BookFileMaterializerTests.swift` (NEW) | ~250 | happy path, all-local skip, partial failure, corrupt-on-disk preflight, SHA-256 mismatch on download, MOBI extension preservation |
| `vreaderTests/Services/Backup/WebDAVProviderTests.swift` | 677 | extend with backup-with-manifest, restore-with-manifest, tmp sweep, MOVE 501 refusal, dedupe on second backup |
| `vreaderTests/Services/Backup/WebDAVBackupIntegrationTests.swift` | 222 | add round-trip: backup 2 books → wipe sandbox → restore → assert library + positions |

Files explicitly OUT of scope:
- `BookImporter.swift` — used as-is via `importFile(at:source: .restore)`. Materializer is the only new caller.
- `LibraryBookItem.swift` — `resolvedFileURL` continues to derive from `fingerprintKey` (underscored). No `BookFileState`.
- `BackupViewModel.swift` — progress reporting expanded but no new states. Size-confirmation dialog deferred to WI-9.
- `WebDAVSettingsView.swift` — same as above.
- `WebDAVProvider.metadataCache` race — pre-existing bug; file separately, do not fix in flight.

## Key design decisions

### Sandbox vs WebDAV blob naming

These are **two different naming schemes** and that's correct:

- **Local sandbox** (existing, do not change): `Application Support/ImportedBooks/<fingerprintKey-with-colons-as-underscores>.<ext>` — set by `BookImporter` and read by `LibraryBookItem.resolvedFileURL`.
- **WebDAV blob** (new): `VReader/books/<format>/<sha256>_<byteCount>.<ext>` — content-addressed, no colons, predictable across servers/tools.

The manifest carries both: the canonical `fingerprintKey` (so positions/annotations restore correctly) and the WebDAV-side `blobPath` (so the restorer knows where to GET).

### Why per-format subdirectory in the blob path

`books/<format>/<sha256>_<byteCount>.<ext>` not `books/<sha256>_<byteCount>.<ext>` because:
- Some WebDAV servers throttle directory enumeration above ~1000 entries; sharding by format buys headroom.
- Easier to manually inspect the server's blob store (group by file type).
- Trivial to compute, no ambiguity.

### Atomic upload pattern (temp + MOVE)

Direct `PUT` to the final blob path is not safe. Mid-upload kill leaves a half-written blob at the canonical path. Next backup's PROPFIND sees the file with wrong size, but if a server returns no `getcontentlength` for some reason, the bad blob would survive forever.

Pattern:
1. `PUT` bytes to `VReader/uploads/tmp/<uuid>.part`
2. `PROPFIND` the temp path; assert `getcontentlength == bytes.count`
3. `MOVE` (with `Destination:` header) from temp path to `VReader/books/<format>/<sha256>_<byteCount>.<ext>`
4. On any step failure: leave `.part` for sweep, do not retry MOVE blindly

Sweep: at backup start, list `uploads/tmp/`, delete entries with `getlastmodified` older than 24h. Idempotent. Cheap.

### Existence check via PROPFIND

`HEAD` is unreliable on some WebDAV servers; `WebDAVClient` already does PROPFIND for directory listings. Add a single-resource PROPFIND with `Depth: 0` that returns the entry (or 404). Compare `getcontentlength` to expected `byteCount`. If match, skip upload.

### Restore order

Today: extract ZIP → call each `restoreXxx(from:)` in turn. Books are silently skipped because the device has no matching `BookRecord` for the fingerprintKey.

New (when manifest present):
1. Extract ZIP → read `library-manifest.json` → list missing books (those whose `resolvedFileURL` doesn't exist locally)
2. For each missing book: GET blob from `blobPath` → write to a temp file → call `BookImporter.importFile(at:source:.restore)` → registers `BookRecord` row
3. Then run the existing per-section metadata restore (positions, annotations, etc.) — now they find the books

When manifest absent (v1 backup): skip step 1-2, run step 3 as today. Backward compatible.

### Where the materialization runs

The plan says "WebDAV provider downloads blobs first, then runs metadata restore." Concretely: `WebDAVProvider.restore(backupId:progress:)` adds a new phase between "download zip" and "apply restoreFiles loop". `BackupDataRestoring` protocol stays unchanged — `WebDAVProvider` extracts the manifest section from the ZIP itself and hands the parsed entry list to `BookFileMaterializer`. The materializer downloads + verifies + imports.

### `BookImporter` use vs direct file copy

We could just copy the blob bytes directly to `LibraryBookItem.resolvedFileURL` and insert a `BookRecord` row by hand. **Don't.** Reasons:
- `BookImporter` runs `MetadataExtractor` (title, author, cover) — bypassing it means the restored library has empty metadata.
- `BookImporter` runs `EncodingDetector` for TXT/MD — bypassing it means TXT files restore with wrong encoding.
- `BookImporter` posts `indexingNeededNotification` — bypassing it means search index doesn't get built for restored books.
- `BookImporter` handles dedupe (idempotent re-import).

So: download blob → write to temp file → call `BookImporter.importFile(at: tempURL, source: .restore)` → delete temp file. Slower than a raw copy but reuses every guarantee the importer already provides.

Need a new `ImportSource.restore` case (or use the existing `.documentPicker` if no behavioral difference is needed).

### What goes in the manifest

Per-book entry fields (`BackupLibraryEntry`):
- `fingerprintKey: String` — canonical `{format}:{sha256}:{byteCount}`
- `format: String` — `"epub"`, `"txt"`, etc.
- `sha256: String` — hex
- `byteCount: Int64`
- `originalExtension: String` — preserves "mobi"/"prc"/"azw" since `BookFormat` collapses them to `.azw3` (cheap; ~5 bytes)
- `title: String?` — display only; `BookImporter` re-extracts from the file
- `author: String?` — display only
- `addedAt: Date`
- `lastOpenedAt: Date?`
- `blobPath: String` — `books/<format>/<sha256>_<byteCount>.<ext>` (relative to WebDAV root)

Why include `title`/`author` even though `BookImporter` re-extracts them: phase 2's selective picker needs to show them before downloading the blob. Including them now costs ~100 bytes per book and avoids a phase-2 schema migration.

### Manifest schema versioning

`schemaVersion: Int` per the existing `BackupVersionedEnvelope` protocol. v1 = first emission. `BackupDataRestorer.decodeAndValidate` already enforces exact-match via `kBackupCurrentSchemaVersion` — bump to 2 (because adding a new section IS a schema change for the archive as a whole, even though existing sections are unchanged).

Wait — actually the schema version is per-section, not per-archive. So `library-manifest.json` carries its own `schemaVersion: 1` and the other sections stay at 1. `kBackupCurrentSchemaVersion` doesn't need to bump.

Confirm by reading existing code: yes, each envelope has its own `schemaVersion`, all currently 1. New section = new envelope at v1. No bump needed.

## File-by-file changes

### New file: `vreader/Services/Backup/BlobPath.swift` (~60 lines)

```swift
// Purpose: Maps (format, sha256, byteCount) ↔ WebDAV-safe blob path.
// Path layout: VReader/books/<format>/<sha256>_<byteCount>.<ext>
// Colons in fingerprintKey are not safe across all WebDAV servers, so
// the blob path uses only [0-9a-f_./].
enum BlobPath {
    static let booksRoot = "VReader/books"
    static func make(format: BookFormat, sha256: String, byteCount: Int64) -> String { ... }
    static func parse(_ path: String) -> (format: BookFormat, sha256: String, byteCount: Int64)? { ... }
}
```

Test file: `vreaderTests/Services/Backup/BlobPathTests.swift` — round-trip per format + invalid-input cases.

### Modified: `BackupSectionDTOs.swift`

Add at end of file:

```swift
// MARK: - Library Manifest

struct BackupLibraryManifestEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let books: [BackupLibraryEntry]
}

struct BackupLibraryEntry: Codable, Sendable, Equatable {
    let fingerprintKey: String       // canonical {format}:{sha256}:{byteCount}
    let format: String                // "epub", "azw3", "txt", "md", "pdf"
    let sha256: String                // hex
    let byteCount: Int64
    let originalExtension: String     // preserves "mobi" / "prc" / "azw" since BookFormat collapses them to .azw3
    let title: String?
    let author: String?
    let addedAt: Date
    let lastOpenedAt: Date?
    let blobPath: String              // "books/<format>/<sha256>_<byteCount>.<canonical-ext>"
}
```

### New: `BackupBookProjection` value type (in `PersistenceActor+Backup.swift`)

Plain Sendable struct exposing the raw fingerprint fields the manifest collector needs. `LibraryBookItem` doesn't expose `fingerprint`; this projection bridges the gap without leaking SwiftData `@Model` instances across the actor boundary.

```swift
struct BackupBookProjection: Sendable, Equatable {
    let fingerprintKey: String
    let format: String              // canonical BookFormat.rawValue
    let sha256: String
    let byteCount: Int64
    let originalExtension: String   // from new Book.originalExtension field (added in WI-0a)
    let title: String?
    let author: String?
    let addedAt: Date
    let lastOpenedAt: Date?
}
```

Add to `PersistenceActor`:

```swift
extension PersistenceActor {
    func fetchAllBooksForBackup() async throws -> [BackupBookProjection] {
        // Read SwiftData Book entities; build projections; return.
        // originalExtension = book.originalExtension (new field added in this same WI)
    }
}
```

`Book.originalExtension: String?` is **added in this WI** (WI-0a). Migration: existing rows default to `BookFormat(rawValue: book.format)?.fileExtensions.first`. `BookImporter` is updated to persist the source URL's pathExtension into this field on every new import. This is the only model change in feature #46.

Known limitation: existing MOBI/PRC/AZW books were imported as `.azw3` with no source extension preserved; their first backup will carry `originalExtension == "azw3"` and they will restore as `.azw3` on a fresh device. Books opened with Foliate work either way. New imports preserve the original extension.

### Modified: `BackupDataCollector.swift`

Add method:

```swift
func collectLibraryManifest() async throws -> Data {
    let projections = try await persistence.fetchAllBooksForBackup()
    let entries: [BackupLibraryEntry] = projections.compactMap { p in
        guard let format = BookFormat(rawValue: p.format) else { return nil }
        return BackupLibraryEntry(
            fingerprintKey: p.fingerprintKey,
            format: p.format,
            sha256: p.sha256,
            byteCount: p.byteCount,
            originalExtension: p.originalExtension,
            title: p.title,
            author: p.author,
            addedAt: p.addedAt,
            lastOpenedAt: p.lastOpenedAt,
            blobPath: BlobPath.make(format: format, sha256: p.sha256, byteCount: p.byteCount)
        )
    }
    let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: entries)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(envelope)
}
```

Add to `BackupDataCollecting` protocol (in `WebDAVProvider.swift`):

```swift
func collectLibraryManifest() async throws -> Data
```

### Modified: `WebDAVClient.swift`

Add MOVE builder + transport method:

```swift
/// Builds a MOVE request. WebDAV `MOVE` requires `Destination:` header.
func buildMOVERequest(fromPath: String, toPath: String, overwrite: Bool = false) -> URLRequest {
    var request = URLRequest(url: buildURL(path: fromPath))
    request.httpMethod = "MOVE"
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
    request.setValue(buildURL(path: toPath).absoluteString, forHTTPHeaderField: "Destination")
    request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")
    return request
}

/// Builds a Depth:0 PROPFIND for a single resource.
func buildPROPFINDExistsRequest(path: String) -> URLRequest { /* same as buildPROPFINDRequest but Depth:0 */ }
```

Extend `WebDAVTransport`:

```swift
protocol WebDAVTransport: Sendable {
    // ... existing methods
    func move(fromPath: String, toPath: String) async throws
    func existsWithSize(at path: String) async throws -> Int64?  // nil = 404, value = byte count
}
```

Implement on `WebDAVClient`. Apply MKCOL trailing-slash lesson: normalize paths if needed. MOVE responds 201/204 on success, 412 on Overwrite=F + destination exists.

### New: `BackupBlobStore` protocols (~50 lines)

Transport-neutral blob interface the materializer depends on. WebDAV is one impl; future iCloud / S3 / etc. conform without touching materializer code.

Split read vs write so the materializer (read-only on restore) doesn't carry write capabilities:

```swift
/// Read side — used by BookFileMaterializer on restore.
protocol BackupBlobReading: Sendable {
    /// Returns the blob's byte count, or nil if the path doesn't exist.
    func existsWithSize(at path: String) async throws -> Int64?

    /// Downloads the full blob at `path`.
    func download(from path: String) async throws -> Data
}

/// Write side — used by WebDAVProvider.backup to upload blobs.
protocol BackupBlobWriting: Sendable {
    /// Publishes `data` atomically at `path`. The implementation guarantees
    /// the blob is either fully present or absent — never partially written.
    /// `expectedByteCount` enables size verification before commit.
    /// Returns `.uploaded` on a real upload, `.alreadyExists` if the
    /// destination already had matching bytes (skip dedup case).
    func putBlobAtomically(
        _ data: Data,
        to path: String,
        expectedByteCount: Int64
    ) async throws -> BlobPutResult
}

enum BlobPutResult: Sendable, Equatable {
    case uploaded
    case alreadyExists
}

enum BackupBlobStoreError: Error, Sendable, Equatable {
    case serverCapabilityMissing(String)   // e.g. "MOVE"
    case sizeAfterPutMismatch(expected: Int64, actual: Int64)
    case underlying(String)                 // wraps WebDAVError, etc.
}
```

`WebDAVClient` (or a thin adapter on top of it) adopts both. Materializer imports only `BackupBlobReading`.

### New: `BookFileMaterializer.swift` (~150 lines)

Pulls book download/import logic out of `WebDAVProvider`. Single responsibility: given a list of `BackupLibraryEntry`, download missing blobs, verify, and import them.

```swift
final class BookFileMaterializer: Sendable {
    init(blobStore: BackupBlobReading, importer: BookImporting, sandboxBooksDirectory: URL, tempDirectory: URL)

    /// Splits entries into (alreadyLocal, needsDownload). For an entry whose
    /// resolvedFileURL exists locally, hashes the file and verifies SHA-256
    /// against manifest — mismatch counts as "needsDownload" (corrupt local file
    /// from prior crashed import that BookImporter would silently re-trust).
    func classify(_ entries: [BackupLibraryEntry]) async -> (alreadyLocal: [BackupLibraryEntry], needsDownload: [BackupLibraryEntry])

    /// Downloads + verifies + imports each entry serially. Verification order:
    /// (1) byte count matches manifest (cheap, catches truncation), (2) SHA-256
    /// matches manifest (catches corruption), (3) BookImporter's resulting
    /// ImportResult.fingerprintKey matches manifest (catches extension/format
    /// confusion). Reports progress 0..1 across the batch.
    func materialize(_ entries: [BackupLibraryEntry], progress: @Sendable (Double) -> Void) async -> [MaterializeResult]
}

struct MaterializeResult: Sendable {
    let entry: BackupLibraryEntry
    let outcome: Outcome
    enum Outcome: Sendable {
        case alreadyLocal                       // local file existed + hash verified
        case downloaded(ImportResult)
        case downloadFailed(BackupBlobStoreError)
        case sizeAfterDownloadMismatch(expected: Int64, actual: Int64)
        case sha256Mismatch(expected: String, actual: String)
        case importFailed(ImportError)          // BookImporter rejected (corrupt EPUB etc.)
        case fingerprintMismatchAfterImport(expected: String, actual: String)
    }
}
```

Materialize's per-entry algorithm:
1. Local-file path exists → hash → match? → `.alreadyLocal`. Mismatch → fall through to redownload.
2. blob.download → bytes
3. `bytes.count == entry.byteCount`? → no → `.sizeAfterDownloadMismatch`
4. SHA-256(bytes) == entry.sha256? → no → `.sha256Mismatch`
5. Write bytes to `tempDirectory/<sha256>_<byteCount>.<originalExtension>`
6. `BookImporter.importFile(at: tempURL, source: .restore)` → result
7. `result.fingerprintKey == entry.fingerprintKey`? → no → `.fingerprintMismatchAfterImport`
8. Delete temp file
9. `.downloaded(result)`

Failures don't abort the loop — every entry gets a result; caller decides how to surface partial failure.

Reasons to split this out:
- Keeps `WebDAVProvider.swift` from growing further (already 352 LOC, over the guideline).
- Materialization logic is independently testable with a mock `BackupBlobStore` + mock `BookImporting`.
- Phase 2 (feature #47, lazy-on-tap) reuses this same materializer, driven from a different caller (the reader's "open book" flow when `BookFileState == .remoteOnly`).
- Transport-neutral via `BackupBlobStore` — future providers don't change materializer code.

### Modified: `WebDAVProvider.swift`

Three changes:

1. **`backup(progress:)`** — after collecting metadata, also collect the manifest. Then for each book in the manifest:
   - PROPFIND the blob path
   - If 404 OR `getcontentlength` mismatch → upload via temp+MOVE
   - Else skip
   
   Progress allocation revision: collect (0→0.3), missing-blob compute (0.3→0.35), blob uploads (0.35→0.85), zip create (0.85→0.9), zip upload (0.9→1.0). Most users won't have new blobs (dedupe), so the blob-upload phase finishes fast for repeat backups.

2. **`restore(backupId:progress:)`** — after downloading the ZIP and validating it, look for `library-manifest.json`:
   - If present → decode → call `materializer.materialize(_:progress:)` → continue with existing per-section restore loop
   - If absent → continue directly with existing per-section restore loop (v1 compat)
   
   Progress: download (0→0.4), materialize (0.4→0.85), per-section apply (0.85→1.0). When the manifest is absent or all books are already local, materialize phase finishes immediately.

3. **`tmpSweep()`** — call at the start of `backup(progress:)`. List `VReader/uploads/tmp/`, delete entries with `getlastmodified` older than 24h. Best-effort: errors logged, do not abort backup.

### Modified: `WebDAVProviderFactory.swift`

Inject `BookImporter` and the temp directory URL into the materializer when constructing the provider.

### New tests

| Test file | Coverage |
|-----------|----------|
| `BlobPathTests.swift` | Round-trip per format, invalid format, parse failures |
| `BackupLibraryManifestTests.swift` | Envelope round-trip, schemaVersion guard |
| `BackupDataCollectorManifestTests.swift` | Library of 3 books → manifest has 3 entries with correct fields |
| `WebDAVClientMOVEAndExistsTests.swift` | MOVE request shape (Destination header), exists 200/404/207 paths |
| `BookFileMaterializerTests.swift` | All-local, all-missing, partial-failure, blob size mismatch redownload |
| `WebDAVProviderBlobUploadTests.swift` | temp+MOVE happy path, mid-upload abort leaves no final blob, dedupe via PROPFIND, tmp sweep |
| `WebDAVProviderRestoreOrderTests.swift` | manifest-extended ZIP → materialize then metadata; v1 ZIP (no manifest) → metadata only |

Augment existing `WebDAVBackupIntegrationTests.swift` if the Docker server is up:
- Backup library of 2 books → assert blobs exist at expected paths
- Restore to empty library → assert 2 books visible with positions
- Repeat backup → second uploads zero blobs (dedupe)

## Sequencing (revised work items)

Each WI: RED test first, then GREEN, then REFACTOR. Each WI ships in its own PR with version bump, audited by Codex before merge.

Two new precondition WIs (0a, 0b) added per audit. The original WIs 1-10 mostly stand but with revised scope.

| WI | What | Files touched | Estimated PR size |
|----|------|--------------|-------------------|
| 0a | **Precondition**: `PersistenceActor+Backup.fetchAllBooksForBackup()` returning `BackupBookProjection` value type with raw `DocumentFingerprint` fields. Tests. | 1 modified, 1 new test | small |
| 0b | **Precondition**: `ImportSource.restore` case + update tests asserting `allCases.count`. | 1 modified, ~2 test files updated | trivial |
| 1 | `BlobPath` utility — `(format, sha256, byteCount, originalExtension) ↔ books/<format>/<sha256>_<byteCount>.<ext>` round-trip. | 1 new, 1 new test | small |
| 2 | `BackupLibraryManifestEnvelope` + `BackupLibraryEntry` DTOs (with `originalExtension`, no `originalFilename`). | 1 modified, 1 new test | small |
| 3 | `WebDAVClient.move(fromPath:toPath:)` + `existsWithSize(at:)` (Depth:0 PROPFIND) + transport methods + tests. | 1 modified, 1 modified test | medium |
| 4 | `BackupBlobStore` protocol + `WebDAVClient` conformance. | 1 new, 1 modified | trivial |
| 5 | `BookFileMaterializer` + tests with mock blob store + mock importer. Tests cover: all-local skip, all-missing happy path, partial download failure, SHA-256 mismatch on download, corrupt local file (preflight rehash), MOBI `originalExtension` preservation. | 1 new, 1 new test | medium |
| 6 | `BackupDataCollector.collectLibraryManifest()` consumes WI-0a's projection. | 1 modified, test added to existing file | small |
| 7 | `WebDAVProvider.backup` integrates materializer's reverse direction (uploadBlob via temp+MOVE), adds tmp sweep, MOVE 501 refusal. | 1 modified, test extended | medium |
| 8 | `WebDAVProvider.restore` adds materialization phase (manifest extraction → materializer.materialize → existing per-section restore). | 1 modified, test extended | medium |
| 9 | Docker integration round-trip test. | 1 modified | medium |
| 10 | `BackupViewModel` + `WebDAVSettingsView`: per-blob progress, size-confirmation dialog (>100 MB missing), per-book failure summary in restore result. | 2 modified, 1 new test | medium |
| 11 | `docs/architecture.md` Backup section update, `docs/manual-test-checklist.md` recipe, feature #46 → DONE in `docs/features.md`. | 3 modified | small |

Critical path: 0a → 0b → 1, 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11.

Some WIs can ship in parallel (WI-1 and WI-2 are independent; WI-3 and WI-4 are independent of WI-1/2). But sequencing as listed keeps PRs small and audit-friendly.

UI work (WI-10) is gated on the data plumbing landing first.

## Risks + mitigations

| Risk | Mitigation |
|------|-----------|
| `BookImporter.importFile(at:source:)` is `@MainActor` or has hidden side effects that break in the restore path | Read full BookImporter contract before WI-4. If `@MainActor`-only, materializer becomes `@MainActor` or uses a hop. |
| `MOVE` not supported on some WebDAV servers (rare; rclone, Apache mod_dav, Nginx dav_module all support it) | **Refuse with `BackupError.serverCapabilityMissing("MOVE")`** and surface a clear error pointing to README's self-host requirements. No silent atomicity loss. |
| Tempdir on iOS sandbox is small (256MB?) — large book downloads fail | Use `FileManager.default.temporaryDirectory` (which is Caches-backed and can grow); alternative: stream blob directly to final sandbox path with `.tmp` suffix, rename on success. Decide in WI-4. |
| `BookImporter` posts `indexingNeededNotification` — restore of 100 books posts 100 notifications and triggers 100 indexing runs | Investigate during WI-4. Either: batch via a `restoreInProgress` flag the indexer respects, or accept the cost (indexing is async + idempotent). |
| Server `getcontentlength` not always returned (some setups omit it) | Fallback existence check: PROPFIND 207 = exists, 404 = missing. If size unknown, trust the existence and don't re-upload. Gives up dedupe-by-size detection of partial uploads, but tmpSweep catches those. |
| Mid-restore app kill leaves partial sandbox state | Each successful `BookImporter.importFile` is atomic. Re-running restore is idempotent — already-imported books skip download. No special crash recovery needed. |
| Concurrent backups from two devices race on `MOVE` of identical content | Content-addressed final paths converge. Worst case: second MOVE fails because destination exists; we treat 412 as "fine, blob is already there". |
| `BookFormat` enum doesn't include `mobi` (Foliate handles azw3 + mobi via the same path) | Verify in WI-1. If `mobi` is missing from the enum, blob path code needs a special case OR add `mobi` to the enum (separate small PR before WI-1). |

## Backward compat

Three scenarios:

1. **Old client restores new backup**: not possible without distributing this code.
2. **New client restores old backup (v1)**: works as today. No `library-manifest.json` → skip materialize phase → metadata-only restore (skips missing books silently). User sees the same empty library they did before, but no regression.
3. **New client restores manifest-extended backup**: full materializing restore.

## Open questions — RESOLVED (Codex audit)

| # | Question | Resolution |
|---|----------|-----------|
| 1 | `BookImporter` injection: A (provider-side) vs B (`BackupDataRestoring` protocol)? | **A**, with a transport-neutral `BackupBlobStore` protocol between materializer and WebDAV. `BackupDataRestoring` stays unchanged. |
| 2 | `ImportSource.restore` new case vs reuse `.documentPicker`? | **Add the case**. Reusing `.documentPicker` is wrong provenance and impossible to branch later. |
| 3 | Indexing notification amplification? | **Post per-book as today** (no production observer found, so not a real amplification problem). If a future audit shows restored books aren't indexed, file as a separate bug. |
| 4 | Manifest metadata — too much? | Title/author/format/dates **kept**. `originalFilename` **dropped** (no source field). `originalExtension` **added** (cheap; preserves MOBI extension on restore). |
| 5 | `BookFileMaterializer` location? | **Stay in `Services/Backup/`** for now. Add a subdirectory only when phase 2's lazy-download coordinator + `BookFileState` arrive. |
| 6 | MOVE 501 fallback? | **Refuse with a clear server-capability error**. No silent atomicity loss. Document required server capabilities in README. |
| 7 | Tmp file lifetime? | **24h**, not 7 days. Temp uploads are disposable. |
| 8 | MOBI in BookFormat enum? | **Don't add `.mobi`** (would change fingerprint identity for future imports). Keep MOBI under `.azw3`. Manifest carries `originalExtension` so restore writes `.mobi` to temp file → BookImporter detects format from content. |

## Acceptance gate

Plan v2 incorporates all Codex audit findings. Implementation can begin starting at WI-0a.

## Audit reference

Full Codex audit (read-only sandbox, 2026-05-03): see conversation log. Key findings codified in "Audit fixes applied" table at top of this doc.
