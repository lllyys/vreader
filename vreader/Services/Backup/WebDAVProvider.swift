// Purpose: BackupProvider conformance for WebDAV storage backends.
// Creates ZIP backups of app data and uploads/downloads via WebDAVTransport.
// Restore delegates to BackupDataRestoring protocol for persistence-layer writes.

import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "WebDAVProvider")

//
// Key decisions:
// - Uses WebDAVTransport protocol for testability.
// - Backup format: ZIP with JSON files. Path: VReader/backups/<ts>_<id>.vreader.zip
// - Progress: collect (40%), archive (10%), upload (50%).
// - Restore extracts ZIP entries and delegates to BackupDataRestoring for import.
// - Missing entries during restore are silently skipped (forward compatibility).
//
// @coordinates-with: BackupProvider.swift, WebDAVClient.swift, ZIPWriter.swift

import Foundation

// MARK: - BackupDataCollecting Protocol

/// Abstracts data collection from the persistence layer for testability.
protocol BackupDataCollecting: Sendable {
    func collectAnnotations() async throws -> Data
    func collectPositions() async throws -> Data
    func collectSettings() async throws -> Data
    func collectCollections() async throws -> Data
    func collectBookSources() async throws -> Data
    func collectPerBookSettings() async throws -> Data
    func collectReplacementRules() async throws -> Data
    func getBookCount() async -> Int

    /// Feature #46 (WI-6): emits `library-manifest.json` carrying one
    /// `BackupLibraryEntry` per local book. Allows the restorer (WI-7+)
    /// to download missing book blobs on a fresh device. Default impl
    /// returns an empty manifest envelope so older provider impls stay
    /// source-compatible.
    func collectLibraryManifest() async throws -> Data

    /// Feature #58 (WI-5): emits `reading-history.json` carrying every
    /// `ReadingSession` + `ReadingStats` row. Default impl returns an empty
    /// envelope so existing mock collectors stay source-compatible.
    func collectReadingHistory() async throws -> Data

    /// Feature #89: emits `ai-conversations.json` carrying every persisted
    /// `ChatSession` (with its message blob). Default impl returns an empty
    /// envelope so existing mock collectors stay source-compatible.
    func collectAIConversations() async throws -> Data
}

