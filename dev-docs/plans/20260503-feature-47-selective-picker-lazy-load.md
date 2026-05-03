# Feature #47 — Implementation Plan

**Source**: `docs/features.md` row #47 (PLANNED, Medium priority) — "WebDAV restore — selective book picker + lazy-on-tap downloads"
**GH issue**: #145
**Phase**: 2 of 2 (phase 1 = feature #46, VERIFIED in v3.11.1)
**Depends on**: feature #46 — VERIFIED in v3.11.1. The blob layout
(`VReader/books/<format>/<sha256>_<byteCount>.<ext>`), `BackupLibraryEntry`
manifest schema, `BookFileMaterializer`, and `WebDAVBlobStore` already exist
and are reused as-is.
**Status**: DRAFT v1 — Codex Round-1 audit returned SPLIT verdict; plan v2 in progress (GC scope carved out to #51; remaining findings to address before Gate 3).

## Revision history

- **DRAFT (v1)** — initial plan; sent to Codex for Gate-2 audit.
- **v1 audit (Codex 2026-05-03)** — verdict: **SPLIT**. 11 findings. Primary structural change: GC operation moved out to feature #51. Other findings drive the v2 plan revision.

## Audit fixes applied — Round 1 (Codex 2026-05-03)

| # | Finding | Severity | Resolution |
|---|---------|----------|-----------|
| 1 | GC race-condition: 60-second grace insufficient; another device backing up DURING our GC run could publish a blob we're about to delete. | High | **Carved out — GC is now feature #51.** v2 plan removes WI-7 (RemoteBlobGarbageCollector + GC dialog) entirely. |
| 2 | Backup collector wrong/incomplete for non-local books: `fetchAllBooksForBackup()` emits every Book row with no file-state signal; `WebDAVProvider.uploadBlobs` skips missing sandbox files but the manifest still references them. | High | **v2 must add file-state policy to `BackupBookProjection` + manifest emit.** Per Codex: `local` → include + upload/verify; `remoteOnly`/`failed` → include only if `blobPath` exists and server `existsWithSize` confirms; `missingRemote` → skip; `downloading` → either skip or fail backup (no speculative refs). |
| 3 | Missed read path: `ShareSheet.activityItems(for:)` blindly returns `book.resolvedFileURL` — sharing a `remoteOnly` book hands out a nonexistent file URL. | High | **v2 adds Share gating** to the cross-cutting state-transitions list. Library context menu disables "Share" on non-local rows OR routes share through download-then-share. |
| 4 | Lazy download session design compile-hostile: `LazyDownloadCoordinator: @MainActor ... URLSessionDownloadDelegate` won't work — delegate callbacks are non-main protocol requirements. | High | **v2 splits responsibility**: nonisolated delegate adapter (`final class LazyDownloadDelegate: NSObject, URLSessionDownloadDelegate`) forwards to `@MainActor LazyDownloadCoordinator` observable. |
| 5 | Background URLSession lifecycle under-specified: needs `taskDescription` mapping `taskIdentifier → fingerprintKey/blobPath/sha/bytes`, `getAllTasks()` reattach on launch, completion-handler storage, crash recovery for `.downloading` rows, test seam. | High | **v2 expands WI-3 into discrete sub-WIs**: session + lifecycle persistence, reattach-on-launch, crash recovery, test seam (mock replacement for background-only behaviors that URLProtocol can't cover). |
| 6 | Coordinator can't reuse `BookFileMaterializer.download` directly: WebDAV downloads need base URL + Basic auth from `WebDAVClient`; materializer only downloads `Data` via `BackupBlobReading`. | Medium | **v2 extracts shared verify+import helpers** from `BookFileMaterializer`; `LazyDownloadCoordinator` uses a request-building WebDAV download adapter (NOT the existing `BackupBlobReading.download(from:)`). |
| 7 | WI-3 + WI-4 too crammed; WI-3 hides session lifecycle + network policy + notifications + reattach + cancellation + retry + tests; WI-4 hides catalog + selective restore + manifest extraction + metadata ordering + provider API. | Medium | **v2 de-crams**: WI-3 → 3 sub-WIs (session+lifecycle, network policy, retry/cancel); WI-4 → 2 sub-WIs (catalog + selective-restore coordinator). |
| 8 | `RemoteBookCatalog` references `ZIPWriter.extractEntry` with wrong API — actual is static `ZIPWriter.extractEntry(named:from:)`. | Low | **v2 uses the correct API** in the file-by-file changes. |
| 9 | `WebDAVProviderFactory` cannot just "wire coordinator into provider"; reader/library UI need an environment/service owner. | Medium | **v2 adds `\.lazyDownloadCoordinator` SwiftUI Environment** key (mirrors `\.bookImporter` pattern from #46/WI-8b); `VReaderApp` injects; Library/Reader read it from environment. |
| 10 | Materializer `classify` using `originalExtension` imperfect for MOBI/PRC duplicates — canonical extension wins for same-content imports. | Low | **No change** — same trade-off as feature #46. `originalExtension` is best-effort metadata; canonical extension drives sandbox path uniqueness. |
| 11 | `BackupBookProjection.originalExtension` non-optional vs `Book.originalExtension` optional: projection coalesces. | Low | **No change** — intentional, audited in feature #46. |

## Open questions answered (Codex Round 1)

- **Q1** (`remoteByteCount` vs reuse `fileByteCount`): Use existing `fileByteCount`. Manifest byte count equals fingerprint byte count.
- **Q3** (URLSession delegate isolation): Nonisolated delegate adapter; persist task metadata for relaunch.
- **Q4** (GC transport-neutrality): Keep WebDAV-specific. **Carved out to #51.**
- **Q8** (Wi-Fi gating scope): Gate backup, restore-all, selective materialization, lazy downloads. Do NOT gate connection test or backup-list refresh.

## Goal

Phase 1 (feature #46) gives a fresh device its full library back by downloading every book up front. That is correct but expensive: large libraries take a long time, secondary devices waste storage, and offline users can't choose to defer. Phase 2 introduces **the file-state distinction**: a book row may exist locally without its bytes, and may flip between `local` ↔ `remoteOnly` via user action.

Concrete success criteria:

1. After a "Restore selectively…" pass, the user has exactly the rows they checked as `local` and the rest as `remoteOnly` (visible with a cloud-download icon and size).
2. Tapping a `remoteOnly` row triggers a download (`URLSessionConfiguration.isDiscretionary`-backed); on success the row flips to `local` and the reader opens at the saved position.
3. A "Wi-Fi only" toggle (default ON) defers cellular downloads until Wi-Fi is available, with a visible "waiting for Wi-Fi" indicator.
4. A "Clean unused remote files" maintenance action lists every backup manifest on the server, computes the union of referenced blob paths, and deletes unreferenced blobs after explicit user confirmation showing affected count + freed bytes.
5. Existing fully-local libraries (people who never touch selective restore) see no behavior change — every existing reader/importer/indexer/delete path keeps working.

## Surface area

Files in scope (current line counts; touch type):

| File | Lines | Touch |
|------|-------|-------|
| `vreader/Models/Book.swift` | 148 | **modified** — add `var fileState: String` (default `"local"`) backed by `BookFileState` enum. New SchemaV6 introduces this column. |
| `vreader/Models/BookFileState.swift` (NEW) | ~50 | enum + helpers (`raw`, transitions, `isReadable`). Sendable + Codable. |
| `vreader/Models/Migration/SchemaV6.swift` (NEW) | ~30 | additive lightweight migration; existing rows default `fileState = "local"`. |
| `vreader/Models/Migration/SchemaV1.swift` | 86 | **modified** — append `SchemaV6.self` to `VReaderMigrationPlan.schemas`. |
| `vreader/Models/LibraryBookItem.swift` | 77 | **modified** — add `fileState: BookFileState` and `remoteByteCount: Int64?` (size-from-manifest for `remoteOnly` rows). |
| `vreader/Services/PersistenceActor.swift` | 182 | **modified** — `BookRecord` adds `fileState: BookFileState`. `bookToRecord` populates it. `insertBook` accepts it (default `.local`). |
| `vreader/Services/PersistenceActor+Library.swift` | 94 | **modified** — `fetchAllLibraryBooks` exposes `fileState`. New `setBookFileState(fingerprintKey:newState:)` and `deleteBook` updated to skip sandbox file removal when `fileState == .remoteOnly`. |
| `vreader/Services/PersistenceActor+RemoteOnly.swift` (NEW) | ~80 | feature-local extension: `insertRemoteOnlyBookRecords(_:)` (used by selective restore to preplant rows from manifest entries without their bytes). |
| `vreader/Services/Backup/RemoteBookCatalog.swift` (NEW) | ~80 | given a backup ID, decodes its `library-manifest.json` and returns `[BackupLibraryEntry]`. Pure function over `WebDAVBlobReading` + `WebDAVTransport.download`. |
| `vreader/Services/Backup/LazyDownloadCoordinator.swift` (NEW) | ~220 | `@MainActor` actor-or-Observable that owns the `URLSessionConfiguration.isDiscretionary` background session, tracks per-book progress, applies a 2-task concurrency cap, gates on Wi-Fi toggle + reachability, posts `bookFileStateDidChange` on state transitions. |
| `vreader/Services/Backup/RemoteBlobGarbageCollector.swift` (NEW) | ~120 | walks every `*.vreader.zip`, extracts `library-manifest.json` from each, computes referenced-blob union, lists `VReader/books/**`, returns deletion candidates with size + count. Apply step is separate (caller confirms first). |
| `vreader/Services/Backup/WebDAVNetworkPolicy.swift` (NEW) | ~80 | `NWPathMonitor`-backed `@MainActor` `@Observable` that publishes `interface: .none / .cellular / .wifi`, plus `wifiOnlyEnabled` UserDefault and `shouldStart() -> Bool`. |
| `vreader/Services/Backup/SelectiveRestoreCoordinator.swift` (NEW) | ~150 | given user's selection set, calls `BookFileMaterializer.materialize` on chosen subset and `insertRemoteOnlyBookRecords` for the rest. Then runs metadata restore via existing `BackupDataRestoring` path. |
| `vreader/Services/Backup/WebDAVProvider.swift` | 508 (>300 ⚠ pre-existing) | **modified** — adds `loadManifest(backupId:) -> [BackupLibraryEntry]?` (no UI work). The existing `restore()` still shipping today is the "Restore all" path; new `restoreSelectively(backupId:selectedKeys:)` is the picker path. Net delta ≤ 80 LOC. |
| `vreader/Services/Backup/WebDAVProviderFactory.swift` | 101 | **modified** — wires `LazyDownloadCoordinator` and `WebDAVNetworkPolicy` into the provider. |
| `vreader/Views/Reader/ReaderNotifications.swift` | (read) | **modified** — add `bookFileStateDidChange` (`userInfo: ["fingerprintKey", "state"]`) and `bookDownloadProgress`. |
| `vreader/Views/BookRowView.swift` | 121 | **modified** — when `book.fileState != .local`, show cloud icon + size; for `.downloading`, show inline ProgressView; for `.failed`, show retry affordance. ≤ 60 LOC delta. |
| `vreader/ViewModels/LibraryViewModel.swift` | 254 | **modified** — observes `bookFileStateDidChange`; `deleteBook` calls remain the same (persistence layer differentiates). |
| `vreader/Views/Reader/ReaderContainerView.swift` | 376 | **modified** — open-flow gate: if `book.fileState != .local`, present `BookDownloadSheet` instead of dispatching to format host. ≤ 40 LOC delta. |
| `vreader/Views/Library/BookDownloadSheet.swift` (NEW) | ~120 | progress sheet shown when opening a non-local book. Cancel button. On `.local` transition, dismisses and the parent push proceeds. |
| `vreader/Views/Settings/WebDAVSettingsView.swift` | 398 (>300 ⚠ pre-existing) | **modified** — adds "Restore selectively…" alongside existing "Restore" button, "Wi-Fi only" toggle, "Clean unused remote files" row with confirmation dialog. ≤ 100 LOC delta — if it pushes past 500 LOC, extract a `WebDAVMaintenanceSection` subview. |
| `vreader/Views/Settings/SelectiveRestorePicker.swift` (NEW) | ~200 | sheet with a `LazyVStack` over `[BackupLibraryEntry]`, search field, sort by title/size/date, "select all" / "deselect all", footer with selected count + total size, "Restore selected" CTA. |
| `vreader/ViewModels/SelectiveRestoreViewModel.swift` (NEW) | ~150 | owns the picker's mutable selection set, sort/filter, computed totals. |
| `vreader/ViewModels/BackupViewModel.swift` | 172 | **modified** — adds `loadRemoteCatalog(backupId:)`, `performSelectiveRestore(backupId:selectedKeys:)`, `runRemoteBlobGC()`. ≤ 80 LOC delta. |
| `vreader/Views/Settings/RemoteBlobGCConfirmDialog.swift` (NEW) | ~80 | shows count + bytes from the GC dry-run; one button to apply, one to cancel. |
| **Test files** | — | see "Test catalogue" below |

Files explicitly **OUT** of scope:

- `BookFileMaterializer.swift` — used as-is from #46. Both selective restore and lazy download call it on a per-entry basis.
- `WebDAVBlobStore.swift` / `BackupBlobStore.swift` — no protocol changes.
- `BackupSectionDTOs.swift` — no DTO changes; `BackupLibraryEntry` already carries every field the picker needs (title, author, byteCount, format, originalExtension, addedAt, lastOpenedAt, blobPath).
- `BookImporter.swift` — used as-is via `.restore` source.
- Reader format hosts (`EPUBReaderHost`, `TXTReaderHost`, etc.) — they only run after `fileState == .local`. Gate is in `ReaderContainerView`.
- Search indexer — already reader-driven, not import-driven; ignores `remoteOnly` rows naturally.
- iCloud / S3 providers — protocol surface is unchanged; future providers conform without further #47 work.

## Prior art / project precedent / rejected alternatives

**Precedent in the codebase:**

- The `@Observable` `@MainActor` ViewModel pattern is established (see `BackupViewModel`, `LibraryViewModel`).
- `NotificationCenter` is the established cross-component bus (see `bookmarkAdded`, `readerDidClose`); using it for `bookFileStateDidChange` matches existing convention.
- `WebDAVBlobStore` (#46) demonstrates the protocol-adapter pattern for transport-neutral blob ops; we extend with `LazyDownloadCoordinator` rather than mutating the protocol.
- `BookFileMaterializer.classify(_:)` already separates "alreadyLocal" vs "needsDownload" via SHA-256 — phase 2 reuses it for both selective restore and lazy download paths.

**Industry precedent:**

- Apple Books / iCloud Drive: cloud icon + tap-to-download is the accepted iOS UX. Background `URLSession` with `isDiscretionary = true` is the documented Apple pattern for opportunistic transfers.
- Kindle's "Cloud" tab and Readwise's "All" view: selective fetch into local storage. Same model as ours.
- `NWPathMonitor` is the canonical reachability API since iOS 12 (no third-party SCNetworkReachability needed).

**Rejected alternatives:**

| Rejected | Why |
|----------|-----|
| Store `BookFileState` as a Codable struct on `Book` | SwiftData `@Model` plays badly with custom Codables for filtering; storing the raw `String` and computing `BookFileState` is the pattern used by `Book.format` already. |
| Make `BookFileState` part of `BackupLibraryEntry` (in the manifest) | The manifest describes server-side identity; client-side state is per-device. Don't conflate. |
| Foreground `URLSession` for downloads | Loses opportunistic scheduling, drains battery, and Apple's TR for media-style transfers explicitly recommends `isDiscretionary = true`. |
| Auto-retry failed downloads | Introduces error-handling surface (exponential backoff, transient vs permanent classification) for marginal gain; user retry is a single tap. |
| GC walks the local sandbox to find orphan files | Sandbox files are content-addressed by fingerprint; orphans there are an unrelated bug class. GC's job is server-side cleanup driven by manifests. |
| One-state `isLocal: Bool` instead of a 5-state enum | Loses `.downloading`, `.failed`, `.missingRemote` distinctions that the UI must show. |
| Add `BookFileState` only to `LibraryBookItem` (not `Book`) | Tap on a `remoteOnly` row in cold-launch state needs the persisted truth, not a runtime cache that resets. Must persist. |

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

`Book.fileState` is added with default `"local"` for existing rows. SwiftData lightweight migration handles the additive change automatically (SchemaV2/V3/V4/V5 all relied on the same pattern). `VReaderMigrationPlan.schemas` appends `SchemaV6.self`. `stages` stays empty.

**Verification path**: existing user's library on v3.11.x ships with `fileState == nil` rows; the SchemaV6 migration default is `"local"`, so every existing book lights up as `.local` post-upgrade. No reader/importer code path changes for the upgrade case.

### Where remote blob URL comes from

We already have `LibraryBookItem.resolvedFileURL` (sandbox path). For `remoteOnly` rows we need a **blob path**, not a URL — the blob is reachable only through the configured `WebDAVTransport`. Decision:

- Store `blobPath: String?` on `Book` as a new field in SchemaV6, populated by `insertRemoteOnlyBookRecords` (selective-restore preplant). Nil for `.local` books that never went through the picker (because their blob path can be recomputed via `BlobPath.make` from fingerprint fields if needed).
- Store `remoteByteCount: Int64?` for the row UI's size label (mirror of `byteCount`; the field is already on `Book` via `fileByteCount` for `.local` rows, but for `.remoteOnly` we want the manifest-provided size to show before any local file exists).

(`fileByteCount` already exists on `Book` so `remoteByteCount` is redundant — see "Open questions" #1.)

### How existing reader/importer/index code paths are gated on `BookFileState == .local`

Touchpoints today that assume "row → local file":

| Path | File | Gating |
|------|------|--------|
| Reader open dispatch | `ReaderContainerView.swift` | guard `book.fileState == .local` else present `BookDownloadSheet`. |
| Reader format hosts | `EPUBReaderHost`, `TXTReaderHost`, etc. | unchanged; only reachable when `fileState == .local`. |
| Search indexer trigger | `ReaderSearchCoordinator.indexBookContent` | unchanged; reader-driven, only fires when reader opens, which only opens when `fileState == .local`. |
| Library list display | `BookRowView.swift` | branch: `.local` → existing layout. Else show cloud icon + size, hide reading-time/speed (no reading session for un-downloaded book). |
| Delete | `PersistenceActor+Library.deleteBook` | unchanged on the row side; `LibraryViewModel.deleteBook` consults `fileState` only to decide whether to also remove the sandbox file (it does not currently — see "Open questions" #2). |
| Backup collection | `BackupDataCollector.collectLibraryManifest` | manifest only emits books whose blob is **present on the server**. A `remoteOnly` book on device A gets re-emitted on its next backup if its blob is still on the server (which we know because we know `blobPath` from the picker). |
| Backup blob upload | `WebDAVProvider.uploadBlobs` | already skips books whose `sandboxResolver` URL is missing (logs and continues). For `remoteOnly` rows the blob is by definition already on the server; the PROPFIND-by-size dedupe path means re-upload is a no-op. |

### Lazy download orchestration

**Owner**: `LazyDownloadCoordinator` is `@MainActor` `@Observable`. It owns:

- A single `URLSession` configured with `URLSessionConfiguration.background(withIdentifier: "com.vreader.app.book-downloads")` and `isDiscretionary = true`. (One identifier per app process; iOS persists pending tasks across launches.)
- An in-memory `[String: TaskProgress]` keyed by fingerprintKey, with `progress: Double, totalBytes: Int64, completedBytes: Int64, state: BookFileState`.
- A 2-task concurrency cap implemented as a serial queue of fingerprintKeys (extra taps go to the back; `cancel(fingerprintKey:)` removes them from any position).

**Progress flow**:

1. Tap `remoteOnly` row → `LibraryViewModel.requestDownload(fingerprintKey:)` → `LazyDownloadCoordinator.enqueue(...)`.
2. Coordinator sets `fileState = .downloading` via `PersistenceActor.setBookFileState` and posts `bookFileStateDidChange`.
3. `URLSessionDownloadTask` started against `BlobPath.make(...)`.
4. Per-byte progress goes through the delegate's `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)` callback → MainActor update of `TaskProgress` → posts `bookDownloadProgress`.
5. On `urlSession(_:downloadTask:didFinishDownloadingTo:)`: SHA-256-verify the temp file against manifest → call `BookImporter.importFile(at:source:.restore)` → on success, set `fileState = .local`, post `bookFileStateDidChange`.
6. On `urlSession(_:task:didCompleteWithError:)` with non-nil error: classify (`.notConnectedToInternet` → `.remoteOnly` revert; HTTP 404 → `.missingRemote`; everything else → `.failed`), post the appropriate transition.

**Cancellation**: `cancel(fingerprintKey:)` calls `task.cancel()` and reverts `fileState` to `.remoteOnly`. The SHA-256-verify step happens before `BookImporter.importFile`, so no half-imported rows are possible.

### Wi-Fi-only policy via `NWPathMonitor`

`WebDAVNetworkPolicy` owns a single `NWPathMonitor` and publishes the current path's `usesInterfaceType(.wifi)` boolean. The "Wi-Fi only" toggle is a `UserDefaults` boolean (`com.vreader.webdav.wifiOnly`, default `true`).

**`shouldStart() -> Bool` semantics**:

- `wifiOnly == false` → always `true`.
- `wifiOnly == true && currentInterface == .wifi` → `true`.
- `wifiOnly == true && currentInterface == .cellular` → `false`; coordinator marks the task `.downloading` with a "Waiting for Wi-Fi" sub-state. Background session re-evaluates when the interface flips.

(URLSession's own `allowsCellularAccess` is **not** sufficient: it cancels rather than defers when set to `false` mid-flight. We must gate at enqueue and re-evaluate on path change.)

### "Restore all" stays the phase-1 path

The existing `WebDAVProvider.restore(backupId:progress:)` keeps its semantics — it fetches every blob and ends with a fully-local library. The new "Restore selectively…" entry point routes to `restoreSelectively`, which differs in the materialize step.

Wi-Fi-only also gates "Restore all" — if Wi-Fi-only is on and the device is on cellular, the restore action is disabled with a tooltip pointing at the toggle.

### GC action — manifest scan + size estimate + explicit confirmation

**`RemoteBlobGarbageCollector`** in three steps:

1. **Catalog** — list `VReader/backups/*.vreader.zip`. For each ZIP, download (cheap; metadata-section ZIPs are small — typical < 1 MB), extract `library-manifest.json`, collect every `blobPath`. Union those into `referencedPaths: Set<String>`.
2. **Discover** — list `VReader/books/<format>/*` for each format (PROPFIND Depth: 1). Compute `existingPaths: Set<String>`.
3. **Diff** — `existingPaths.subtracting(referencedPaths)` = orphans. PROPFIND each orphan to fetch `getcontentlength` (we already do single-resource PROPFIND for #46). Sum bytes.

The action returns `GCDryRunResult { orphanCount: Int, freedBytes: Int64, paths: [String] }`. The caller (UI) shows confirmation. On confirm, `apply(_:)` deletes each path serially, returning a per-path success/failure list.

**Concurrency safety**: Even if device B uploads a new backup mid-GC, the new backup references blobs that were either already in `referencedPaths` (no harm) or are newly uploaded (and thus not in `existingPaths` from device A's earlier PROPFIND — we never delete what we didn't list). Worst case: a freshly orphaned blob from a deleted manifest survives one GC pass; next GC catches it.

GC is **explicit** (user invokes from settings) — never automatic.

### Selective-restore preplant

When the user picks 3 of 100 books:

1. Materialize the 3 chosen entries (call existing `BookFileMaterializer.materialize`) → 3 `.local` rows with full metadata via `BookImporter`.
2. **Preplant** the other 97 as `.remoteOnly` rows — synthesize `BookRecord`s from manifest fields without touching `BookImporter`. The preplant path lives in `PersistenceActor+RemoteOnly.insertRemoteOnlyBookRecords(_:)` and:
   - Sets `provenance` to a special-cased `.restore` value (matching `ImportSource.restore` semantics).
   - Stores `coverImagePath = nil` (covers come back when the user downloads — the manifest doesn't carry covers).
   - Stores `detectedEncoding = nil` (TXT encoding is detected at download).
   - Sets `fileState = .remoteOnly` and `blobPath = entry.blobPath`.
3. Run existing per-section metadata restore (positions, annotations, etc.) — they re-attach to the now-present rows by fingerprintKey, **including for the 97 remote-only rows**. So a tap-to-download book opens at the saved position.

### Reader-entry-point gate UX

In `ReaderContainerView.body`:

```swift
if book.fileState == .local {
    // existing dispatch
} else if let coordinator = downloadCoordinator {
    BookDownloadSheet(book: book, coordinator: coordinator) // full-screen
}
```

The sheet shows: cover (if available — usually nil for `remoteOnly`), title, author, format icon, byte size, a `ProgressView(value:)` bound to the coordinator's per-key progress, a Cancel button, an error state with Retry (when `.failed` / `.missingRemote`).

On `bookFileStateDidChange` to `.local`, the sheet auto-dismisses and the dispatcher proceeds.

## File-by-file changes

### New: `vreader/Models/BookFileState.swift` (~50 lines)

```swift
enum BookFileState: String, Sendable, Codable, CaseIterable, Equatable {
    case local
    case remoteOnly
    case downloading
    case failed
    case missingRemote

    /// True for states where opening the reader directly is allowed.
    var isReadable: Bool { self == .local }

    /// True for states from which the user can initiate a download.
    var canDownload: Bool {
        switch self {
        case .remoteOnly, .failed: return true
        case .local, .downloading, .missingRemote: return false
        }
    }
}
```

### Modified: `vreader/Models/Book.swift`

- Add `var fileState: String = "local"` (raw value; SwiftData-friendly).
- Add `var blobPath: String?` (only populated for `remoteOnly` preplants; nil for `.local` books that came through `BookImporter`).
- Update `init(...)` to accept both, both defaulting (`fileState: BookFileState = .local`).

### New: `vreader/Models/Migration/SchemaV6.swift` (~30 lines)

Mirrors SchemaV5; lists the same models. Lightweight migration applies because both new fields are additive with defaults / optional.

### Modified: `vreader/Models/Migration/SchemaV1.swift`

Append `SchemaV6.self` to `VReaderMigrationPlan.schemas`. `stages` stays `[]`.

### Modified: `vreader/Models/LibraryBookItem.swift`

```swift
struct LibraryBookItem: ... {
    // existing fields...
    let fileState: BookFileState        // NEW
    let blobPath: String?               // NEW (nil for .local rows)

    /// True if reader can open this book directly.
    var isReadable: Bool { fileState.isReadable }
}
```

`resolvedFileURL` returns the same URL regardless of state — but callers must check `fileState` first.

### Modified: `vreader/Services/PersistenceActor.swift`

- `BookRecord` adds `let fileState: BookFileState` (default `.local`) and `let blobPath: String?` (default `nil`).
- `bookToRecord` reads `book.fileState` and parses; falls back to `.local` for unknown raw strings.
- `insertBook` writes both fields.

### New: `vreader/Services/PersistenceActor+RemoteOnly.swift` (~80 lines)

```swift
extension PersistenceActor {
    /// Inserts BookRecords with fileState = .remoteOnly. Skips entries whose
    /// fingerprintKey already exists locally (idempotent re-pick safe).
    func insertRemoteOnlyBookRecords(_ records: [BookRecord]) async throws -> [String] {
        // returns the list of inserted fingerprintKeys
    }

    /// Updates fileState for an existing book. Throws if no row matches.
    func setBookFileState(fingerprintKey: String, newState: BookFileState) async throws

    /// Updates blobPath (used when SelectiveRestoreCoordinator first preplants
    /// a row). Idempotent.
    func setBookBlobPath(fingerprintKey: String, blobPath: String?) async throws
}
```

### Modified: `vreader/Services/PersistenceActor+Library.swift`

`fetchAllLibraryBooks` populates the new `LibraryBookItem.fileState` + `blobPath`. `deleteBook` is **unchanged** on the persistence side — sandbox file removal was already not happening; phase 2 keeps that behavior because deleting a `.remoteOnly` row should have no file to delete and deleting a `.local` row already left the sandbox file behind. (This is a known phase-1 issue; see "Open questions" #2 for whether to address as part of #47 or file separately.)

### New: `vreader/Services/Backup/RemoteBookCatalog.swift` (~80 lines)

```swift
struct RemoteBookCatalog: Sendable {
    let provider: WebDAVProvider

    /// Downloads the backup ZIP, extracts library-manifest.json, returns entries.
    /// Cached by backupId in-memory; cache cleared on `loadBackups()` refresh.
    func loadCatalog(backupId: UUID) async throws -> [BackupLibraryEntry]
}
```

Uses existing `WebDAVTransport.download` + `ZIPWriter.extractEntry` (both already exist from #46).

### New: `vreader/Services/Backup/WebDAVNetworkPolicy.swift` (~80 lines)

```swift
@MainActor
@Observable
final class WebDAVNetworkPolicy {
    private(set) var interface: PathInterface = .none
    var wifiOnly: Bool { didSet { saveDefault() } }

    enum PathInterface: Sendable, Equatable { case none, cellular, wifi }

    init(defaults: UserDefaults = .standard) { ... }

    /// True if a download/backup transfer is allowed to start now.
    func shouldStart() -> Bool { ... }
}
```

`UserDefaults` key: `com.vreader.webdav.wifiOnly` (default `true`).

### New: `vreader/Services/Backup/LazyDownloadCoordinator.swift` (~220 lines)

```swift
@MainActor
@Observable
final class LazyDownloadCoordinator: NSObject, URLSessionDownloadDelegate {

    struct TaskProgress: Sendable, Equatable {
        let fingerprintKey: String
        let totalBytes: Int64
        let completedBytes: Int64
        let waitingForWiFi: Bool
        var fraction: Double { ... }
    }

    private(set) var inFlight: [String: TaskProgress] = [:]

    init(
        persistence: PersistenceActor,
        importer: any BookImporting,
        materializer: BookFileMaterializer,
        policy: WebDAVNetworkPolicy,
        sessionIdentifier: String = "com.vreader.app.book-downloads",
        maxConcurrent: Int = 2
    )

    func enqueue(fingerprintKey: String, blobPath: String, expectedSHA256: String, expectedByteCount: Int64) async
    func cancel(fingerprintKey: String) async

    // URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) { ... }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) { ... }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) { ... }
}
```

The `URLSession` is built once with `.background(withIdentifier:)` + `isDiscretionary = true` + `sessionSendsLaunchEvents = true`. Per Apple's guidance for opportunistic transfers.

(Alternative: have `LazyDownloadCoordinator` own a non-isolated `URLSession` and hop to `@MainActor` only inside the delegate methods. Decide during WI-3 implementation; both work.)

### New: `vreader/Services/Backup/SelectiveRestoreCoordinator.swift` (~150 lines)

```swift
struct SelectiveRestoreCoordinator: Sendable {

    let provider: WebDAVProvider
    let materializer: BookFileMaterializer
    let persistence: PersistenceActor
    let dataRestorer: BackupDataRestoring

    /// Materializes selected fingerprintKeys, preplants the rest as remoteOnly,
    /// then runs metadata restore. Progress flows in three phases:
    /// preplant (0 → 0.10) → materialize (0.10 → 0.85) → metadata (0.85 → 1.0).
    func restoreSelectively(
        backupId: UUID,
        manifest: [BackupLibraryEntry],
        selectedKeys: Set<String>,
        progress: @Sendable (Double) -> Void
    ) async throws
}
```

### New: `vreader/Services/Backup/RemoteBlobGarbageCollector.swift` (~120 lines)

```swift
struct RemoteBlobGarbageCollector: Sendable {

    let transport: any WebDAVTransport
    let blobStore: any BackupBlobReading

    struct DryRunResult: Sendable, Equatable {
        let orphanPaths: [String]
        let freedBytes: Int64
        var orphanCount: Int { orphanPaths.count }
    }

    /// Walks every backup ZIP's manifest, lists VReader/books/**, returns
    /// candidates for deletion. Does NOT delete anything.
    func dryRun() async throws -> DryRunResult

    /// Deletes the listed paths. Returns per-path success/failure.
    func apply(_ result: DryRunResult) async -> [String: Result<Void, BackupBlobStoreError>]
}
```

### Modified: `vreader/Services/Backup/WebDAVProvider.swift`

Net adds:

- `func loadManifest(backupId: UUID) async throws -> [BackupLibraryEntry]?` — used by both `SelectiveRestorePicker` and the GC. Returns nil for v1-format ZIPs (no manifest).
- `func restoreSelectively(backupId: UUID, selectedKeys: Set<String>, progress: ...)` — delegates to `SelectiveRestoreCoordinator`.

The existing `restore(backupId:progress:)` is unchanged.

If WebDAVProvider grows past 600 LOC, extract `WebDAVProvider+Restore.swift`.

### Modified: `vreader/Services/Backup/WebDAVProviderFactory.swift`

Inject `LazyDownloadCoordinator` and `WebDAVNetworkPolicy` (production singletons created in `VReaderApp.init` and threaded through SwiftUI Environment, or owned by `BackupViewModel`).

### Modified: `vreader/Views/Reader/ReaderNotifications.swift`

```swift
extension Notification.Name {
    /// Posted when a book's fileState changes. userInfo:
    /// ["fingerprintKey": String, "state": String (BookFileState raw)]
    static let bookFileStateDidChange = Notification.Name("vreader.book.fileState.didChange")

    /// Posted as download progresses. userInfo:
    /// ["fingerprintKey": String, "completed": Int64, "total": Int64, "waitingForWiFi": Bool]
    static let bookDownloadProgress = Notification.Name("vreader.book.download.progress")
}
```

### Modified: `vreader/Views/BookRowView.swift`

Branch on `book.fileState`:

- `.local` → existing layout.
- `.remoteOnly` → cloud icon (`icloud.and.arrow.down`) replacing the format icon, size label instead of reading time.
- `.downloading` → spinner with progress; tap → cancel sheet.
- `.failed` → `exclamationmark.icloud` icon with retry hint.
- `.missingRemote` → `xmark.icloud` icon with "blob removed from server" hint.

### Modified: `vreader/Views/Reader/ReaderContainerView.swift`

```swift
if book.fileState.isReadable {
    Group { /* existing dispatch */ }
} else {
    BookDownloadSheet(book: book, coordinator: downloadCoordinator)
}
```

### New: `vreader/Views/Library/BookDownloadSheet.swift` (~120 lines)

Full-screen sheet bound to coordinator state. Auto-dismisses (and reader push proceeds) when `bookFileStateDidChange` fires with `.local`.

### Modified: `vreader/ViewModels/LibraryViewModel.swift`

Adds `requestDownload(fingerprintKey:)`, `cancelDownload(fingerprintKey:)`, observes `bookFileStateDidChange` to keep `books` array in sync.

### New: `vreader/ViewModels/SelectiveRestoreViewModel.swift` (~150 lines)

Owns the picker's mutable state.

```swift
@MainActor
@Observable
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
    func toggleSelection(_ key: String)
    func selectAll()
    func deselectAll()
}
```

### New: `vreader/Views/Settings/SelectiveRestorePicker.swift` (~200 lines)

`LazyVStack` over `viewModel.filtered`. Each row: format icon, title, author, byte size, last-opened date, checkbox bound to `selection.contains(entry.fingerprintKey)`. Footer: "Restore N (X MB)" CTA.

### Modified: `vreader/Views/Settings/WebDAVSettingsView.swift`

- Add Wi-Fi-only toggle row (bound to `WebDAVNetworkPolicy.wifiOnly`).
- Add "Restore selectively…" button alongside the existing "Restore" affordance per backup row.
- Add "Clean unused remote files" row in a new "Maintenance" section.
- If file > 500 LOC after edits, extract `WebDAVMaintenanceSection.swift`.

### Modified: `vreader/ViewModels/BackupViewModel.swift`

```swift
func loadRemoteCatalog(backupId: UUID) async -> [BackupLibraryEntry]
func performSelectiveRestore(backupId: UUID, selectedKeys: Set<String>) async
func runRemoteBlobGCDryRun() async -> RemoteBlobGarbageCollector.DryRunResult?
func applyRemoteBlobGC(_ result: RemoteBlobGarbageCollector.DryRunResult) async
```

### New: `vreader/Views/Settings/RemoteBlobGCConfirmDialog.swift` (~80 lines)

Confirmation dialog for the GC. Apply / Cancel.

## Test catalogue

| Test file | Coverage |
|-----------|----------|
| `BookFileStateTests.swift` (NEW) | enum raw round-trip, `isReadable` / `canDownload` truth tables, allCases stability. |
| `BookFileStateMigrationTests.swift` (NEW) | V5 → V6 migration: existing rows default `fileState == "local"`. Use in-memory `ModelContainer` configured with both schemas. |
| `LibraryBookItemTests.swift` (extended) | `fileState`/`blobPath` expose correctly; `resolvedFileURL` independent of state. |
| `PersistenceActorRemoteOnlyTests.swift` (NEW) | `insertRemoteOnlyBookRecords` idempotency (re-pick same key is a no-op), `setBookFileState` invalid transitions, `setBookBlobPath` round-trip. |
| `RemoteBookCatalogTests.swift` (NEW) | given a fixture ZIP, returns expected `[BackupLibraryEntry]`; v1-format ZIP returns nil. |
| `WebDAVNetworkPolicyTests.swift` (NEW) | `shouldStart()` truth table for all four (toggle × interface) combinations; UserDefault round-trip. |
| `LazyDownloadCoordinatorTests.swift` (NEW) | concurrency cap of 2, queue ordering, cancel removes from any position, Wi-Fi-only gating with mocked policy, SHA-256-mismatch path triggers `.failed` and not `.local`, retry after `.failed` works. Use `URLProtocol` mock for the session. |
| `SelectiveRestoreCoordinatorTests.swift` (NEW) | given manifest of 5 + selection of 2, persists 2 `.local` + 3 `.remoteOnly`; metadata restore re-attaches positions to all 5 rows. |
| `RemoteBlobGarbageCollectorTests.swift` (NEW) | given 3 manifests with overlapping book sets, `dryRun()` returns the unique-to-deleted-manifest blobs; `apply` deletes only listed paths. |
| `SelectiveRestoreViewModelTests.swift` (NEW) | filter by title, sort by size, selectAll/deselectAll, totalSelectedBytes math, empty-catalog edge case. |
| `BackupViewModelTests.swift` (extended) | `performSelectiveRestore` happy path, GC dry-run + apply round-trip, error surfacing. |
| `LazyDownloadIntegrationTests.swift` (NEW; Docker WebDAV) | restore selectively (1 of 3) → 1 local + 2 remoteOnly → tap remote → download → verify SHA + open at saved position. |
| `RemoteGarbageCollectorIntegrationTests.swift` (NEW; Docker WebDAV) | back up two libraries with one shared book → delete one backup → run GC → only unique blob deleted. |
| `WebDAVBackupIntegrationTests.swift` (extended) | regression: existing "Restore all" path still works against feature-#47-shaped backups. |

**Edge cases explicitly covered**:

- Empty manifest (selective picker shows empty state, not crash).
- 10k-entry manifest (`LazyVStack` virtualizes; sort doesn't choke).
- Tap `remoteOnly` row offline (`.notConnectedToInternet`) → row stays `remoteOnly`, error toast (does NOT flip to `.failed`).
- Tap `remoteOnly` row when blob 404s → `.missingRemote`.
- Mid-download cancel → row reverts to `.remoteOnly`, no half-imported state.
- Storage pressure during download (set `.isExcludedFromBackup = false` only after successful import).
- Wi-Fi-only toggle flipped mid-flight → in-flight task continues (already started); next enqueue reads fresh policy.
- App relaunch with pending background downloads → `URLSession.background` resumes; coordinator re-attaches via session-identifier match.
- Concurrent backup on device B during GC on device A → covered by content-addressing convergence.
- Unicode/CJK title in selective picker search → NFC-normalize search text.
- RTL title rendering → relies on existing SwiftUI text mirror behavior.

## Sequencing

Each WI: RED test first, then GREEN, REFACTOR. Each WI ships its own PR with version bump (per `40-version-bump.md`) and is audited per Gate 4. Aggregating the picker UI + lazy download + GC into eight WIs; foundational tier ships without device verification.

| WI | Tier | What | Files | Estimated PR |
|----|------|------|-------|--------------|
| 1  | foundational | `BookFileState` enum + `Book.fileState` + `Book.blobPath` + SchemaV6 + migration plan append. Tests cover migration. | 5 prod, 2 test | small |
| 2  | foundational | `BookRecord` + `LibraryBookItem` carry `fileState`/`blobPath`. `PersistenceActor+RemoteOnly` (insertRemoteOnly, setFileState, setBlobPath). Tests. | 4 prod, 1 test | medium |
| 3  | behavioral | `LazyDownloadCoordinator` + `WebDAVNetworkPolicy` + notifications. Tests use `URLProtocol` mock. **Slice verify**: enqueue a download, observe state transitions in a debug-bridge eval. | 3 prod, 2 test | medium |
| 4  | behavioral | `RemoteBookCatalog` + `SelectiveRestoreCoordinator` + `WebDAVProvider.loadManifest` + `restoreSelectively`. Tests cover preplant + materialize + metadata wiring. **Slice verify**: pick 2 of 5 → assert 2 local + 3 remoteOnly + positions restored. | 4 prod, 2 test | medium |
| 5  | behavioral | `BookRowView` branching; `LibraryViewModel` observes notifications; `ReaderContainerView` gate; `BookDownloadSheet`. **Slice verify**: tap a remote-only row, watch the sheet, watch the row flip. | 4 prod, 1 test | medium |
| 6  | behavioral | `SelectiveRestoreViewModel` + `SelectiveRestorePicker` + `WebDAVSettingsView` integration (picker entry + Wi-Fi toggle row). **Slice verify**: open picker on a 5-book backup → check 2 → restore. | 4 prod, 1 test | medium |
| 7  | behavioral | `RemoteBlobGarbageCollector` + GC confirm dialog + settings entry. **Slice verify**: 3 manifests + GC → assert correct deletions. | 3 prod, 2 test | medium |
| 8  | final | Docker integration tests (lazy download + GC); `docs/architecture.md` Backup section update; manual-test-checklist recipe; row #47 → DONE. **Full acceptance pass** per Gate 5: every acceptance criterion exercised. | 4 mod, 1 test | small |

Critical path: WI-1 → WI-2 → (WI-3 + WI-4 in parallel) → WI-5 → WI-6 → WI-7 → WI-8.

WIs 3 and 4 can ship in either order or in parallel because their surfaces don't overlap.

UI WIs (5, 6, 7) gate on the data plumbing in WIs 1-4.

WI count: **8**. Below the workflow rule's 10-WI threshold; no split needed. (If audit pushes back on cohesion, candidate split is "WI-7 + GC dialog → feature #47b" since GC is the most independent slice.)

## Risks + mitigations

| Risk | Mitigation |
|------|-----------|
| `URLSession.background` + `isDiscretionary` is reportedly slow when iOS deprioritizes the session — users may see "Wi-Fi-only ON" downloads stall for hours | Document the expected latency in user-facing copy; offer a "Download now (use cellular)" override that flips wifiOnly transiently for a single transfer. |
| `URLSession.background` requires `application(_:handleEventsForBackgroundURLSession:completionHandler:)` in `UIApplicationDelegate`. vreader uses `@main App` + SwiftUI lifecycle. | Adopt `UIApplicationDelegateAdaptor` for this single delegate hook. Confirmed pattern; one ~20-LOC adapter. |
| `BookFileState` migration on a large library could block app launch | Migration is column-add with a default; SwiftData handles in O(rows). Worst-case 10k rows ≈ tens of ms. Tested in WI-1. |
| Selective picker on 10k-book backup loads slowly | Manifest is small (~150 bytes/entry → 1.5 MB for 10k books). Load happens once on sheet open, cached in `RemoteBookCatalog`. `LazyVStack` virtualizes display. |
| GC race with concurrent backup on device B deletes a blob B just uploaded | Covered by content-addressing — B's just-uploaded blob is at `existingPaths` time of A's PROPFIND; it's referenced by B's manifest only after B finishes its ZIP upload. There's a narrow window where A's manifest scan happens after B uploads the blob but before B uploads the ZIP — A's GC would delete it. Mitigation: GC ignores blobs created within the last 60 seconds (parse `getlastmodified` from PROPFIND). |
| Background download completion when app is suspended needs `application(_:handleEventsForBackgroundURLSession:completionHandler:)` | See app-delegate adaptor mitigation above. |
| `NWPathMonitor` reports `.cellular` for tethering; user expects that to count as "Wi-Fi" | Document: Wi-Fi-only follows iOS's interface classification. Power-users can flip the toggle for tethered situations. |
| Cover images are absent for `.remoteOnly` rows; user sees same icon for every book | `BackupLibraryEntry` already carries title + author. Cover comes back when the book downloads. Acceptable phase-2 limitation. |
| `URLSessionDownloadTask` writes to a temp file iOS may evict; the SHA-256 verify must complete inline before iOS moves on | The delegate's `didFinishDownloadingTo` runs synchronously and blocks until we move/copy the file; standard pattern is to copy + return. |
| User triggers "Restore all" mid-selective restore | `BackupViewModel.isRestoring` already gates concurrent restores; selective restore reuses the same flag. |
| Reader open path's `BookDownloadSheet` race: download completes after user dismisses navigation | Sheet observes `bookFileStateDidChange`; on `.local` → auto-dismiss → caller pushes reader. If user already went back to library, `.local` transition just refreshes the row. No reader is force-pushed. |

## Backward compat

Three scenarios:

1. **Existing v3.11.x library upgrades to v3.12.0 (this feature)**: every existing row gets `fileState = .local` via SchemaV6 default. No reader/importer/index path changes for them.
2. **v3.11.x backup restored on v3.12.0 device via "Restore all"**: identical to phase-1 behavior. All books materialize as `.local`. `library-manifest.json` is the same shape (DTOs unchanged).
3. **v3.12.0 device with `.remoteOnly` rows backs up to a v3.11.x peer (or with v3.11.x app)**: `.remoteOnly` rows still emit a manifest entry pointing at `blobPath`. Phase-1 restore tries to fetch the blob; if it's still on the server, success. If the user GC'd the blob, phase-1 logs an error and the row is silently skipped (existing phase-1 behavior). Acceptable: a non-v3.12.0 client downgrades the experience but never corrupts data.

## Open questions (for Gate-2 audit)

1. **Redundancy between `Book.fileByteCount` and a new `remoteByteCount`?** `fileByteCount` is set at import time to the local file size (mandatory because of how SwiftData maps the field — see `Book.swift:46`). For a `.remoteOnly` preplant, the byte count comes from the manifest, which is identical. So `fileByteCount` should suffice. Skip the new `remoteByteCount` field. Confirm during audit.

2. **Should `.local` book deletion remove the sandbox file as part of #47?** Today, `PersistenceActor+Library.deleteBook` (line 55) does **not** remove the sandbox book file. This is technically a phase-1 latent issue. Phase 2 makes it more visible because users will toggle local/remote more often. **Proposal**: file as a separate bug, do not bundle into #47 — keeps the plan focused. Audit input requested.

3. **`URLSession.background` + `URLSessionDelegate` ownership when the coordinator is `@MainActor`.** Apple's docs say the delegate may be called on a non-main queue. Three options: (a) `@MainActor` coordinator + dispatch every callback to MainActor; (b) non-isolated `URLSession` wrapper actor + MainActor `Observable` wrapper; (c) plain `final class` coordinator with internal lock. We've sketched (a) but defer to audit.

4. **Should `RemoteBlobGarbageCollector` be transport-neutral (`BackupBlobReading`)?** That's the #46 pattern. The GC needs PROPFIND-list-directory in addition to download — which `BackupBlobReading` doesn't expose. Decision: keep GC WebDAV-specific for now (depends on `WebDAVTransport.listDirectory` directly); generalize when a second blob backend appears. Audit input requested.

5. **`UIApplicationDelegateAdaptor` placement.** Adding the delegate hooks just for background URLSession completion. Does the existing app structure tolerate it? (Should be yes — standard pattern — but audit can verify against `VReaderApp.swift:1-160`.)

6. **Indexing notification.** `BookImporter.indexingNeededNotification` is posted when the materializer imports a freshly-downloaded book. As of phase 1 there's no production observer (search indexer is reader-driven). Phase 2 doesn't change this. If a future audit determines restored books need explicit indexing, that's a separate feature.

7. **Should the selective picker support a "preview cover" by downloading a few KB?** Manifest entries don't carry cover data, and EPUB cover extraction requires the full file. Decision: skip for #47; rely on title/author display. Audit input requested.

8. **Does Wi-Fi-only ON gate "Back Up Now" too, or only restore/download?** Symmetry argues yes; user experience argues yes (avoid surprise cellular use during a metadata backup). **Proposal**: gate all transfers (backup + restore + lazy download). Audit input requested.

## Acceptance gate

- Plan exists at `dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md` ✅
- Gate 2 (Codex plan audit) — **pending**.
- Codex must verify model-assumption set: `BookFileState` raw-string storage on `Book`, SchemaV6 migration is lightweight, `BackupLibraryEntry` truly carries every field needed for picker UX (it does — see `BackupSectionDTOs.swift:231`), `URLSessionConfiguration.background` integrates with `@MainActor` coordinator pattern, `NWPathMonitor` `.wifi` classification semantics.
- Codex must critique the 8-WI sequencing for cohesion (any WI too big? two WIs that should merge?).
- Codex must look for missed edge cases: app-suspend mid-download, picker on empty manifest, GC race with concurrent backup, selection toggle while sort is changing.

Implementation begins at WI-1 only after audit findings are resolved (or accepted with rationale).
