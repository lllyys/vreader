# Feature #47 — Implementation Plan

**Source**: `docs/features.md` row #47 (PLANNED, Medium priority) — "WebDAV restore — selective book picker + lazy-on-tap downloads"
**GH issue**: #145
**Phase**: 2 of 2 (phase 1 = feature #46, VERIFIED in v3.11.1)
**Depends on**: feature #46 — VERIFIED in v3.11.1. The blob layout
(`VReader/books/<format>/<sha256>_<byteCount>.<ext>`), `BackupLibraryEntry`
manifest schema, `BookFileMaterializer`, and `WebDAVBlobStore` already exist
and are reused as-is.
**Status**: v3 — Round-2 surface fixes applied (5 items). Plan is implementation-ready for Gate 3.

## Revision history

- **DRAFT (v1)** — initial plan; sent to Codex for Gate-2 audit.
- **v1 audit (Codex 2026-05-03)** — verdict: **SPLIT**. 11 findings. Primary structural change: GC operation moved out to feature #51. Other findings drive v2 plan revision.
- **DRAFT (v2)** — addresses 5 High + 3 Medium Codex Round-1 findings throughout the plan body.
- **v2 audit (Codex 2026-05-03)** — verdict: **REVISE-with-list**. 5 surface items: `.local` manifest must verify-and-upload (not just emit); blob verifier ownership unclear; background-session test seam at wrong abstraction level; `LazyDownloadTaskMeta` needs `schemaVersion` for forward compat; authenticated WebDAV download request construction missing.
- **v3 (this)** — Round-2 surface fixes applied. See "Audit fixes applied — Round 2" below. Plan is Gate-3 ready.

## Audit fixes applied — Round 2 (Codex 2026-05-03)

| # | Finding | Resolution |
|---|---------|-----------|
| 1 | `.local` manifest emit currently "always include" but `WebDAVProvider.uploadBlobs` silently skips missing sandbox files — manifest can seal pointing at a blob that wasn't uploaded. | **`.local` rows now require verified upload before emit.** New backup phase order: (1) `BookFileMaterializer.classify` rehashes every `.local` row's local file; mismatch demotes to `.failed` (or restores from blob if available). (2) `WebDAVProvider.uploadBlobs` aborts the whole backup on any individual upload failure (was: silent skip). (3) Only post-upload-confirmed rows enter the manifest as `.local`. Rationale: a manifest is a contract that every entry's blob exists on the server. |
| 2 | Blob-verifier ownership unclear: v2 said collector uses `BackupBlobReading.existsWithSize`, but `BackupDataCollector` has no blob-store dependency and `WebDAVProviderFactory` builds collector before `WebDAVProvider` owns `WebDAVBlobStore`. | **Move state-aware manifest filtering into `WebDAVProvider`, not `BackupDataCollector`.** The collector emits a "raw" manifest of every Book row with `fileState`. The provider, which owns `WebDAVBlobStore`, applies the policy table during the upload phase: for each row, calls `existsWithSize(at: blobPath)` and decides emit/skip. Avoids cross-actor dependency injection through the factory. Manifest serialization happens after the policy filter, before ZIP archive write. |
| 3 | `BackgroundDownloadSessionFactory -> URLSession` test seam too concrete — tests can't realistically synthesize delegate events through a real `URLSession`. | **Replace factory with `BackgroundDownloadSessioning` protocol.** Surface: `func allTasks() async -> [URLSessionDownloadTask]`, `func downloadTask(with: URLRequest) -> URLSessionDownloadTask`, `func cancel(_ task: URLSessionDownloadTask)`, `func invalidateAndCancel()`. Production `URLSessionBackgroundSession` wraps a real `URLSession`. Mock `MockBackgroundSession` supports `simulateProgress(taskID: bytesWritten:)`, `simulateCompletion(taskID:tempURL:)`, `simulateError(taskID:Error)` — gives tests deterministic control over the lifecycle without round-tripping through real URLSession. |
| 4 | `LazyDownloadTaskMeta` forward compat: future required fields will break persisted in-flight tasks (URLSession persists across launches + OS upgrades). | **Add `schemaVersion: Int` to `LazyDownloadTaskMeta`.** Decoder accepts schemaVersion 1 (this release) onwards. Future versions add fields as Optional with safe defaults. On schemaVersion mismatch (e.g., a v1 client sees a v2 task because user downgraded), the coordinator treats the task as orphaned: cancel it, mark the row `.failed`, user retries. |
| 5 | Lazy download lacks WebDAV authenticated request construction. v2 extracts the finalizer but doesn't show how `LazyDownloadCoordinator.enqueue` builds an authenticated `URLRequest` from `blobPath` + saved Keychain credentials. | **New `WebDAVDownloadRequestBuilder`** in `vreader/Services/Backup/` (~40 LOC). Takes `WebDAVClient` (which already owns serverURL + credentials), exposes `func authenticatedRequest(for blobPath: String) -> URLRequest` that mirrors `WebDAVClient.buildGETRequest(path:)` shape. `LazyDownloadCoordinator.enqueue(_ entry:)` calls `requestBuilder.authenticatedRequest(for: entry.blobPath)` then passes the URLRequest to `session.downloadTask(with:)`. The coordinator's init takes the request builder; `\.lazyDownloadCoordinator` Environment key wiring in `VReaderApp` constructs both from the live Keychain creds. |

## Audit fixes applied — Round 1 (Codex 2026-05-03)

| # | Finding | Severity | Resolution |
|---|---------|----------|-----------|
| 1 | GC race-condition: 60-second grace insufficient; another device backing up DURING our GC run could publish a blob we're about to delete. | High | **Carved out — GC is now feature #51.** v2 plan removes WI-7 (RemoteBlobGarbageCollector + GC dialog) entirely. |
| 2 | Backup collector wrong/incomplete for non-local books: `fetchAllBooksForBackup()` emits every Book row with no file-state signal; `WebDAVProvider.uploadBlobs` skips missing sandbox files but the manifest still references them. | High | **v2 adds `fileState` + `blobPath` to `BackupBookProjection`; `BackupDataCollector.collectLibraryManifest` filters per the policy table below.** |
| 3 | Missed read path: `ShareSheet.activityItems(for:)` blindly returns `book.resolvedFileURL` — sharing a `remoteOnly` book hands out a nonexistent file URL. | High | **v2 disables Share for non-`.local` rows in the Library context menu.** Lazy-download-then-share is a future enhancement (documented, not built). |
| 4 | Lazy download session design compile-hostile: `LazyDownloadCoordinator: @MainActor ... URLSessionDownloadDelegate` won't work — delegate callbacks are non-main protocol requirements. | High | **v2 splits the coordinator**: nonisolated `final class LazyDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable` receives URLSession callbacks; forwards to `@MainActor @Observable LazyDownloadCoordinator` via `Task { @MainActor in ... }`. |
| 5 | Background URLSession lifecycle under-specified: needs `taskDescription` mapping `taskIdentifier → fingerprintKey/blobPath/sha/bytes`, `getAllTasks()` reattach on launch, completion-handler storage, crash recovery for `.downloading` rows, test seam. | High | **v2 spells out**: `taskDescription` carries a JSON-encoded `LazyDownloadTaskMeta`; `URLSession.getAllTasks()` reattach at coordinator init; `.downloading` rows with no live task at launch flip to `.failed`; `UIApplicationDelegateAdaptor` retains `handleEventsForBackgroundURLSession` completion handlers until `urlSessionDidFinishEvents`. Test seam via `BackgroundDownloadSessionFactory` protocol with deterministic mock. |
| 6 | Coordinator can't reuse `BookFileMaterializer.download` directly: WebDAV downloads need base URL + Basic auth from `WebDAVClient`; materializer only downloads `Data` via `BackupBlobReading`. | Medium | **v2 extracts `BookFileImportFinalizer`** (verify + write + import) from `BookFileMaterializer`. Both `BookFileMaterializer` (in-memory `Data` path, restore-all) and `LazyDownloadCoordinator` (file-URL path, background streaming) call the finalizer on completion. |
| 7 | WI-3 + WI-4 too crammed; WI-3 hides session lifecycle + network policy + notifications + reattach + cancellation + retry + tests; WI-4 hides catalog + selective restore + manifest extraction + metadata ordering + provider API. | Medium | **v2 de-crams**: WI-3 → WI-3a (delegate split + happy-path enqueue/cancel), WI-3b (lifecycle persistence: taskDescription / reattach / crash recovery), WI-3c (`WebDAVNetworkPolicy` + Wi-Fi gating). WI-4 → WI-4a (`RemoteBookCatalog`), WI-4b (`SelectiveRestoreCoordinator`). |
| 8 | `RemoteBookCatalog` references `ZIPWriter.extractEntry` with wrong API — actual is static `ZIPWriter.extractEntry(named:from:)`. | Low | **v2 uses the correct static API**: `try ZIPWriter.extractEntry(named: "library-manifest.json", from: zipData)`. |
| 9 | `WebDAVProviderFactory` cannot just "wire coordinator into provider"; reader/library UI need an environment/service owner. | Medium | **v2 introduces `\.lazyDownloadCoordinator` SwiftUI Environment key** (mirrors `BookImporterEnvironment`); `VReaderApp` constructs and injects; Library/Reader read it. `LazyDownloadCoordinator` is **not** wired through `WebDAVProviderFactory.make(...)` (that factory builds the on-demand backup/restore provider, which has nothing to do with persistent download lifecycle). |
| 10 | Materializer `classify` using `originalExtension` imperfect for MOBI/PRC duplicates — canonical extension wins for same-content imports. | Low | **No change** — same trade-off as feature #46. `originalExtension` is best-effort metadata; canonical extension drives sandbox path uniqueness. |
| 11 | `BackupBookProjection.originalExtension` non-optional vs `Book.originalExtension` optional: projection coalesces. | Low | **No change** — intentional, audited in feature #46. |

## Open questions answered (Codex Round 1)

- **Q1** (`remoteByteCount` vs reuse `fileByteCount`): Use existing `fileByteCount`. Manifest byte count equals fingerprint byte count.
- **Q3** (URLSession delegate isolation): **Resolved per finding #4**. Nonisolated `LazyDownloadDelegate` adapter forwards to `@MainActor LazyDownloadCoordinator`.
- **Q4** (GC transport-neutrality): Keep WebDAV-specific. **Carved out to #51.**
- **Q8** (Wi-Fi gating scope): Gate backup, restore-all, selective materialization, lazy downloads. Do NOT gate connection test or backup-list refresh.

## Goal

Phase 1 (feature #46) gives a fresh device its full library back by downloading every book up front. That is correct but expensive: large libraries take a long time, secondary devices waste storage, and offline users can't choose to defer. Phase 2 introduces **the file-state distinction**: a book row may exist locally without its bytes, and may flip between `.local` ↔ `.remoteOnly` via user action.

Concrete success criteria:

1. After a "Restore selectively…" pass, the user has exactly the rows they checked as `.local` and the rest as `.remoteOnly` (visible with a cloud-download icon and size).
2. Tapping a `.remoteOnly` row triggers a download (`URLSessionConfiguration.background(...)` + `isDiscretionary = true`); on success the row flips to `.local` and the reader opens at the saved position.
3. A "Wi-Fi only" toggle (default ON) defers cellular downloads until Wi-Fi is available, with a visible "waiting for Wi-Fi" indicator.
4. Existing fully-local libraries (people who never touch selective restore) see no behavior change — every existing reader/importer/indexer/delete/share path keeps working.
5. The Library "Share" action is correctly disabled for non-local rows (no nonexistent-URL share crash).

(Acceptance criterion #4 from v1 — "Clean unused remote files" — moved to feature #51.)

## Surface area

Files in scope (current line counts; touch type):

| File | Lines | Touch |
|------|-------|-------|
| `vreader/Models/Book.swift` | 148 | **modified** — add `var fileState: String` (default `"local"`) and `var blobPath: String?`. New SchemaV6 introduces these columns. |
| `vreader/Models/BookFileState.swift` (NEW) | ~50 | enum + helpers (`raw`, transitions, `isReadable`, `canDownload`). Sendable + Codable. |
| `vreader/Models/Migration/SchemaV6.swift` (NEW) | ~30 | additive lightweight migration; existing rows default `fileState = "local"`, `blobPath = nil`. |
| `vreader/Models/Migration/SchemaV1.swift` | 86 | **modified** — append `SchemaV6.self` to `VReaderMigrationPlan.schemas`. |
| `vreader/Models/LibraryBookItem.swift` | 77 | **modified** — add `fileState: BookFileState` and `blobPath: String?`. |
| `vreader/Services/PersistenceActor.swift` | 182 | **modified** — `BookRecord` adds `fileState: BookFileState`, `blobPath: String?`. `bookToRecord` populates them. `insertBook` accepts them (defaults `.local` / `nil`). |
| `vreader/Services/PersistenceActor+Library.swift` | 94 | **modified** — `fetchAllLibraryBooks` exposes `fileState` and `blobPath`. |
| `vreader/Services/PersistenceActor+RemoteOnly.swift` (NEW) | ~80 | feature-local extension: `insertRemoteOnlyBookRecords(_:)`, `setBookFileState(...)`, `setBookBlobPath(...)`. |
| `vreader/Services/PersistenceActor+Backup.swift` | 451 | **modified** — `BackupBookProjection` adds `fileState: BookFileState` and `blobPath: String?`. `fetchAllBooksForBackup()` reads both. |
| `vreader/Services/Backup/BackupDataCollector.swift` | 205+ | **modified** — `collectLibraryManifest()` filters projections per the manifest emit policy table below. Uses `BackupBlobReading.existsWithSize(at:)` to verify presence for `.remoteOnly` / `.failed` rows. |
| `vreader/Services/Backup/BookFileImportFinalizer.swift` (NEW) | ~120 | extracted from `BookFileMaterializer.materializeOne`: takes `(localTempURL, manifestEntry) -> ImportResult` and runs SHA-256 verify + extension write + `BookImporter.importFile`. Both materializer and lazy coordinator call it. |
| `vreader/Services/Backup/BookFileMaterializer.swift` | 268 | **modified** — `materializeOne` becomes thin: download `Data` → write to temp → delegate to `BookFileImportFinalizer.finalize(localTempURL:entry:)`. Existing tests still pass; finalizer gets new tests. |
| `vreader/Services/Backup/RemoteBookCatalog.swift` (NEW) | ~80 | given a backup ID, decodes its `library-manifest.json` and returns `[BackupLibraryEntry]`. Uses `ZIPWriter.extractEntry(named:from:)` (the **correct** static API). |
| `vreader/Services/Backup/LazyDownloadDelegate.swift` (NEW) | ~120 | `final class LazyDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable` (nonisolated). Receives URLSession callbacks; holds `weak var coordinator: LazyDownloadCoordinator?`; forwards to MainActor. |
| `vreader/Services/Backup/LazyDownloadCoordinator.swift` (NEW) | ~220 | `@MainActor @Observable final class`. Owns the background `URLSession`, in-memory progress dictionary, enqueue/cancel API, and reattach-on-launch. Receives forwarded events from delegate. |
| `vreader/Services/Backup/LazyDownloadTaskMeta.swift` (NEW) | ~50 | `Codable Sendable` payload encoded in `URLSessionDownloadTask.taskDescription` so identity (`fingerprintKey`, `blobPath`, `expectedSHA256`, `expectedByteCount`, `originalExtension`) survives crash + relaunch. |
| `vreader/Services/Backup/BackgroundDownloadSessionFactory.swift` (NEW) | ~40 | protocol so tests can swap a deterministic mock for `URLSession.background(...)`. Production impl wraps `URLSession(configuration:delegate:delegateQueue:)`. |
| `vreader/Services/Backup/SelectiveRestoreCoordinator.swift` (NEW) | ~150 | given user's selection set, calls `BookFileMaterializer.materialize` on chosen subset and `insertRemoteOnlyBookRecords` for the rest. Then runs metadata restore via existing `BackupDataRestoring` path. |
| `vreader/Services/Backup/WebDAVNetworkPolicy.swift` (NEW) | ~80 | `NWPathMonitor`-backed `@MainActor @Observable` with `interface: .none / .cellular / .wifi`, `wifiOnly: Bool` UserDefault, `shouldStart() -> Bool`. |
| `vreader/Services/Backup/WebDAVProvider.swift` | 508 (>300 ⚠ pre-existing) | **modified** — adds `loadManifest(backupId:)` (returns `[BackupLibraryEntry]?`) and `restoreSelectively(backupId:selectedKeys:progress:)`. Net delta ≤ 80 LOC. |
| `vreader/Services/Backup/WebDAVProviderFactory.swift` | 101 | **unchanged** — factory does NOT receive `LazyDownloadCoordinator`. (Per finding #9.) |
| `vreader/App/VReaderApp.swift` | 200+ | **modified** — constructs the live `LazyDownloadCoordinator` (with `bookImporter`, `WebDAVNetworkPolicy`) and `WebDAVNetworkPolicy`, injects via `.environment(\.lazyDownloadCoordinator, ...)`. Adopts `UIApplicationDelegateAdaptor` for `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. ≤ 60 LOC delta. |
| `vreader/App/VReaderAppDelegate.swift` (NEW) | ~50 | `UIApplicationDelegate` adapter for `handleEventsForBackgroundURLSession` — stores completion handler keyed by session identifier; `LazyDownloadCoordinator` retrieves it on `urlSessionDidFinishEvents`. |
| `vreader/Utils/LazyDownloadCoordinatorEnvironment.swift` (NEW) | ~25 | mirrors `BookImporterEnvironment`. `EnvironmentKey` + `var lazyDownloadCoordinator: LazyDownloadCoordinator?`. |
| `vreader/Utils/WebDAVNetworkPolicyEnvironment.swift` (NEW) | ~25 | same pattern for the policy object. |
| `vreader/Views/Reader/ReaderNotifications.swift` | (read) | **modified** — add `bookFileStateDidChange` and `bookDownloadProgress`. |
| `vreader/Views/BookRowView.swift` | 121 | **modified** — branch on `book.fileState`. |
| `vreader/Views/Library/ShareSheet.swift` | 41 | **unchanged** internally — but the **call site** in the Library context menu gates on `book.fileState == .local`. |
| `vreader/Views/Library/LibraryView.swift` (or wherever the context menu lives) | (read) | **modified** — context menu's "Share" item is conditioned on `book.fileState == .local`; for non-local rows the item is absent (cleaner than disabled-with-grey-out for SwiftUI menus). |
| `vreader/ViewModels/LibraryViewModel.swift` | 254 | **modified** — observes `bookFileStateDidChange`; adds `requestDownload(fingerprintKey:)` / `cancelDownload(fingerprintKey:)`. |
| `vreader/Views/Reader/ReaderContainerView.swift` | 376 | **modified** — open-flow gate: if `!book.fileState.isReadable`, present `BookDownloadSheet`. |
| `vreader/Views/Library/BookDownloadSheet.swift` (NEW) | ~120 | progress sheet shown when opening a non-local book. |
| `vreader/Views/Settings/WebDAVSettingsView.swift` | 398 (>300 ⚠ pre-existing) | **modified** — adds "Restore selectively…", "Wi-Fi only" toggle. ≤ 70 LOC delta (GC entry deferred to #51). |
| `vreader/Views/Settings/SelectiveRestorePicker.swift` (NEW) | ~200 | sheet with `LazyVStack` over `[BackupLibraryEntry]`. |
| `vreader/ViewModels/SelectiveRestoreViewModel.swift` (NEW) | ~150 | owns the picker's mutable selection set, sort/filter, computed totals. |
| `vreader/ViewModels/BackupViewModel.swift` | 172 | **modified** — adds `loadRemoteCatalog(backupId:)`, `performSelectiveRestore(backupId:selectedKeys:)`. ≤ 60 LOC delta. |
| **Test files** | — | see "Test catalogue" below |

Files explicitly **OUT** of scope:

- `WebDAVBlobStore.swift` / `BackupBlobStore.swift` — protocol unchanged. (`BackupBlobReading.existsWithSize(at:)` is already adequate for the manifest emit policy.)
- `BackupSectionDTOs.swift` — `BackupLibraryEntry` already carries every field the picker and lazy coordinator need.
- `BookImporter.swift` — used as-is via `.restore` source.
- Reader format hosts (`EPUBReaderHost`, `TXTReaderHost`, etc.) — they only run after `fileState == .local`. Gate is in `ReaderContainerView`.
- Search indexer — already reader-driven, not import-driven.
- iCloud / S3 providers — protocol surface is unchanged.
- `RemoteBlobGarbageCollector` — moved to feature #51.

## Prior art / project precedent / rejected alternatives

**Precedent in the codebase:**

- The `@Observable` `@MainActor` ViewModel pattern is established (see `BackupViewModel`, `LibraryViewModel`).
- `NotificationCenter` is the cross-component bus (see `bookmarkAdded`, `readerDidClose`); using it for `bookFileStateDidChange` matches existing convention.
- `BookImporterEnvironment` (#46) demonstrates the `EnvironmentKey` pattern for thread-safe `@MainActor` service injection from `VReaderApp`. v2's `LazyDownloadCoordinatorEnvironment` mirrors it line-for-line.
- `BookFileMaterializer.classify(_:)` already separates "alreadyLocal" vs "needsDownload" via SHA-256 — phase 2 reuses it for both selective restore and lazy download paths.
- `BookFileImportFinalizer` extraction follows the same separation-of-concerns precedent that produced `BackupBlobReading` / `BackupBlobWriting` in #46.

**Industry precedent:**

- Apple Books / iCloud Drive: cloud icon + tap-to-download is the accepted iOS UX. Background `URLSession` with `isDiscretionary = true` is the documented Apple pattern for opportunistic transfers.
- Kindle's "Cloud" tab and Readwise's "All" view: selective fetch into local storage. Same model as ours.
- `NWPathMonitor` is the canonical reachability API since iOS 12 (no third-party SCNetworkReachability needed).
- The "nonisolated delegate adapter forwards to MainActor observable" pattern is the documented Swift 6 way to integrate URLSession (Apple's WWDC 2022 "Eliminate data races using Swift Concurrency" sample code uses it).

**Rejected alternatives:**

| Rejected | Why |
|----------|-----|
| Make `LazyDownloadCoordinator` itself conform to `URLSessionDownloadDelegate` directly | Compile-hostile under Swift 6: delegate methods are non-MainActor protocol requirements; you can't satisfy them on a `@MainActor`-isolated type without `nonisolated` per-method, which then forbids touching MainActor state inside them. The two-type split is cleaner. |
| Wire `LazyDownloadCoordinator` through `WebDAVProviderFactory.make(...)` | Factory builds the on-demand backup/restore provider; coordinator must outlive any single backup/restore. Lifecycles don't match; coupling is wrong. SwiftUI Environment is the right scope. |
| Single `BookFileMaterializer` that handles both in-memory and streaming downloads | Background `URLSessionDownloadTask` writes to a temp file; in-memory `BackupBlobReading.download(from: String) -> Data` returns a buffer. Forcing one shape on the other either spikes memory (load 500 MB blob into RAM) or breaks the existing restore path. Two callers, one finalizer is the right shape. |
| Store `BookFileState` as a Codable struct on `Book` | SwiftData `@Model` plays badly with custom Codables for filtering; storing the raw `String` and computing `BookFileState` is the pattern used by `Book.format` already. |
| Make `BookFileState` part of `BackupLibraryEntry` (in the manifest) | The manifest describes server-side identity; client-side state is per-device. Don't conflate. |
| Foreground `URLSession` for downloads | Loses opportunistic scheduling, drains battery, and Apple's TR for media-style transfers explicitly recommends `isDiscretionary = true`. |
| Auto-retry failed downloads | Introduces error-handling surface (exponential backoff, transient vs permanent classification) for marginal gain; user retry is a single tap. |
| One-state `isLocal: Bool` instead of a 5-state enum | Loses `.downloading`, `.failed`, `.missingRemote` distinctions that the UI must show. |
| Add `BookFileState` only to `LibraryBookItem` (not `Book`) | Tap on a `remoteOnly` row in cold-launch state needs the persisted truth, not a runtime cache that resets. Must persist. |
| "Share with auto-download" instead of "Share disabled when remote" | Adds reader-style download UX to a quick context-menu action; defer to future. |

## Key design decisions

### Where `BookFileState` lives

**Decision**: enum lives in `vreader/Models/BookFileState.swift`. Stored on `Book` as `var fileState: String` (raw value, defaulting to `"local"`). Surfaced on `LibraryBookItem` as a typed `BookFileState`. `BookRecord` carries it as the typed enum.

```swift
enum BookFileState: String, Sendable, Codable, CaseIterable, Equatable {
    case local         // bytes present at resolvedFileURL, fingerprint verified at import
    case remoteOnly    // row exists, blob is on the WebDAV server, no local bytes
    case downloading   // transfer in flight via LazyDownloadCoordinator
    case failed        // last download attempt failed; user can retry
    case missingRemote // row exists, but server reports 404 for blobPath
}
```

Storing as a raw `String` on the SwiftData model matches `Book.format`'s pattern and avoids SwiftData enum-encoding pitfalls. The typed enum gives compile-time safety everywhere else.

### Migration V5 → V6 (additive lightweight)

`Book.fileState` (String, default `"local"`) and `Book.blobPath` (optional String) are added. SwiftData lightweight migration handles additive changes with defaults / optional fields. `VReaderMigrationPlan.schemas` appends `SchemaV6.self`. `stages` stays empty.

**Verification path**: existing user's library on v3.11.x ships with `fileState == nil` rows; SchemaV6's default of `"local"` lights every existing book as `.local` post-upgrade. No reader/importer code path changes for the upgrade case.

### Manifest emit policy for non-local books (Round-1 finding #2)

**The rule a manifest entry must satisfy: it must point to a blob that genuinely exists at backup time.** Otherwise a peer device's restore breaks.

`BackupBookProjection` v2:

```swift
struct BackupBookProjection: Sendable, Equatable {
    let fingerprintKey: String
    let format: String
    let sha256: String
    let byteCount: Int64
    let originalExtension: String
    let title: String?
    let author: String?
    let addedAt: Date
    let lastOpenedAt: Date?
    let fileState: BookFileState   // NEW
    let blobPath: String?          // NEW (nil for legacy .local rows that never went through the picker)
}
```

`fetchAllBooksForBackup()` reads both new fields. `BackupDataCollector.collectLibraryManifest()` then applies:

| Row's `fileState` | Action | Notes |
|-------------------|--------|-------|
| `.local` | **Include in manifest; upload/verify blob.** | Existing phase-1 behavior. `blobPath` computed via `BlobPath.make(...)`. |
| `.remoteOnly` | **Include only if** `blobPath != nil` AND `await blobStore.existsWithSize(at: blobPath) != nil`. | Verifies the server still has the blob. If absent, the row is dropped from this manifest (other peer manifests may still reference it; that's not our concern). Server existence check uses `BackupBlobReading.existsWithSize(at:)`. |
| `.failed` | **Include only if** `blobPath != nil` AND `existsWithSize` returns non-nil. | Same as `.remoteOnly`. The failure was a download, not an upload — the blob may still be on the server. |
| `.missingRemote` | **Skip from manifest.** | We already know the server doesn't have the blob; emitting a manifest entry that points at a 404 corrupts other devices' restores. |
| `.downloading` | **Skip from manifest.** | No speculative refs. The book is mid-flight. Next backup catches it (it'll be either `.local` or `.failed` by then). |

**Rationale**: when a peer device runs "Restore all", every entry in the manifest is fetched. If even one entry 404s, the user sees a partial restore and an error toast. The policy above guarantees that every manifest entry's blob existed at the moment the backup ZIP was sealed.

**Cost**: one PROPFIND per non-`.local` row at backup time. For a library with 100 books of which 80 are `.remoteOnly`, that's 80 PROPFINDs. Acceptable; backup is a foreground operation already showing a progress bar.

### Share gating for non-local rows (Round-1 finding #3)

`ShareSheet.activityItems(for:)` returns `[book.resolvedFileURL]`. For a `.remoteOnly` row that URL points at a sandbox path with no file — sharing it hands `UIActivityViewController` a nonexistent URL and crashes / shows an empty share sheet.

**Decision (v2)**: the Library context menu's "Share" item is **conditioned on `book.fileState == .local`**. For non-local rows, the menu item is absent.

- **Rationale for "absent" over "disabled grey"**: SwiftUI's `.contextMenu { Button(...) }` doesn't have a clean `disabled-with-explanation` affordance. Hiding it is consistent with how iOS hides Quick Look for cloud-only files in Files.app.
- **Discoverability**: BookRowView's cloud icon already signals "this isn't local"; absence of Share follows naturally.
- **Future enhancement (NOT built in v2)**: a "Download then Share" path that taps the lazy coordinator and presents the Share sheet on `.local` transition. Documented for #145 follow-up.

The read-path enumeration that today assumes "Book row = file present" is now:

| Path | File | v2 gating |
|------|------|-----------|
| Reader open dispatch | `ReaderContainerView.swift` | `if !book.fileState.isReadable { BookDownloadSheet(...) }` |
| Library context menu — Share | `LibraryView.swift` (where the menu lives) | only show "Share" when `book.fileState == .local` |
| Library context menu — Open | (same) | always show; reader gate handles non-local case |
| Library context menu — Add to collection / Delete | (same) | always show; metadata-only ops |
| Search indexer trigger | `ReaderSearchCoordinator.indexBookContent` | unchanged; reader-driven, only fires on reader open which only opens for `.local` |
| Library list display | `BookRowView.swift` | branches per state (cloud icon, spinner, retry, etc.) |
| Delete | `PersistenceActor+Library.deleteBook` | unchanged. (Sandbox-file removal is a pre-existing latent issue; see Open Questions.) |
| Backup blob upload | `WebDAVProvider.uploadBlobs` | already skips books whose sandbox URL is missing. For `.remoteOnly` the blob is already on the server; the size-dedupe path makes re-upload a no-op. |
| Backup manifest emit | `BackupDataCollector.collectLibraryManifest` | new policy table above. |

### Lazy download orchestration: split delegate vs coordinator (Round-1 finding #4)

**Two types, one responsibility-split:**

```swift
// LazyDownloadDelegate.swift — nonisolated, receives URLSession callbacks
final class LazyDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var coordinator: LazyDownloadCoordinator?

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let meta = LazyDownloadTaskMeta(taskDescription: downloadTask.taskDescription) else { return }
        let snapshot = (
            fingerprintKey: meta.fingerprintKey,
            completed: totalBytesWritten,
            total: totalBytesExpectedToWrite
        )
        Task { @MainActor [weak coordinator] in
            coordinator?.didProgress(
                fingerprintKey: snapshot.fingerprintKey,
                completed: snapshot.completed,
                total: snapshot.total
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // CRITICAL: copy the temp file to a coordinator-owned URL synchronously
        // here. iOS deletes `location` as soon as this method returns.
        guard let meta = LazyDownloadTaskMeta(taskDescription: downloadTask.taskDescription) else { return }
        let stableURL = LazyDownloadDelegate.stableTempURL(for: meta)
        try? FileManager.default.removeItem(at: stableURL)
        try? FileManager.default.moveItem(at: location, to: stableURL)
        Task { @MainActor [weak coordinator] in
            await coordinator?.didFinishDownload(meta: meta, atStableURL: stableURL)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { ... }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak coordinator] in
            coordinator?.didFinishBackgroundEvents()
        }
    }
}

// LazyDownloadCoordinator.swift — @MainActor, observable, owns state
@MainActor
@Observable
final class LazyDownloadCoordinator {

    struct TaskProgress: Sendable, Equatable { /* ... */ }

    private(set) var inFlight: [String: TaskProgress] = [:]

    private let delegate: LazyDownloadDelegate
    private let session: URLSession
    private let finalizer: BookFileImportFinalizer
    private let persistence: PersistenceActor
    private let policy: WebDAVNetworkPolicy

    init(
        sessionFactory: any BackgroundDownloadSessionFactory,
        finalizer: BookFileImportFinalizer,
        persistence: PersistenceActor,
        policy: WebDAVNetworkPolicy
    ) {
        self.delegate = LazyDownloadDelegate()
        self.session = sessionFactory.makeSession(delegate: delegate)  // background config inside
        self.finalizer = finalizer
        self.persistence = persistence
        self.policy = policy
        self.delegate.coordinator = self
        Task { await reattachExistingTasks() }   // see lifecycle section
    }

    func enqueue(fingerprintKey: String, blobPath: String, expectedSHA256: String,
                 expectedByteCount: Int64, originalExtension: String) async { ... }
    func cancel(fingerprintKey: String) async { ... }

    // Called from delegate
    func didProgress(fingerprintKey: String, completed: Int64, total: Int64) { ... }
    func didFinishDownload(meta: LazyDownloadTaskMeta, atStableURL url: URL) async { ... }
    func didFailWithError(meta: LazyDownloadTaskMeta, error: Error) { ... }
    func didFinishBackgroundEvents() { ... }
}
```

**Why this matters**: SwiftUI views that observe the coordinator (via `@Environment` or `@Bindable`) must run on the MainActor. URLSession delegate methods are documented to run on a background queue (or `delegateQueue` if provided, but never `OperationQueue.main` for background sessions per Apple's TR). The `weak var coordinator` + `Task { @MainActor in ... }` forwarding is the only Swift-6-clean pattern.

The `LazyDownloadDelegate` is `@unchecked Sendable` because:
- Its only mutable property is `coordinator` (weak ref), set once during init.
- Delegate-callback locals are stack-confined.

### Background URLSession lifecycle persistence (Round-1 finding #5)

Background `URLSession` survives app termination. iOS launches the app to deliver completion events. v2 must spell out every stage of that lifecycle:

#### `taskDescription` mapping

`URLSessionDownloadTask.taskDescription` is a free-form string Apple persists across termination. We use it to carry identity:

```swift
struct LazyDownloadTaskMeta: Codable, Sendable, Equatable {
    let fingerprintKey: String
    let blobPath: String
    let expectedSHA256: String
    let expectedByteCount: Int64
    let originalExtension: String

    init?(taskDescription: String?) {
        guard let s = taskDescription, let data = s.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = decoded
    }

    func asTaskDescription() -> String {
        let data = try! JSONEncoder().encode(self)  // Codable on simple value types — won't throw
        return String(data: data, encoding: .utf8)!
    }
}
```

Set on `enqueue`: `task.taskDescription = meta.asTaskDescription()`. Read on every delegate callback to recover identity.

#### `URLSession.getAllTasks()` reattach on launch

`reattachExistingTasks()` runs at coordinator init:

```swift
private func reattachExistingTasks() async {
    let tasks = await session.allTasks
    for task in tasks {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let meta = LazyDownloadTaskMeta(taskDescription: task.taskDescription) else { continue }
        inFlight[meta.fingerprintKey] = TaskProgress(...)
        // Don't re-enqueue; the task is already running. Just observe.
    }
    await reconcileDownloadingRowsAgainst(tasks: tasks)
}
```

#### Crash recovery for `.downloading` rows

After reattach, walk persistence:

```swift
private func reconcileDownloadingRowsAgainst(tasks: [URLSessionTask]) async {
    let liveKeys = Set(tasks.compactMap { LazyDownloadTaskMeta(taskDescription: $0.taskDescription)?.fingerprintKey })
    let persistedDownloading = (try? await persistence.fingerprintKeys(withFileState: .downloading)) ?? []
    for key in persistedDownloading where !liveKeys.contains(key) {
        // App crashed between enqueue and `didCompleteWithError`. No live task. Mark failed.
        try? await persistence.setBookFileState(fingerprintKey: key, newState: .failed)
        NotificationCenter.default.post(name: .bookFileStateDidChange,
            object: nil, userInfo: ["fingerprintKey": key, "state": "failed"])
    }
}
```

#### `handleEventsForBackgroundURLSession` storage

When iOS launches the app to deliver background download events, it calls
`UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`. The completion handler **must be invoked** before iOS will release the app's background-launch grace period. SwiftUI's `App` lifecycle doesn't expose this hook directly, so v2 adopts `UIApplicationDelegateAdaptor`:

```swift
// VReaderAppDelegate.swift
final class VReaderAppDelegate: NSObject, UIApplicationDelegate {
    static var backgroundCompletionHandlers: [String: () -> Void] = [:]

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Self.backgroundCompletionHandlers[identifier] = completionHandler
    }
}

// VReaderApp.swift
@main
@MainActor
struct VReaderApp: App {
    @UIApplicationDelegateAdaptor(VReaderAppDelegate.self) private var appDelegate
    // ...
}

// LazyDownloadCoordinator.didFinishBackgroundEvents()
func didFinishBackgroundEvents() {
    let handler = VReaderAppDelegate.backgroundCompletionHandlers.removeValue(
        forKey: session.configuration.identifier ?? "")
    handler?()
}
```

**Critical**: the completion handler must NOT be invoked until `urlSessionDidFinishEvents(forBackgroundURLSession:)` fires. Calling it earlier loses pending events.

#### Test seam: `BackgroundDownloadSessionFactory`

`URLProtocol` mocks don't model `URLSession.background(...)` correctly — there's no realistic way to test reattach-on-launch with the standard mock. Solution:

```swift
protocol BackgroundDownloadSessionFactory: Sendable {
    func makeSession(delegate: URLSessionDownloadDelegate) -> URLSession
}

struct ProductionBackgroundDownloadSessionFactory: BackgroundDownloadSessionFactory {
    let identifier: String
    func makeSession(delegate: URLSessionDownloadDelegate) -> URLSession {
        let cfg = URLSessionConfiguration.background(withIdentifier: identifier)
        cfg.isDiscretionary = true
        cfg.sessionSendsLaunchEvents = true
        cfg.allowsCellularAccess = true  // gating happens in WebDAVNetworkPolicy
        return URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    }
}

// Test impl: synthesizes lifecycle deterministically without OS scheduling.
```

Tests use the mock to drive `enqueue → progress callbacks → finish → finalizer` synchronously. The reattach test injects a mock that returns a pre-staged `[URLSessionTask]`.

### `BookFileImportFinalizer` extraction (Round-1 finding #6)

`BookFileMaterializer.materializeOne` today does seven steps: preflight hash, download bytes, byte-count check, SHA-256 check, write temp file, import via `BookImporter`, fingerprint check.

For lazy download, steps 2 and 3 are different (streaming download writes a file, byte count comes from `URLResponse`). Steps 1 and 4-7 are **identical** and worth sharing.

**Extraction**:

```swift
// BookFileImportFinalizer.swift
struct BookFileImportFinalizer: Sendable {
    let importer: any BookImporting

    /// Verifies SHA-256, imports via BookImporter, verifies the resulting fingerprint.
    /// Caller must ensure `localTempURL` carries the bytes claimed by `entry`.
    /// `localTempURL` should already have the right `originalExtension`.
    func finalize(
        localTempURL: URL,
        entry: BackupLibraryEntry
    ) async -> MaterializeResult {
        // Step 4: SHA-256 verify on the file.
        guard let hash = try? localFileSHA256(at: localTempURL) else { ... }
        if hash != entry.sha256 {
            return .init(entry: entry, outcome: .sha256Mismatch(...))
        }
        // Step 6: import via BookImporter.
        do {
            let result = try await importer.importFile(at: localTempURL, source: .restore)
            // Step 7: verify fingerprint.
            guard result.fingerprintKey == entry.fingerprintKey else {
                return .init(entry: entry, outcome: .fingerprintMismatchAfterImport(...))
            }
            return .init(entry: entry, outcome: .downloaded(fingerprintKey: result.fingerprintKey))
        } catch let importErr as ImportError {
            return .init(entry: entry, outcome: .importFailed("\(importErr)"))
        } catch { ... }
    }

    private func localFileSHA256(at url: URL) throws -> String { /* moved from materializer */ }
}
```

**`BookFileMaterializer` after extraction**:

```swift
private func materializeOne(_ entry: BackupLibraryEntry) async -> MaterializeResult {
    // Steps 1-3 stay here (preflight + download bytes + byte-count check).
    // Step 5 (write to temp) stays here.
    // Step 4 + 6 + 7 delegate to finalizer.
    // ...
    let bytes = try await blobStore.download(from: entry.blobPath)
    if Int64(bytes.count) != entry.byteCount { return .sizeAfterDownloadMismatch(...) }
    try bytes.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }
    return await finalizer.finalize(localTempURL: tempURL, entry: entry)
}
```

**`LazyDownloadCoordinator.didFinishDownload`**:

```swift
func didFinishDownload(meta: LazyDownloadTaskMeta, atStableURL url: URL) async {
    let entry = meta.asBackupLibraryEntry()  // synthesize from meta fields
    let result = await finalizer.finalize(localTempURL: url, entry: entry)
    try? FileManager.default.removeItem(at: url)
    if result.isSuccess {
        try? await persistence.setBookFileState(fingerprintKey: meta.fingerprintKey, newState: .local)
        post(.bookFileStateDidChange, ["fingerprintKey": meta.fingerprintKey, "state": "local"])
    } else {
        try? await persistence.setBookFileState(fingerprintKey: meta.fingerprintKey, newState: .failed)
        post(.bookFileStateDidChange, ["fingerprintKey": meta.fingerprintKey, "state": "failed"])
    }
}
```

**Trade-off acknowledged**: same triple-verification logic, two callers, one finalizer (~120 LOC). Worth it because:
1. The verify-import logic is a security boundary (catches bad bytes); duplication invites drift.
2. `BookImporter.importFile(at:source:)` is async with side effects (cover extraction, indexing notification); calling it twice in two slightly-different ways is the highest-risk drift surface.
3. The finalizer's protocol signature `(URL, entry) -> MaterializeResult` is small and stable.

### Wi-Fi-only policy via `NWPathMonitor`

`WebDAVNetworkPolicy` owns a single `NWPathMonitor` and publishes `interface: .none / .cellular / .wifi`. The "Wi-Fi only" toggle is a `UserDefaults` boolean (`com.vreader.webdav.wifiOnly`, default `true`).

`shouldStart() -> Bool`:

- `wifiOnly == false` → `true`.
- `wifiOnly == true && currentInterface == .wifi` → `true`.
- `wifiOnly == true && currentInterface == .cellular` → `false`. Coordinator marks the task `.downloading` with a `waitingForWiFi: true` sub-state (visible in UI). Re-evaluates on path-change notification.

URLSession's `allowsCellularAccess = false` cancels rather than defers when the interface flips mid-flight; we set `allowsCellularAccess = true` and gate at `enqueue` instead.

### "Restore all" stays the phase-1 path

The existing `WebDAVProvider.restore(backupId:progress:)` is unchanged. The new "Restore selectively…" entry point routes to `restoreSelectively`, which differs in the materialize step.

Wi-Fi-only also gates "Restore all" — disabled with tooltip when on cellular.

### `\.lazyDownloadCoordinator` SwiftUI Environment (Round-1 finding #9)

`vreader/Utils/LazyDownloadCoordinatorEnvironment.swift`:

```swift
private struct LazyDownloadCoordinatorKey: EnvironmentKey {
    static let defaultValue: LazyDownloadCoordinator? = nil
}

extension EnvironmentValues {
    var lazyDownloadCoordinator: LazyDownloadCoordinator? {
        get { self[LazyDownloadCoordinatorKey.self] }
        set { self[LazyDownloadCoordinatorKey.self] = newValue }
    }
}
```

`VReaderApp` constructs the coordinator once in `init()` (alongside the existing `bookImporterRef`):

```swift
// in VReaderApp.init():
let policy = WebDAVNetworkPolicy()
let finalizer = BookFileImportFinalizer(importer: importer)
let factory = ProductionBackgroundDownloadSessionFactory(identifier: "com.vreader.app.book-downloads")
let coordinator = LazyDownloadCoordinator(
    sessionFactory: factory,
    finalizer: finalizer,
    persistence: persistenceActor,
    policy: policy
)
self.lazyDownloadCoordinatorRef = coordinator
self.networkPolicyRef = policy
```

```swift
// in body:
content
    .environment(\.persistenceActor, persistenceActor)
    .environment(\.bookImporter, bookImporterRef)
    .environment(\.lazyDownloadCoordinator, lazyDownloadCoordinatorRef)
    .environment(\.webDAVNetworkPolicy, networkPolicyRef)
```

Library + Reader views read `@Environment(\.lazyDownloadCoordinator)`. **Lifecycle**: coordinator is owned by `VReaderApp` for the lifetime of the process. The on-demand `WebDAVProvider` (built per backup/restore action via `WebDAVProviderFactory.make(...)`) does **not** receive or own the coordinator — those are independent concerns.

### Selective-restore preplant

When the user picks 3 of 100 books:

1. Materialize the 3 chosen entries (call existing `BookFileMaterializer.materialize`) → 3 `.local` rows with full metadata via `BookImporter`.
2. **Preplant** the other 97 as `.remoteOnly` rows — synthesize `BookRecord`s from manifest fields without touching `BookImporter`. The preplant path lives in `PersistenceActor+RemoteOnly.insertRemoteOnlyBookRecords(_:)` and:
   - Sets `provenance` to `.restore`.
   - Stores `coverImagePath = nil` (covers come back when the user downloads — the manifest doesn't carry covers).
   - Stores `detectedEncoding = nil` (TXT encoding is detected at download).
   - Sets `fileState = .remoteOnly` and `blobPath = entry.blobPath`.
3. Run existing per-section metadata restore (positions, annotations, etc.) — they re-attach to the now-present rows by `fingerprintKey`, **including for the 97 remote-only rows**. So a tap-to-download book opens at the saved position.

### Reader-entry-point gate UX

In `ReaderContainerView.body`:

```swift
if book.fileState.isReadable {
    // existing dispatch
} else if let coordinator = downloadCoordinator {
    BookDownloadSheet(book: book, coordinator: coordinator)
}
```

The sheet shows: title, author, format icon, byte size, `ProgressView(value:)` bound to coordinator's per-key progress, Cancel button, error state with Retry. On `bookFileStateDidChange` to `.local`, sheet auto-dismisses.

## File-by-file changes

### New: `vreader/Models/BookFileState.swift` (~50 lines)

```swift
enum BookFileState: String, Sendable, Codable, CaseIterable, Equatable {
    case local, remoteOnly, downloading, failed, missingRemote
    var isReadable: Bool { self == .local }
    var canDownload: Bool {
        switch self {
        case .remoteOnly, .failed: return true
        case .local, .downloading, .missingRemote: return false
        }
    }
}
```

### Modified: `vreader/Models/Book.swift`

- Add `var fileState: String = "local"`.
- Add `var blobPath: String?`.
- Update `init(...)` to accept both.

### New: `vreader/Models/Migration/SchemaV6.swift` (~30 lines)

Mirrors SchemaV5; lists the same models with `fileState` + `blobPath` added to `Book`.

### Modified: `vreader/Models/Migration/SchemaV1.swift`

Append `SchemaV6.self` to `VReaderMigrationPlan.schemas`.

### Modified: `vreader/Models/LibraryBookItem.swift`

Add `fileState: BookFileState` + `blobPath: String?`. `resolvedFileURL` returns the same URL regardless of state — but callers must check `fileState` first.

### Modified: `vreader/Services/PersistenceActor.swift`

`BookRecord` adds `fileState: BookFileState` (default `.local`) and `blobPath: String?` (default `nil`). `bookToRecord` reads from `Book`. `insertBook` writes both.

### New: `vreader/Services/PersistenceActor+RemoteOnly.swift` (~80 lines)

```swift
extension PersistenceActor {
    func insertRemoteOnlyBookRecords(_ records: [BookRecord]) async throws -> [String]
    func setBookFileState(fingerprintKey: String, newState: BookFileState) async throws
    func setBookBlobPath(fingerprintKey: String, blobPath: String?) async throws
    func fingerprintKeys(withFileState state: BookFileState) async throws -> [String]
}
```

`fingerprintKeys(withFileState:)` is used by the coordinator's reattach reconciliation.

### Modified: `vreader/Services/PersistenceActor+Library.swift`

`fetchAllLibraryBooks` populates `LibraryBookItem.fileState` + `blobPath`. `deleteBook` is **unchanged** (sandbox-file-removal is a pre-existing latent issue; see Open Questions).

### Modified: `vreader/Services/PersistenceActor+Backup.swift`

`BackupBookProjection` adds `fileState: BookFileState` + `blobPath: String?`. `fetchAllBooksForBackup()` reads them from `Book`.

### Modified: `vreader/Services/Backup/BackupDataCollector.swift`

`collectLibraryManifest` now (a) takes a `BackupBlobReading` parameter (already injected, just reused for the existence check), and (b) filters projections per the manifest emit policy table. Emits a per-skipped-row debug log.

### New: `vreader/Services/Backup/BookFileImportFinalizer.swift` (~120 lines)

See "BookFileImportFinalizer extraction" above. Owns: SHA-256 verify, BookImporter call, fingerprint-mismatch check.

### Modified: `vreader/Services/Backup/BookFileMaterializer.swift`

`materializeOne` becomes thin: download bytes, byte-count check, write to temp, delegate to `finalizer.finalize(localTempURL:entry:)`. Net delta: −60 LOC moved out, +5 LOC plumbing.

### New: `vreader/Services/Backup/RemoteBookCatalog.swift` (~80 lines)

```swift
struct RemoteBookCatalog: Sendable {
    let provider: WebDAVProvider
    func loadCatalog(backupId: UUID) async throws -> [BackupLibraryEntry]
}
```

Implementation:
1. Download backup ZIP via `WebDAVProvider`.
2. Extract: `let manifestData = try ZIPWriter.extractEntry(named: "library-manifest.json", from: zipData)` — **the correct static API per finding #8**.
3. Decode JSON.
4. Cache by `backupId` in-memory; cache cleared on `BackupViewModel.loadBackups()` refresh.

### New: `vreader/Services/Backup/LazyDownloadTaskMeta.swift` (~50 lines)

See above. Codable Sendable struct serializing identity into `taskDescription`.

### New: `vreader/Services/Backup/BackgroundDownloadSessionFactory.swift` (~40 lines)

Protocol + production impl. See above.

### New: `vreader/Services/Backup/LazyDownloadDelegate.swift` (~120 lines)

Nonisolated `URLSessionDownloadDelegate` adapter. See "Lazy download orchestration" above.

### New: `vreader/Services/Backup/LazyDownloadCoordinator.swift` (~220 lines)

`@MainActor @Observable`. See "Lazy download orchestration" above.

### New: `vreader/Services/Backup/SelectiveRestoreCoordinator.swift` (~150 lines)

```swift
struct SelectiveRestoreCoordinator: Sendable {
    let provider: WebDAVProvider
    let materializer: BookFileMaterializer
    let persistence: PersistenceActor
    let dataRestorer: BackupDataRestoring

    func restoreSelectively(
        backupId: UUID,
        manifest: [BackupLibraryEntry],
        selectedKeys: Set<String>,
        progress: @Sendable (Double) -> Void
    ) async throws
}
```

Phases: preplant remote-only rows (0 → 0.10) → materialize selected (0.10 → 0.85) → metadata restore (0.85 → 1.0).

### New: `vreader/Services/Backup/WebDAVNetworkPolicy.swift` (~80 lines)

`@MainActor @Observable` with `NWPathMonitor`. UserDefault key `com.vreader.webdav.wifiOnly` (default `true`).

### Modified: `vreader/Services/Backup/WebDAVProvider.swift`

Net adds:
- `func loadManifest(backupId: UUID) async throws -> [BackupLibraryEntry]?`
- `func restoreSelectively(backupId: UUID, selectedKeys: Set<String>, progress: ...) async throws`

If the file grows past 600 LOC, extract `WebDAVProvider+Restore.swift`.

### Unchanged: `vreader/Services/Backup/WebDAVProviderFactory.swift`

Per finding #9 — factory does NOT receive `LazyDownloadCoordinator`.

### Modified: `vreader/App/VReaderApp.swift`

Construct `WebDAVNetworkPolicy`, `BookFileImportFinalizer`, `LazyDownloadCoordinator` in `init()`. Inject via Environment. Adopt `UIApplicationDelegateAdaptor`.

### New: `vreader/App/VReaderAppDelegate.swift` (~50 lines)

`UIApplicationDelegate` adapter for `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. Stores handler in static dictionary keyed by session identifier.

### New: `vreader/Utils/LazyDownloadCoordinatorEnvironment.swift` (~25 lines)

`EnvironmentKey` mirroring `BookImporterEnvironment`.

### New: `vreader/Utils/WebDAVNetworkPolicyEnvironment.swift` (~25 lines)

Same.

### Modified: `vreader/Views/Reader/ReaderNotifications.swift`

```swift
extension Notification.Name {
    static let bookFileStateDidChange = Notification.Name("vreader.book.fileState.didChange")
    static let bookDownloadProgress = Notification.Name("vreader.book.download.progress")
}
```

### Modified: `vreader/Views/BookRowView.swift`

Branch on `book.fileState`. Cloud icon for `.remoteOnly`, spinner for `.downloading`, retry hint for `.failed`, "removed from server" hint for `.missingRemote`.

### Modified: `vreader/Views/Library/LibraryView.swift` (or context-menu host)

Conditional Share menu item: only present when `book.fileState == .local`.

### Modified: `vreader/Views/Reader/ReaderContainerView.swift`

```swift
if book.fileState.isReadable {
    Group { /* existing dispatch */ }
} else {
    BookDownloadSheet(book: book, coordinator: downloadCoordinator)
}
```

### New: `vreader/Views/Library/BookDownloadSheet.swift` (~120 lines)

Full-screen sheet bound to coordinator state. Auto-dismisses on `.local`.

### Modified: `vreader/ViewModels/LibraryViewModel.swift`

Adds `requestDownload(fingerprintKey:)`, `cancelDownload(fingerprintKey:)`, observes `bookFileStateDidChange`.

### New: `vreader/ViewModels/SelectiveRestoreViewModel.swift` (~150 lines)

Owns picker state.

```swift
@MainActor @Observable
final class SelectiveRestoreViewModel {
    let backupId: UUID
    private(set) var entries: [BackupLibraryEntry] = []
    var searchText: String = ""
    var sort: SortKey = .title
    var selection: Set<String> = []  // fingerprintKeys
    enum SortKey: String, CaseIterable { case title, size, date }
    var filtered: [BackupLibraryEntry] { ... }
    var totalSelectedBytes: Int64 { ... }
    func loadCatalog() async
    func toggleSelection(_ key: String); func selectAll(); func deselectAll()
}
```

### New: `vreader/Views/Settings/SelectiveRestorePicker.swift` (~200 lines)

`LazyVStack` over `viewModel.filtered`. Each row: format icon, title, author, byte size, last-opened date, checkbox. Footer: "Restore N (X MB)" CTA.

### Modified: `vreader/Views/Settings/WebDAVSettingsView.swift`

- Add Wi-Fi-only toggle row.
- Add "Restore selectively…" button per backup row.
- (GC entry deferred to feature #51.)
- If file > 500 LOC after edits, extract `WebDAVMaintenanceSection.swift`.

### Modified: `vreader/ViewModels/BackupViewModel.swift`

```swift
func loadRemoteCatalog(backupId: UUID) async -> [BackupLibraryEntry]
func performSelectiveRestore(backupId: UUID, selectedKeys: Set<String>) async
```

(GC view-model entries deferred to feature #51.)

## Test catalogue

| Test file | Coverage |
|-----------|----------|
| `BookFileStateTests.swift` (NEW) | enum raw round-trip, `isReadable` / `canDownload` truth tables, `allCases` stability. |
| `BookFileStateMigrationTests.swift` (NEW) | V5 → V6 migration: existing rows default `fileState == "local"`, `blobPath == nil`. In-memory `ModelContainer` configured with both schemas. |
| `LibraryBookItemTests.swift` (extended) | `fileState`/`blobPath` expose correctly; `resolvedFileURL` independent of state. |
| `BackupBookProjectionTests.swift` (extended) | `fetchAllBooksForBackup()` reads `fileState` + `blobPath`; legacy V5 rows coalesce to `.local`/nil. |
| `BackupDataCollectorManifestEmitTests.swift` (NEW) | manifest emit policy: `.local` always emitted; `.remoteOnly` with present blob emitted; `.remoteOnly` with missing blob skipped; `.failed` with missing blob skipped; `.missingRemote` always skipped; `.downloading` always skipped. Mock `BackupBlobReading.existsWithSize` to control "present" vs "missing". |
| `PersistenceActorRemoteOnlyTests.swift` (NEW) | `insertRemoteOnlyBookRecords` idempotency, `setBookFileState` valid + invalid transitions, `setBookBlobPath` round-trip, `fingerprintKeys(withFileState:)` filtering. |
| `BookFileImportFinalizerTests.swift` (NEW) | SHA-256 mismatch returns `.sha256Mismatch`; happy path returns `.downloaded`; importer error wraps as `.importFailed`; fingerprint mismatch returns `.fingerprintMismatchAfterImport`. |
| `BookFileMaterializerTests.swift` (extended) | regression: post-extraction materializer still passes existing tests (now exercised through finalizer). |
| `RemoteBookCatalogTests.swift` (NEW) | given a fixture ZIP, returns expected `[BackupLibraryEntry]` via `ZIPWriter.extractEntry(named:from:)`; v1-format ZIP returns nil. |
| `WebDAVNetworkPolicyTests.swift` (NEW) | `shouldStart()` truth table for all (toggle × interface) combinations; UserDefault round-trip. |
| `LazyDownloadTaskMetaTests.swift` (NEW) | `taskDescription` round-trip; nil-input produces nil; bad-JSON produces nil. |
| `LazyDownloadDelegateTests.swift` (NEW) | progress event forwarding hits MainActor with right snapshot; finish event copies the temp file before iOS could evict; error event propagates. Use a `MockCoordinator` that records calls. |
| `LazyDownloadCoordinatorTests.swift` (NEW) | enqueue happy-path; cancel mid-flight reverts to `.remoteOnly`; SHA-256 mismatch path triggers `.failed`; retry after `.failed` works; reattach-on-init pulls running tasks via mock factory; `.downloading` row with no live task at launch flips to `.failed`; `didFinishBackgroundEvents` invokes the stored completion handler exactly once. Uses `BackgroundDownloadSessionFactory` mock. |
| `SelectiveRestoreCoordinatorTests.swift` (NEW) | given manifest of 5 + selection of 2, persists 2 `.local` + 3 `.remoteOnly`; metadata restore re-attaches positions to all 5 rows. |
| `SelectiveRestoreViewModelTests.swift` (NEW) | filter by title, sort by size, selectAll/deselectAll, totalSelectedBytes math, empty-catalog edge case. |
| `BackupViewModelTests.swift` (extended) | `performSelectiveRestore` happy path, error surfacing. |
| `LibraryShareGatingTests.swift` (NEW) | the Library context menu omits "Share" when `fileState != .local`; includes it when `.local`. (Snapshot or behavioral assertion on the menu builder.) |
| `LazyDownloadIntegrationTests.swift` (NEW; Docker WebDAV) | restore selectively (1 of 3) → 1 local + 2 remoteOnly → tap remote → download → verify SHA + open at saved position. |
| `WebDAVBackupIntegrationTests.swift` (extended) | regression: existing "Restore all" path still works against feature-#47-shaped backups. |

**Edge cases explicitly covered**:

- Empty manifest (selective picker shows empty state, not crash).
- 10k-entry manifest (`LazyVStack` virtualizes; sort doesn't choke).
- Tap `.remoteOnly` row offline (`.notConnectedToInternet`) → row stays `.remoteOnly`, error toast (does NOT flip to `.failed`).
- Tap `.remoteOnly` row when blob 404s → `.missingRemote`.
- Mid-download cancel → row reverts to `.remoteOnly`, no half-imported state.
- Storage pressure during download.
- Wi-Fi-only toggle flipped mid-flight → in-flight task continues; next enqueue reads fresh policy.
- App relaunch with pending background downloads → coordinator reattaches via `getAllTasks()`.
- App **crash** mid-download (vs clean termination) → `.downloading` row with no live task at launch → flips to `.failed`.
- `handleEventsForBackgroundURLSession` called twice (rare iOS race) → second handler replaces first; first is leaked but iOS tolerates.
- Sharing a `.remoteOnly` book → Share is absent from context menu (test covers this).
- Backing up a library that contains a `.remoteOnly` book whose blob was GC'd by another device → `existsWithSize` returns nil → row skipped from manifest with debug log.
- `taskDescription` containing user-input strings → JSON-encoded so commas/quotes don't break parsing.
- Unicode/CJK title in selective picker search → NFC-normalize.
- RTL title rendering → relies on existing SwiftUI text mirror.

## Sequencing

Each WI: RED test first, then GREEN, REFACTOR. Each WI ships its own PR with version bump.

| WI | Tier | What | Files | Estimated PR |
|----|------|------|-------|--------------|
| 1 | foundational | `BookFileState` enum + `Book.fileState` + `Book.blobPath` + SchemaV6 + migration plan append. Tests cover migration. | 5 prod, 2 test | small |
| 2 | foundational | `BookRecord` + `LibraryBookItem` carry `fileState`/`blobPath`. `PersistenceActor+RemoteOnly` (insertRemoteOnly, setFileState, setBlobPath, fingerprintKeys-by-state). `BackupBookProjection` extension + manifest emit policy in `BackupDataCollector`. Tests. | 5 prod, 3 test | medium |
| 3a | behavioral | `LazyDownloadDelegate` + `LazyDownloadCoordinator` skeleton. `LazyDownloadTaskMeta`. `BackgroundDownloadSessionFactory`. Happy-path enqueue/cancel. NO lifecycle persistence yet, NO Wi-Fi gating yet. Tests use the factory mock. | 4 prod, 3 test | medium |
| 3b | behavioral | Lifecycle persistence: `taskDescription` mapping wired in, `URLSession.getAllTasks()` reattach, crash recovery for `.downloading` rows, `VReaderAppDelegate` + `UIApplicationDelegateAdaptor`, `handleEventsForBackgroundURLSession` storage and invocation. Tests with deterministic factory mock. | 2 prod, 1 test | small-medium |
| 3c | behavioral | `WebDAVNetworkPolicy` + Wi-Fi-only toggle wiring + `webDAVNetworkPolicy` Environment key. Coordinator gates `enqueue` on `policy.shouldStart()`. UserDefault round-trip. | 2 prod, 1 test | small |
| 4a | behavioral | `BookFileImportFinalizer` extraction from `BookFileMaterializer`. Existing materializer tests must still pass; new finalizer tests. `RemoteBookCatalog` (using correct `ZIPWriter.extractEntry(named:from:)` API). | 3 prod (mod+new), 2 test | small-medium |
| 4b | behavioral | `SelectiveRestoreCoordinator` + `WebDAVProvider.loadManifest` + `restoreSelectively`. Coordinator wires materializer + finalizer + `insertRemoteOnlyBookRecords` + metadata restore. **Slice verify**: pick 2 of 5 → assert 2 local + 3 remoteOnly + positions restored. | 2 prod, 2 test | medium |
| 5 | behavioral | `BookRowView` branching; `LibraryViewModel` observes notifications; **Library context-menu Share gating** (omit when not `.local`); `ReaderContainerView` gate; `BookDownloadSheet`; `\.lazyDownloadCoordinator` Environment in `VReaderApp`. **Slice verify**: tap a remote-only row, watch the sheet, watch the row flip. | 6 prod, 2 test | medium |
| 6 | behavioral | `SelectiveRestoreViewModel` + `SelectiveRestorePicker` + `WebDAVSettingsView` integration (picker entry + Wi-Fi toggle row). **Slice verify**: open picker on a 5-book backup → check 2 → restore. | 4 prod, 1 test | medium |
| 7 | final | Docker integration tests (lazy download, share-gating, app-relaunch resume); `docs/architecture.md` Backup section update; manual-test-checklist recipe; row #47 → DONE. **Full acceptance pass**. | 1 mod, 2 test | small |

**WI count: 9** (was 8 in v1; GC carve-out → 7, then WI-3 → 3a/3b/3c and WI-4 → 4a/4b → 9).

**Critical path**:
- WI-1 → WI-2 (foundational, must land first).
- WI-3a → WI-3b → WI-3c (lifecycle stack, depends on WI-2).
- WI-4a → WI-4b (selective-restore stack, depends on WI-2; WI-4a in particular depends on WI-2's `BookFileImportFinalizer` callsite).
- WI-3 stack and WI-4 stack can ship in parallel after WI-2.
- WI-5, WI-6 (UI) depend on the full WI-3 + WI-4 surface.
- WI-7 is the final acceptance + docs WI.

WI-3 and WI-4 stacks can ship in either order or in parallel — surfaces don't overlap (WI-3 is download infra, WI-4 is restore-selectively wiring).

## Risks + mitigations

| Risk | Mitigation |
|------|-----------|
| `URLSession.background` + `isDiscretionary` is reportedly slow when iOS deprioritizes the session | Document in user-facing copy; offer "Download now (use cellular)" override that flips `wifiOnly` transiently for a single transfer. |
| `URLSessionDownloadDelegate` callbacks running on a background queue race with MainActor state | Resolved by the `LazyDownloadDelegate` / `LazyDownloadCoordinator` split (finding #4). All MainActor mutations go through the `Task { @MainActor in ... }` forwarding. |
| `BookFileState` migration on a large library could block app launch | Migration is column-add with a default + optional; SwiftData handles in O(rows). Worst-case 10k rows ≈ tens of ms. Tested in WI-1. |
| Selective picker on 10k-book backup loads slowly | Manifest is small (~150 bytes/entry → 1.5 MB for 10k books). Cached in `RemoteBookCatalog`. `LazyVStack` virtualizes display. |
| `handleEventsForBackgroundURLSession` not called → app gets killed without delivering events | Confirmed pattern; `UIApplicationDelegateAdaptor` is the SwiftUI-blessed way to receive it. WI-3b adds a focused test. |
| Background download completion when app is suspended | `sessionSendsLaunchEvents = true`; iOS launches the app to deliver. `VReaderAppDelegate.backgroundCompletionHandlers` retains the handler until `urlSessionDidFinishEvents`. |
| `NWPathMonitor` reports `.cellular` for tethering; user expects that to count as Wi-Fi | Document: Wi-Fi-only follows iOS's interface classification. |
| Cover images are absent for `.remoteOnly` rows | `BackupLibraryEntry` already carries title + author. Cover comes back when the book downloads. Acceptable phase-2 limitation. |
| `URLSessionDownloadTask` writes to a temp file iOS may evict before we copy it out | `LazyDownloadDelegate.urlSession(_:downloadTask:didFinishDownloadingTo:)` synchronously moves the file to a coordinator-owned stable URL **before** dispatching to MainActor. The MainActor leg then runs `finalizer.finalize(localTempURL: stableURL, ...)`. |
| User triggers "Restore all" mid-selective restore | `BackupViewModel.isRestoring` already gates concurrent restores; selective restore reuses the flag. |
| Reader open path's `BookDownloadSheet` race: download completes after user dismisses | Sheet observes `bookFileStateDidChange`; on `.local` → auto-dismiss → caller pushes reader. If user already left, transition just refreshes the row. No reader force-pushed. |
| Sharing a `.remoteOnly` book hands `UIActivityViewController` a nonexistent URL | Resolved by Library context-menu gating (finding #3). Test covers presence/absence of the menu item. |
| Backup of a library with `.remoteOnly` books emits manifest entries pointing at deleted blobs | Resolved by manifest emit policy (finding #2). Test covers each filter branch. |
| `BookFileImportFinalizer` extraction breaks existing `BookFileMaterializer` tests | WI-4a runs the existing materializer test suite end-to-end after extraction; any failure is a regression and blocks WI-4a. |

## Backward compat

1. **Existing v3.11.x library upgrades to v3.12.0**: every existing row gets `fileState = .local` via SchemaV6 default. No reader/importer/index path changes.
2. **v3.11.x backup restored on v3.12.0 device via "Restore all"**: identical to phase-1 behavior. All books materialize as `.local`. `library-manifest.json` shape is the same (DTOs unchanged on the wire).
3. **v3.12.0 device with `.remoteOnly` rows backs up to a v3.11.x peer**: per the new emit policy, only `.remoteOnly` rows whose blobs are server-present emit a manifest entry. Phase-1 restore tries to fetch the blob; if still on the server, success. Older clients never see invalid manifest entries.

## Open questions (for Gate-3 audit)

1. **Should `.local` book deletion remove the sandbox file as part of #47?** Today, `PersistenceActor+Library.deleteBook` does not remove the sandbox book file. This is a pre-existing latent issue. Phase 2 doesn't make it worse, but does make the implications more visible (users will toggle local/remote more often). **Proposal**: file as a separate bug, not bundled into #47.

2. **`RemoteBookCatalog` cache invalidation — when does it clear?** Today's plan: clear on `BackupViewModel.loadBackups()` refresh. Open: also clear on `restoreSelectively` completion (entries become preplanted, so re-fetch is wasted)? Audit input requested.

3. **`BookFileImportFinalizer` ownership**: should it be a `struct` (current plan) or an actor? The verify+import path is async but stateless. Struct is simpler; audit can push back.

4. **Indexing notification**: `BookImporter.indexingNeededNotification` is posted when the materializer imports a freshly-downloaded book. As of phase 1 there's no production observer. Phase 2 doesn't change this. If a future audit determines restored books need explicit indexing, that's a separate feature.

5. **Should the selective picker support a "preview cover" by downloading a few KB?** Manifest entries don't carry cover data; EPUB cover extraction requires the full file. Decision: skip for #47.

## Acceptance gate

- Plan exists at `dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md` ✅
- Gate 2 (Codex Round-1 audit) — **complete**, SPLIT verdict; resolutions encoded in v2.
- Gate 3 (Codex Round-2 audit on v2) — **pending**.
- Codex Round-2 must verify:
  - The manifest emit policy table covers every state transition without gaps.
  - The `LazyDownloadDelegate` / `LazyDownloadCoordinator` split compiles cleanly under Swift 6.
  - The `taskDescription` JSON encoding round-trips across crash/relaunch.
  - `BookFileImportFinalizer` extraction preserves existing materializer test outcomes.
  - The Library context-menu Share gating mechanism works (menu builder vs `.disabled` modifier).
  - The 9-WI sequencing is implementable in the listed order without circular deps.
- Implementation begins at WI-1 only after Gate-3 audit findings are resolved (or accepted with rationale).