extension BackupDataCollecting {
    func collectLibraryManifest() async throws -> Data {
        let envelope = BackupLibraryManifestEnvelope(
            schemaVersion: 1,
            books: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    func collectReadingHistory() async throws -> Data {
        let envelope = BackupReadingHistoryEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, sessions: [], stats: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    func collectAIConversations() async throws -> Data {
        let envelope = BackupAIConversationsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, sessions: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}

// MARK: - BackupDataRestoring Protocol

/// Abstracts data restoration into the persistence layer for testability.
/// Mirrors BackupDataCollecting for the restore path.
protocol BackupDataRestoring: Sendable {
    func restoreAnnotations(from data: Data) async throws
    func restorePositions(from data: Data) async throws
    func restoreSettings(from data: Data) async throws
    func restoreCollections(from data: Data) async throws
    func restoreBookSources(from data: Data) async throws
    func restorePerBookSettings(from data: Data) async throws
    func restoreReplacementRules(from data: Data) async throws

    /// Feature #58 (WI-5): restores the `reading-history.json` section.
    /// Default impl is a no-op so existing mock restorers stay source-compatible.
    func restoreReadingHistory(from data: Data) async throws

    /// Feature #89: restores the `ai-conversations.json` section.
    /// Default impl is a no-op so existing mock restorers stay source-compatible.
    func restoreAIConversations(from data: Data) async throws
}

extension BackupDataRestoring {
    func restoreReadingHistory(from data: Data) async throws {
        // Default: no-op. The production BackupDataRestorer overrides this.
    }

    func restoreAIConversations(from data: Data) async throws {
        // Default: no-op. The production BackupDataRestorer overrides this.
    }
}

// MARK: - WebDAVProvider

/// BackupProvider that stores backups on a WebDAV server.
final class WebDAVProvider: BackupProvider, @unchecked Sendable {

    private let transport: WebDAVTransport
    private let dataCollector: BackupDataCollecting
    private let dataRestorer: BackupDataRestoring
    private let deviceName: String
    private let appVersion: String
    private let basePath = "VReader/backups"

    /// Resolves the local sandbox URL for a (fingerprintKey, originalExtension)
    /// — used by feature #46 (WI-7) to locate book bytes for blob upload.
    /// Defaults to the production resolver shared with `BookFileMaterializer`.
    private let sandboxResolver: SandboxURLResolver

    /// Optional importer used by feature #46 (WI-8) to materialize books
    /// from manifest blobs during restore. Nil → manifest-extended restore
    /// is skipped (v1-format backups still restore as today).
    private let bookImporter: (any BookImporting)?

    /// Temp directory for restore-side blob downloads before BookImporter
    /// adopts them. Created under `FileManager.default.temporaryDirectory`
    /// by default.
    private let materializeTempDirectory: URL

    /// Blob store wrapping the same transport. Used by feature #46 to publish
    /// content-addressed book blobs atomically (PUT-tmp → PROPFIND-verify → MOVE)
    /// and to read blobs during materializing restore.
    private let blobStore: WebDAVBlobStore

    /// In-memory cache of known backup metadata, keyed by ID.
    private var metadataCache: [UUID: (metadata: BackupMetadata, remotePath: String)] = [:]

    init(
        transport: WebDAVTransport,
        dataCollector: BackupDataCollecting,
        dataRestorer: BackupDataRestoring,
        deviceName: String,
        appVersion: String,
        sandboxResolver: @escaping SandboxURLResolver = BookFileMaterializer.defaultSandboxResolver,
        bookImporter: (any BookImporting)? = nil,
        materializeTempDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VReaderRestore", isDirectory: true)
    ) {
        self.transport = transport
        self.dataCollector = dataCollector
        self.dataRestorer = dataRestorer
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.sandboxResolver = sandboxResolver
        self.bookImporter = bookImporter
        self.materializeTempDirectory = materializeTempDirectory
        self.blobStore = WebDAVBlobStore(transport: transport)
    }

    // MARK: - BackupProvider

    func backup(progress: @Sendable (Double) -> Void) async throws -> BackupMetadata {
        progress(0.0)

        // Phase 1: Collect metadata sections + library manifest (0.0 → 0.30)
        let collected: [(String, Data)]
        let manifestData: Data
        let manifest: BackupLibraryManifestEnvelope
        let bookCount: Int
        do {
            let a = try await dataCollector.collectAnnotations(); progress(0.04)
            let p = try await dataCollector.collectPositions(); progress(0.08)
            let s = try await dataCollector.collectSettings(); progress(0.12)
            let c = try await dataCollector.collectCollections(); progress(0.16)
            let bs = try await dataCollector.collectBookSources(); progress(0.20)
            let pbs = try await dataCollector.collectPerBookSettings(); progress(0.24)
            let rr = try await dataCollector.collectReplacementRules(); progress(0.25)
            let rh = try await dataCollector.collectReadingHistory(); progress(0.27)
            let ai = try await dataCollector.collectAIConversations(); progress(0.28)
            manifestData = try await dataCollector.collectLibraryManifest(); progress(0.29)
            bookCount = await dataCollector.getBookCount(); progress(0.30)
            collected = [
                ("annotations.json", a), ("positions.json", p), ("settings.json", s),
                ("collections.json", c), ("book-sources.json", bs), ("per-book-settings.json", pbs),
                ("replacement-rules.json", rr),
                ("reading-history.json", rh),
                ("ai-conversations.json", ai),
                ("library-manifest.json", manifestData),
            ]

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = (try? decoder.decode(BackupLibraryManifestEnvelope.self, from: manifestData))
                ?? BackupLibraryManifestEnvelope(schemaVersion: 1, books: [])
        } catch {
            throw BackupError.archiveCreationFailed("Failed to collect data: \(error.localizedDescription)")
        }

        // Phase 2: Create metadata + ZIP (0.30 → 0.40)
        let backupId = UUID()
        let now = Date()
        let totalSize = Int64(collected.reduce(0) { $0 + $1.1.count })
        let metadata = BackupMetadata(
            id: backupId, createdAt: now, deviceName: deviceName,
            appVersion: appVersion, bookCount: bookCount, totalSizeBytes: totalSize
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let metadataJSON = try? encoder.encode(metadata) else {
            throw BackupError.archiveCreationFailed("Failed to encode metadata")
        }

        var zipEntries = [ZIPWriter.Entry(name: "metadata.json", data: metadataJSON)]
        zipEntries += collected.map { ZIPWriter.Entry(name: $0.0, data: $0.1) }

        guard let zipData = try? ZIPWriter.createArchive(entries: zipEntries) else {
            throw BackupError.archiveCreationFailed("Failed to create ZIP archive")
        }
        progress(0.40)

        // Phase 3: Ensure server directory tree (0.40 → 0.45)
        do {
            for ancestor in nestedAncestors(of: basePath) {
                try await transport.createDirectory(path: ancestor)
            }
        } catch let error as WebDAVError {
            throw BackupError.storageUnavailable("WebDAV mkdir failed: \(error)")
        }
        progress(0.45)

        // Phase 4: Publish missing book blobs (0.45 → 0.85)
        // Per feature #46: each book is uploaded as a content-addressed blob
        // at VReader/books/<format>/<sha256>_<byteCount>.<ext>. PROPFIND-dedupe
        // makes repeat backups cheap (only NEW books transfer bytes).
        if !manifest.books.isEmpty {
            try await uploadBlobs(manifest.books, progressBase: 0.45, progressSpan: 0.40, progress: progress)
        }
        progress(0.85)

        // Phase 5: Upload metadata ZIP (0.85 → 1.0)
        let remotePath = makeRemotePath(id: backupId, date: now)
        do {
            try await transport.upload(data: zipData, toPath: remotePath)
        } catch let error as WebDAVError {
            throw BackupError.storageUnavailable("WebDAV upload failed: \(error)")
        } catch {
            throw BackupError.storageUnavailable("Upload failed: \(error.localizedDescription)")
        }

        metadataCache[backupId] = (metadata, remotePath)
        progress(1.0)
        return metadata
    }

    /// Uploads (or skips, if dedupe says they're already on the server) every
    /// blob referenced by the manifest. Surfaces server-capability gaps as a
    /// hard error so the user knows their server can't host atomic uploads.
    private func uploadBlobs(
        _ entries: [BackupLibraryEntry],
        progressBase: Double,
        progressSpan: Double,
        progress: @Sendable (Double) -> Void
    ) async throws {
        // Books may share a parent directory; create them all idempotently.
        // The blob path is "VReader/books/<format>/<sha256>_<byteCount>.<ext>"
        // so we need at least "VReader/books" + per-format subdirs created.
        var seenDirs: Set<String> = []
        let count = max(entries.count, 1)
        for (index, entry) in entries.enumerated() {
            let dir = (entry.blobPath as NSString).deletingLastPathComponent
            for ancestor in nestedAncestors(of: dir) where !seenDirs.contains(ancestor) {
                seenDirs.insert(ancestor)
                try? await transport.createDirectory(path: ancestor)
            }

            let localURL = sandboxResolver(entry.fingerprintKey, entry.originalExtension)
            guard let bytes = try? Data(contentsOf: localURL) else {
                log.error("Local blob missing for \(entry.fingerprintKey, privacy: .public) at \(localURL.path, privacy: .public); skipping upload")
                progress(progressBase + progressSpan * Double(index + 1) / Double(count))
                continue
            }
            do {
                _ = try await blobStore.putBlobAtomically(
                    bytes,
                    to: entry.blobPath,
                    expectedByteCount: entry.byteCount
                )
            } catch BackupBlobStoreError.serverCapabilityMissing(let cap) {
                throw BackupError.storageUnavailable("Server doesn't support \(cap); cannot publish blobs atomically")
            } catch {
                throw BackupError.storageUnavailable("Blob upload failed for \(entry.fingerprintKey): \(error)")
            }
            progress(progressBase + progressSpan * Double(index + 1) / Double(count))
        }
    }

    func restore(backupId: UUID, progress: @Sendable (Double) -> Void) async throws {
        progress(0.0)

        // Find the remote path for this backup
        let remotePath: String
        if let cached = metadataCache[backupId] {
            remotePath = cached.remotePath
        } else {
            // Refresh cache from server
            _ = try await listBackups()
            guard let cached = metadataCache[backupId] else {
                throw BackupError.backupNotFound(backupId)
            }
            remotePath = cached.remotePath
        }

        progress(0.10)

        // Download the ZIP
        let zipData: Data
        do {
            zipData = try await transport.download(fromPath: remotePath)
        } catch let error as WebDAVError {
            if case .notFound = error {
                throw BackupError.backupNotFound(backupId)
            }
            throw BackupError.storageUnavailable(
                "Download failed: \(error)"
            )
        }

        progress(0.50)

        // Validate the archive contains metadata
        do {
            let names = try ZIPWriter.listEntryNames(in: zipData)
            guard names.contains("metadata.json") else {
                throw BackupError.archiveCorrupted("Missing metadata.json in archive")
            }
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.archiveCorrupted(
                "Failed to read archive: \(error.localizedDescription)"
            )
        }

        progress(0.55)

        // Phase A — feature #46 (WI-8): if the ZIP carries library-manifest.json
        // AND this provider was constructed with a BookImporter, materialize
        // missing book blobs into the local sandbox BEFORE applying metadata
        // sections. Older v1-format backups (no manifest) skip this phase
        // and restore exactly as today.
        var materializeFailedTitles: [String] = []
        if let importer = bookImporter,
           let manifestData = try? ZIPWriter.extractEntry(named: "library-manifest.json", from: zipData),
           let manifest = decodeManifest(manifestData),
           !manifest.books.isEmpty {
            let materializer = BookFileMaterializer(
                blobStore: blobStore,
                importer: importer,
                tempDirectory: materializeTempDirectory,
                resolveSandboxURL: sandboxResolver
            )
            let results = await materializer.materialize(
                manifest.books
            ) { fraction in
                // Allocate 0.55 → 0.75 to materialization. The remaining
                // metadata-section restore consumes 0.75 → 1.0.
                progress(0.55 + 0.20 * fraction)
            }
            for result in results where !result.isSuccess {
                materializeFailedTitles.append(result.entry.title ?? result.entry.fingerprintKey)
            }
        }

        // Phase B — apply restored data to local database via BackupDataRestoring.
        // Each file is optional; missing entries are silently skipped.
        // Per-section errors don't abort the loop.
        let restoreFiles: [(filename: String, label: String, fn: (Data) async throws -> Void)] = [
            ("annotations.json", "annotations", dataRestorer.restoreAnnotations),
            ("positions.json", "reading positions", dataRestorer.restorePositions),
            ("settings.json", "settings", dataRestorer.restoreSettings),
            ("collections.json", "collections", dataRestorer.restoreCollections),
            ("book-sources.json", "book sources", dataRestorer.restoreBookSources),
            ("per-book-settings.json", "per-book settings", dataRestorer.restorePerBookSettings),
            ("replacement-rules.json", "replacement rules", dataRestorer.restoreReplacementRules),
            ("reading-history.json", "reading history", dataRestorer.restoreReadingHistory),
            ("ai-conversations.json", "AI conversations", dataRestorer.restoreAIConversations),
        ]

        let restorePhaseStart = (bookImporter != nil) ? 0.75 : 0.55
        let restorePhaseSpan = 1.0 - restorePhaseStart
        let totalFiles = Double(restoreFiles.count)
        var failedLabels: [String] = []
        for (index, item) in restoreFiles.enumerated() {
            if let entryData = try? ZIPWriter.extractEntry(named: item.filename, from: zipData) {
                do {
                    try await item.fn(entryData)
                } catch {
                    failedLabels.append(item.label)
                }
            }
            progress(restorePhaseStart + restorePhaseSpan * Double(index + 1) / totalFiles)
        }

        progress(1.0)

        // Surface partial failures from EITHER phase so the user knows what
        // didn't make it. Materialization failures are reported separately
        // from metadata-section failures (different failure classes).
        if !materializeFailedTitles.isEmpty {
            throw BackupError.restorePartiallyFailed(
                "books not materialized: \(materializeFailedTitles.joined(separator: ", "))"
                + (failedLabels.isEmpty ? "" : "; sections: \(failedLabels.joined(separator: ", "))")
            )
        }
        if !failedLabels.isEmpty {
            throw BackupError.restorePartiallyFailed(failedLabels.joined(separator: ", "))
        }
    }

    private func decodeManifest(_ data: Data) -> BackupLibraryManifestEnvelope? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
    }

    // MARK: - Selective restore (feature #47 WI-6)

    /// Fetches the backup ZIP for `backupId` and decodes its
    /// `library-manifest.json` into the entries the picker UI shows.
    /// - Returns nil for older backups (pre-#46) that don't carry a
    ///   manifest — the UI displays "this backup has no recoverable
    ///   book files; only metadata will restore".
    /// - Throws `BackupError.backupNotFound` / `.storageUnavailable` /
    ///   `.archiveCorrupted` for transport + ZIP errors.
    func loadManifest(backupId: UUID) async throws -> [BackupLibraryEntry]? {
        let zipData = try await fetchBackupZIP(backupId: backupId)
        do {
            return try RemoteBookCatalog.loadEntries(fromBackupZIP: zipData)
        } catch RemoteBookCatalogError.manifestMissing {
            return nil
        } catch let error as RemoteBookCatalogError {
            throw BackupError.archiveCorrupted("manifest decode failed: \(error)")
        }
    }

    /// Picker-driven restore: preplant unselected manifest entries as
    /// `.remoteOnly` rows, materialize the selected subset via the
    /// existing `BookFileMaterializer`, then apply the metadata
    /// sections present in the ZIP. Reading positions reattach to BOTH
    /// `.local` and `.remoteOnly` rows by fingerprintKey.
    /// - Throws `BackupError.backupNotFound` if the backup ID isn't
    ///   known, `.archiveCorrupted` if the ZIP doesn't carry a
    ///   manifest (caller should have checked via `loadManifest` first),
    ///   `.restorePartiallyFailed` if some materializations failed.
    /// - `persistence` is passed explicitly because `BookImporter`'s
    ///   reference to it is private; the caller (BackupViewModel)
    ///   already holds the live `PersistenceActor`.
    func restoreSelectively(
        backupId: UUID,
        selectedKeys: Set<String>,
        persistence: PersistenceActor,
        progress: @Sendable (Double) -> Void
    ) async throws -> SelectiveRestoreSummary {
        guard let importer = bookImporter else {
            throw BackupError.storageUnavailable("BookImporter not configured")
        }
        progress(0.0)
        let zipData = try await fetchBackupZIP(backupId: backupId)
        progress(0.10)

        let manifest: [BackupLibraryEntry]
        do {
            manifest = try RemoteBookCatalog.loadEntries(fromBackupZIP: zipData)
        } catch RemoteBookCatalogError.manifestMissing {
            throw BackupError.archiveCorrupted(
                "backup has no library-manifest.json — restore selectively requires a feature-#46+ backup"
            )
        } catch let error as RemoteBookCatalogError {
            throw BackupError.archiveCorrupted("manifest decode failed: \(error)")
        }
        progress(0.15)

        let materializer = BookFileMaterializer(
            blobStore: blobStore,
            importer: importer,
            tempDirectory: materializeTempDirectory,
            resolveSandboxURL: sandboxResolver
        )

        let coordinator = SelectiveRestoreCoordinator(
            materializer: materializer,
            persistence: persistence,
            dataRestorer: dataRestorer
        )

        let sections = Self.extractMetadataSections(from: zipData)

        let summary = try await coordinator.restoreSelectively(
            manifest: manifest,
            selectedKeys: selectedKeys,
            metadataSections: sections,
            progress: { fraction in
                // 0.15..1.0 reserved for coordinator (preplant +
                // materialize + metadata).
                progress(0.15 + fraction * 0.85)
            }
        )

        // Surface partial materialize failures the same way restore-all
        // does so the BackupViewModel UX is uniform.
        let failedTitles = summary.materialized
            .filter { !$0.isSuccess }
            .map { $0.entry.title ?? $0.entry.fingerprintKey }
        if !failedTitles.isEmpty {
            throw BackupError.restorePartiallyFailed(
                "books not materialized: \(failedTitles.joined(separator: ", "))"
            )
        }
        return summary
    }

    /// Cache-aware ZIP fetch shared by `loadManifest` and `restoreSelectively`.
    private func fetchBackupZIP(backupId: UUID) async throws -> Data {
        let remotePath: String
        if let cached = metadataCache[backupId] {
            remotePath = cached.remotePath
        } else {
            _ = try await listBackups()
            guard let cached = metadataCache[backupId] else {
                throw BackupError.backupNotFound(backupId)
            }
            remotePath = cached.remotePath
        }
        do {
            return try await transport.download(fromPath: remotePath)
        } catch let error as WebDAVError {
            if case .notFound = error {
                throw BackupError.backupNotFound(backupId)
            }
            throw BackupError.storageUnavailable("Download failed: \(error)")
        }
    }

    /// Pulls each metadata section out of the ZIP into a
    /// `SelectiveRestoreMetadataSections` value the coordinator
    /// consumes. Missing sections are nil and skipped.
    private static func extractMetadataSections(from zipData: Data) -> SelectiveRestoreMetadataSections {
        func read(_ name: String) -> Data? {
            try? ZIPWriter.extractEntry(named: name, from: zipData)
        }
        return SelectiveRestoreMetadataSections(
            annotations: read("annotations.json"),
            positions: read("positions.json"),
            settings: read("settings.json"),
            collections: read("collections.json"),
            bookSources: read("book-sources.json"),
            perBookSettings: read("per-book-settings.json"),
            replacementRules: read("replacement-rules.json")
        )
    }

    func listBackups() async throws -> [BackupMetadata] {
        let entries: [WebDAVEntry]
        do {
            entries = try await transport.listDirectory(path: basePath + "/")
        } catch let error as WebDAVError {
            if case .notFound = error {
                return [] // Directory doesn't exist yet — no backups
            }
            throw BackupError.storageUnavailable(
                "Failed to list backups: \(error)"
            )
        }

        // Filter to .vreader.zip files
        let zipEntries = entries.filter {
            !$0.isDirectory && $0.href.hasSuffix(".vreader.zip")
        }

        // Download and parse metadata from each backup
        var results: [BackupMetadata] = []
        for entry in zipEntries {
            let path = extractRelativePath(from: entry.href)
            do {
                let zipData = try await transport.download(fromPath: path)
                let metadataData = try ZIPWriter.extractEntry(
                    named: "metadata.json", from: zipData
                )
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let metadata = try decoder.decode(BackupMetadata.self, from: metadataData)
                results.append(metadata)
                metadataCache[metadata.id] = (metadata, path)
            } catch {
                // Skip corrupted backups
                continue
            }
        }

        // Sort newest first
        results.sort { $0.createdAt > $1.createdAt }
        return results
    }

    func deleteBackup(id: UUID) async throws {
        // Find the remote path
        let remotePath: String
        if let cached = metadataCache[id] {
            remotePath = cached.remotePath
        } else {
            _ = try await listBackups()
            guard let cached = metadataCache[id] else {
                throw BackupError.backupNotFound(id)
            }
            remotePath = cached.remotePath
        }

        do {
            try await transport.delete(path: remotePath)
        } catch let error as WebDAVError {
            if case .notFound = error {
                throw BackupError.backupNotFound(id)
            }
            throw BackupError.storageUnavailable(
                "Failed to delete backup: \(error)"
            )
        }

        metadataCache.removeValue(forKey: id)
    }

    // MARK: - Connection Test

    /// Tests the connection to the WebDAV server.
    /// Throws if connection or authentication fails.
    func testConnection() async throws {
        try await transport.testConnection()
    }

    // MARK: - Private Helpers

    /// Returns each ancestor directory that should be MKCOL'd, deepest last.
    /// e.g. `"VReader/backups"` → `["VReader", "VReader/backups"]`.
    private func nestedAncestors(of path: String) -> [String] {
        var components: [String] = []
        var accumulator: [String] = []
        for piece in path.split(separator: "/") where !piece.isEmpty {
            accumulator.append(String(piece))
            components.append(accumulator.joined(separator: "/"))
        }
        return components
    }

    /// Creates a remote path for a backup file.
    private func makeRemotePath(id: UUID, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate]
        let timestamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        let shortId = id.uuidString.prefix(8).lowercased()
        return "\(basePath)/\(timestamp)_\(shortId).vreader.zip"
    }

    /// Extracts a relative path from a full href.
    /// Handles various server path formats.
    private func extractRelativePath(from href: String) -> String {
        // If href is already a relative path starting with basePath, use it directly
        if href.hasPrefix(basePath) {
            return href
        }
        // Otherwise, find the basePath portion within the href
        if let range = href.range(of: basePath) {
            return String(href[range.lowerBound...])
        }
        // Fallback: try to extract just the filename
        let components = href.components(separatedBy: "/")
        if let filename = components.last, filename.hasSuffix(".vreader.zip") {
            return "\(basePath)/\(filename)"
        }
        return href
    }
}
