// Purpose: BackupProvider conformance for WebDAV storage backends.
// Creates ZIP backups of app data and uploads/downloads via WebDAVTransport.
// Restore delegates to BackupDataRestoring protocol for persistence-layer writes.
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

    /// In-memory cache of known backup metadata, keyed by ID.
    private var metadataCache: [UUID: (metadata: BackupMetadata, remotePath: String)] = [:]

    init(
        transport: WebDAVTransport,
        dataCollector: BackupDataCollecting,
        dataRestorer: BackupDataRestoring,
        deviceName: String,
        appVersion: String
    ) {
        self.transport = transport
        self.dataCollector = dataCollector
        self.dataRestorer = dataRestorer
        self.deviceName = deviceName
        self.appVersion = appVersion
    }

    // MARK: - BackupProvider

    func backup(progress: @Sendable (Double) -> Void) async throws -> BackupMetadata {
        progress(0.0)

        // Phase 1: Collect data (0.0 → 0.4)
        let collected: [(String, Data)]
        let bookCount: Int
        do {
            let a = try await dataCollector.collectAnnotations(); progress(0.06)
            let p = try await dataCollector.collectPositions(); progress(0.12)
            let s = try await dataCollector.collectSettings(); progress(0.18)
            let c = try await dataCollector.collectCollections(); progress(0.24)
            let bs = try await dataCollector.collectBookSources(); progress(0.30)
            let pbs = try await dataCollector.collectPerBookSettings(); progress(0.35)
            let rr = try await dataCollector.collectReplacementRules(); progress(0.38)
            bookCount = await dataCollector.getBookCount(); progress(0.40)
            collected = [
                ("annotations.json", a), ("positions.json", p), ("settings.json", s),
                ("collections.json", c), ("book-sources.json", bs), ("per-book-settings.json", pbs),
                ("replacement-rules.json", rr),
            ]
        } catch {
            throw BackupError.archiveCreationFailed("Failed to collect data: \(error.localizedDescription)")
        }

        // Phase 2: Create metadata and ZIP (0.4 → 0.5)
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
        progress(0.50)

        // Phase 3: Upload to WebDAV (0.5 → 1.0)
        let remotePath = makeRemotePath(id: backupId, date: now)
        do {
            // Create each parent collection in turn — WebDAV MKCOL won't
            // create intermediate directories on most servers, so a nested
            // basePath like "VReader/backups" needs two MKCOLs.
            for ancestor in nestedAncestors(of: basePath) {
                try await transport.createDirectory(path: ancestor)
            }
            progress(0.55)
            try await transport.upload(data: zipData, toPath: remotePath); progress(0.95)
        } catch let error as WebDAVError {
            throw BackupError.storageUnavailable("WebDAV upload failed: \(error)")
        } catch {
            throw BackupError.storageUnavailable("Upload failed: \(error.localizedDescription)")
        }

        metadataCache[backupId] = (metadata, remotePath)
        progress(1.0)
        return metadata
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

        // Apply restored data to local database via BackupDataRestoring delegate.
        // Each file is optional — missing entries are silently skipped (forward compatibility).
        // Each tuple: (zip filename, user-facing section label, restore fn).
        // The label is what shows up in BackupError.restorePartiallyFailed —
        // it must not leak internal filenames.
        let restoreFiles: [(filename: String, label: String, fn: (Data) async throws -> Void)] = [
            ("annotations.json", "annotations", dataRestorer.restoreAnnotations),
            ("positions.json", "reading positions", dataRestorer.restorePositions),
            ("settings.json", "settings", dataRestorer.restoreSettings),
            ("collections.json", "collections", dataRestorer.restoreCollections),
            ("book-sources.json", "book sources", dataRestorer.restoreBookSources),
            ("per-book-settings.json", "per-book settings", dataRestorer.restorePerBookSettings),
            ("replacement-rules.json", "replacement rules", dataRestorer.restoreReplacementRules),
        ]

        let totalFiles = Double(restoreFiles.count)
        var failedLabels: [String] = []
        for (index, item) in restoreFiles.enumerated() {
            if let entryData = try? ZIPWriter.extractEntry(named: item.filename, from: zipData) {
                do {
                    try await item.fn(entryData)
                } catch {
                    // Per-section restore errors don't abort the loop —
                    // restoring the remaining sections is more useful than
                    // bailing out and leaving the user with a half-applied
                    // archive that's hard to reason about.
                    failedLabels.append(item.label)
                }
            }
            progress(0.55 + 0.40 * Double(index + 1) / totalFiles)
        }

        progress(1.0)
        if !failedLabels.isEmpty {
            throw BackupError.restorePartiallyFailed(failedLabels.joined(separator: ", "))
        }
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
