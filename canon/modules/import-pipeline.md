---
title: Module — import pipeline
updated: 2026-07-10
status: verified
---

# Module — import pipeline

## Purpose

Turns a user-provided file (Files-app picker, iOS Share Sheet / "Open in", OPDS download, WebDAV restore blob, or DEBUG fixture seed) into a deduplicated library row: validate the format, detect text encoding, compute a content-based fingerprint, copy the bytes atomically into the app sandbox, extract title/author/cover, persist a `Book` row through the persistence actor, and notify the library UI. Kindle files are additionally converted to EPUB at this stage (see [[Module — Kindle AZW3 and libmobi]]).

## Key files and types

- `vreader/Services/BookImporter.swift` — `final class BookImporter: BookImporting, Sendable`, the orchestrator. Entry point: `func importFile(at fileURL: URL, source: ImportSource, titleOverride: String? = nil) async throws -> ImportResult`. Returns `ImportResult { fingerprintKey, title, author, fingerprint, provenance, detectedEncoding, isDuplicate, sourceCanonicalKey }`.
- `vreader/Services/BookImporting.swift` — the protocol (mock seam); an extension supplies the historical two-argument `importFile(at:source:)` overload.
- `vreader/Services/ImportError.swift` — `enum ImportError` (11 cases: `unsupportedFormat`, `binaryMasquerade`, `fileNotReadable`, `hashComputationFailed`, `duplicateBook`, `sandboxCopyFailed`, `encodingDetectionFailed`, `cancelled`, `securityScopeAccessDenied`, `bookNotFound`, `persistenceFailed`) with `userMessage` (sanitized for UI) and `diagnosticMessage`.
- `vreader/Services/ImportJobQueue.swift` — `actor ImportJobQueue` with a pending→running→completed/failed/cancelled state machine, `maxRetries` (default 3), and task-handle cancellation. Implemented and unit-tested (`vreaderTests/Services/ImportJobQueueTests.swift`) but NOT instantiated by any production call site — `LibraryViewModel` and the routers call the importer directly.
- `vreader/Services/Import/FileURLImportRouter.swift` — `@MainActor final class FileURLImportRouter`: dispatches incoming `file://` URLs from `VReaderApp`'s `.onOpenURL` (feature #59 WI-2). `dispatch(_ url: URL) -> Bool` returns false for non-file URLs; unsupported extensions go to an injected `reportUnknownExtension` closure (currently a no-op in production); supported ones fire-and-forget `importFile(at:source:.shareSheet)`.
- `vreader/Services/Import/AnnotationImporter.swift` (+ `VReaderAnnotationParser.swift`, `AnnotationImportError.swift`) — a separate lane: imports VReader JSON annotation exports, dedupes by annotation UUID against `existingAnnotationIds`, dispatches to `HighlightPersisting` / `BookmarkPersisting` / `AnnotationPersisting`, reports progress via callback. See [[Module — annotations and highlights]].
- `vreader/Services/MetadataExtractor.swift` — `protocol MetadataExtractor` (`extractMetadata(from:)`, `extractCoverImage(from:)` defaulting to nil) + `BookMetadata` + concrete `TXTMetadataExtractor`, `EPUBMetadataExtractor`, `PDFMetadataExtractor` (filename stub), `AZW3MetadataExtractor`; `MDMetadataExtractor` lives in `vreader/Services/MD/MDMetadataExtractor.swift`. Shared `maxTitleLength = 255`.
- `vreader/Utils/ContentHasher.swift` — `enum ContentHasher`, streaming CryptoKit SHA-256 in 64 KB chunks; returns `HashResult { sha256Hex, byteCount }`; `Task.checkCancellation()` per chunk, `CancellationError` rethrown as `ImportError.cancelled`.
- `vreader/Utils/EncodingDetector.swift` — TXT/MD encoding pipeline (see Data flow).
- Identity/value types in `vreader/Models/`: `BookFormat` (epub/pdf/txt/md/azw3; `.azw3` file extensions are `["azw3", "azw", "mobi", "prc"]`; `isSupportedExtension(_:)` is the router's gate), `DocumentFingerprint` (`canonicalKey` = `"{format}:{contentSHA256}:{fileByteCount}"`), `ImportSource` (`filesApp / shareSheet / icloudDrive / localCopy / restore`), `ImportProvenance` (`source`, `importedAt`, `originalURLBookmarkData`, plus best-effort `convertedFromKindleExtension` / `converterVersion`).
- `vreader/Utils/BookImporterEnvironment.swift` — SwiftUI `EnvironmentValues.bookImporter: (any BookImporting)?` so feature #46's WebDAV restore surface can reach the live importer.

## Dependencies

Internal: persistence via `protocol BookPersisting` (implemented by `PersistenceActor` — `findBook(byFingerprintKey:)`, `insertBook(_:)`, `replaceProvenance(_:toBookWithKey:)`, `updateBookTitle(fingerprintKey:title:author:)`, `setSourceCanonicalKey(_:forBookWithKey:)`; see [[Module — persistence and data model]]); covers via `CustomCoverStore`; EPUB metadata via `EPUBParser` + `ZIPReader`; instant-open via `EPUBPreExtractor` (`vreader/Services/EPUB/EPUBPreExtractor.swift`); Kindle conversion via `MobiEPUBConverter` gated by `FeatureFlags.kindleConvertOnImport`; AZW3 metadata/cover via `MOBIMetadataParser` / `MOBICoverExtractor` (`vreader/Services/AZW3/`). External: Foundation, CryptoKit, UIKit (`UIImage` covers), OSLog (`Logger(subsystem: "com.vreader.app", category: "BookImporter")`).

## Data flow

Call sites and their `ImportSource`:

- `LibraryViewModel.importFiles(_ urls:)` — `.filesApp`; wired from `LibraryViewSheets.swift`'s `.fileImporter` and from the `.opdsBookDownloaded` notification posted by `OPDSEntryView` after an OPDS download (see [[Module — OPDS]]).
- `FileURLImportRouter.dispatch(_:)` — `.shareSheet`.
- `BookFileImportFinalizer.finalize(localTempURL:entry:)` (`vreader/Services/Backup/`, feature #47 WI-4a) — `.restore`, with `titleOverride: entry.title` (bug #247); called by `BookFileMaterializer` (restore-all path). The lazy-download coordinator (feature #47 WI-4b) does NOT call this `finalize` — it uses a separate `LazyDownloadFinalizer.finalize(stagedURL:meta:)` (existing `.remoteOnly` rows need a file-move + `fileState` flip that `BookImporter`'s dedupe branch doesn't perform); the two flavors reuse only the static `BookFileImportFinalizer.localFileSHA256` hashing helper. See [[Module — backup and WebDAV]].
- `RealDebugBridgeContext.seed(fixture:)` — `.localCopy` for DEBUG fixture seeding ([[Module — debug bridge]]).

`importFile` pipeline (step numbers are the code's own comments):

0. Reject non-`file://` URLs and directories (`.fileNotReadable`).
1. Resolve `BookFormat` from the lowercased path extension (`.unsupportedFormat`).
2–3. `startAccessingSecurityScopedResource()` with `defer` cleanup; readability check (`.securityScopeAccessDenied` when scope was refused).
3.5. Kindle convert-on-import (feature #42 Phase 2 WI-4b): when `FeatureFlags.isEnabled(.kindleConvertOnImport)` and `format.isKindleConvertible`, hash the SOURCE bytes first (feature #108: `sourceCanonicalKey` = `azw3:{sha256_of_source}:{bytes}`, format normalized to `.azw3`), then `MobiEPUBConverter.convertToFile(mobiPath:destinationDir:)` — both off-main via `Task.detached(priority: .userInitiated)`. On success the rest of the pipeline runs over the converted EPUB (`workingFormat = .epub`); a semantic failure (`MobiDecodeError`/`MobiEPUBError`) logs and falls back to native Kindle import; filesystem write failures propagate.
4. TXT/MD only: read a 64 KB sample (`readFileDataSample`) and run `EncodingDetector.detect(data:)`. Detector order: BOM sniff (UTF-32LE/BE, UTF-8, UTF-16LE/BE — deliberately BEFORE the binary check because UTF-16/32 contain 0x00 bytes) → binary-masquerade check (first 8 KB; >10% control bytes excluding `\t\n\r` throws `.binaryMasquerade`) → strict UTF-8 → `NSString.stringEncoding(for:)` heuristic with suggested encodings `[.windowsCP1252, .isoLatin1, .shiftJIS, GB18030, EUC-KR, Big5]` → CP1252 → lossy UTF-8 with U+FFFD. `encodingName(_:)` stores an IANA-style name (e.g. `"utf-8"`, `"windows-1252"`) on the row.
5–6. `ContentHasher.hash(fileAt:)` on the working file → `DocumentFingerprint.validated(...)` (64 lowercase hex chars enforced).
7. Dedupe: `persistence.findBook(byFingerprintKey:)`. On a hit: `replaceProvenance` with the new source (carrying Kindle-origin fields so a re-import doesn't wipe them — bug #307), backfill `setSourceCanonicalKey` if the existing row's is nil and one was computed (feature #108), apply a differing `titleOverride` via `updateBookTitle` (bug #247), post `.bookDidImport`, return `ImportResult(isDuplicate: true)`. The V1 importer never throws `.duplicateBook` — that case is reserved.
8. `atomicCopyToSandbox`: destination is Application Support `ImportedBooks/` (wired in `VReaderApp`), filename = `fingerprintKey` with `:` → `_` plus the format's first extension; copy to a hidden `.<name>_<UUID>.tmp` then `moveItem` rename. An already-existing final file (crash re-import / concurrent import) is returned with `createdByThisImport: false`, so rollback never deletes another import's file; a rename race where the other side won is treated as success.
9–9.5. Metadata extraction from the working URL (converted-Kindle books read the self-describing EPUB, so `EPUBMetadataExtractor` recovers baked-in title/author/cover); cover extraction is non-fatal and skipped if `CustomCoverStore.hasCover(for:)`.
10–11. Build `ImportProvenance` (recording `convertedFromKindleExtension` + `MobiEPUBConverter.version` when conversion ran) and `BookRecord` (including `originalExtension` from the WORKING file — `"epub"` for converted Kindle — and `sourceCanonicalKey`), then `persistence.insertBook`. Failures roll back the sandbox copy (only if owned) and the cover.
12. Removed (bug #139): a forward-looking `indexingNeeded` notification was dead code; search indexing actually happens lazily on search-open.
13. Post `NotificationCenter` `.bookDidImport` (`"vreader.import.bookDidImport"`, userInfo `["fingerprintKey": String]`) — observed by `LibraryViewObservers` to force-refresh the imperative `loadBooks()` list (bug #197); posted on both new-row and duplicate paths. Then for EPUBs a detached `.utility` task runs `EPUBPreExtractor.preExtract(epubURL:)` for instant open. See [[Architecture — notification bus]].

## Concurrency

`BookImporter` is a `Sendable` final class, not an actor — serialization of writes lives in `PersistenceActor`. `ContentHasher` does synchronous file I/O with cooperative cancellation; the doc comment requires `@MainActor` callers to hop off first, which the Kindle path does explicitly with `Task.detached`. `FileURLImportRouter` is `@MainActor` and launches the import in a `Task { @MainActor ... }`. `titleOverride` normalization (trim → empty-is-nil → 255-char cap) happens once at entry so the insert path, the dedupe-update path, and the returned `ImportResult.title` agree.

## Edge cases and invariants

- Identity is content-based: same bytes + size + format ⇒ same `fingerprintKey` ⇒ dedupe hit regardless of filename or source.
- `BookMetadata.fromFilename` guards dot-prefixed no-stem names (a file named `.txt`) → `"Untitled"`; titles capped at 255 chars everywhere (extractors, override, `Book.init`).
- `EPUBMetadataExtractor.coverPathCandidates` (bug #122) cascades: spec-resolved OPF href → case-insensitive basename match anywhere in the archive (entries inside the OPF directory ranked first) → root-level `cover.{jpg,jpeg,png,gif}`; first candidate whose bytes decode as `UIImage` wins.
- Import never deletes a file it didn't create (`SandboxCopyResult.createdByThisImport` gates rollback); cover save/remove uses `try?` (non-fatal by design).
- `ImportError.userMessage` deliberately omits paths/system detail; `diagnosticMessage` carries them for logs.
- Restore-path invariant: `BookFileImportFinalizer` verifies streaming SHA-256 against the manifest before importing and the resulting `fingerprintKey` against `entry.fingerprintKey` after.

## History

Feature #42 Phase 2 (Kindle convert-on-import, flag default ON since the G2 flip 2026-06-02), feature #46/#47 (WebDAV materializing restore + lazy download → `.restore` source, `BookFileImportFinalizer`), feature #59 WI-2 (`FileURLImportRouter`), feature #108 (`sourceCanonicalKey`, VERIFIED 2026-06-18, `docs/features.md` row 108). Bugs referenced in code comments: #122 (cover href cascade), #139 (dead indexing notification removed), #197 (`.bookDidImport` refresh signal), #247 (restore title override), #307 (dedupe preserves Kindle origin), #149/GH #340 (AZW3 EXTH title). Tests: `vreaderTests/Services/BookImporterTests.swift`, `BookImporterAZW3Tests.swift`, `BookImporterNotificationTests.swift`, `BookImporterOriginalExtensionTests.swift`, `ContentHasherTests.swift`, `EncodingDetectorTests.swift`, `ImportErrorTests.swift`, `ImportJobQueueTests.swift`, `Import/AnnotationImporterTests.swift`.

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]

**Verified.** 2026-07-11 — checked against: vreader/Services/BookImporter.swift, vreader/Services/BookImporting.swift, vreader/Services/ImportError.swift, vreader/Services/ImportJobQueue.swift, vreader/Services/Import/FileURLImportRouter.swift, vreader/Services/Import/AnnotationImporter.swift, vreader/Services/Import/VReaderAnnotationParser.swift, vreader/Services/Import/AnnotationImportError.swift, vreader/Services/MetadataExtractor.swift, vreader/Services/MD/MDMetadataExtractor.swift, vreader/Utils/ContentHasher.swift, vreader/Utils/EncodingDetector.swift, vreader/Models/BookFormat.swift, vreader/Models/DocumentFingerprint.swift, vreader/Models/ImportSource.swift, vreader/Models/ImportProvenance.swift, vreader/Models/Book.swift, vreader/Utils/BookImporterEnvironment.swift, vreader/Services/PersistenceActor.swift, vreader/Services/FeatureFlags.swift, vreader/App/VReaderApp.swift, vreader/Services/Libmobi/MobiEPUBConverter.swift, vreader/Services/Libmobi/MobiDocument.swift, vreader/Services/Libmobi/MobiEPUBAssembler.swift, vreader/Services/AZW3/MOBIMetadataParser.swift, vreader/Services/AZW3/MOBICoverExtractor.swift, vreader/Services/EPUB/EPUBPreExtractor.swift, vreader/Services/EPUB/EPUBParserProtocol.swift, vreader/Services/EPUB/ZIPReader.swift, vreader/Services/CustomCoverStore.swift, vreader/Services/Backup/BookFileImportFinalizer.swift, vreader/Services/Backup/BookFileMaterializer.swift, vreader/Services/Backup/LazyDownloadFinalizer.swift, vreader/Services/Backup/LazyDownloadCoordinator.swift, vreader/ViewModels/LibraryViewModel.swift, vreader/Views/Library/LibraryViewSheets.swift, vreader/Views/Library/LibraryViewObservers.swift, vreader/Views/OPDS/OPDSEntryView.swift, vreader/Services/DebugBridge/DebugBridge.swift, vreader/Services/DebugBridge/RealDebugBridgeContext.swift, docs/bugs.md, archive/bugs-history.md, docs/features.md
