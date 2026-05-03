// Purpose: Tests for WebDAVProvider — BackupProvider conformance over WebDAV.
// Uses a mock WebDAVClient to test backup/restore/list/delete operations
// without hitting a real server.
//
// @coordinates-with: WebDAVProvider.swift, WebDAVClient.swift, BackupProvider.swift

import Testing
import Foundation
@testable import vreader

// MARK: - MockWebDAVTransport

/// Mock transport layer that replaces real HTTP calls.
/// Stores uploaded files in memory and supports PROPFIND listing.
final class MockWebDAVTransport: WebDAVTransport, @unchecked Sendable {
    /// Files stored on the mock server, keyed by path.
    var files: [String: Data] = [:]
    /// Whether the next call should fail with an auth error.
    var simulateAuthFailure = false
    /// Whether the next call should fail with a connection error.
    var simulateConnectionFailure = false
    /// Track method calls for verification.
    var methodCalls: [(method: String, path: String)] = []

    func upload(data: Data, toPath path: String) async throws {
        methodCalls.append(("PUT", path))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        if simulateConnectionFailure { throw WebDAVError.connectionFailed("mock") }
        files[path] = data
    }

    func download(fromPath path: String) async throws -> Data {
        methodCalls.append(("GET", path))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        if simulateConnectionFailure { throw WebDAVError.connectionFailed("mock") }
        guard let data = files[path] else {
            throw WebDAVError.notFound(path)
        }
        return data
    }

    func delete(path: String) async throws {
        methodCalls.append(("DELETE", path))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        guard files.removeValue(forKey: path) != nil else {
            throw WebDAVError.notFound(path)
        }
    }

    func listDirectory(path: String) async throws -> [WebDAVEntry] {
        methodCalls.append(("PROPFIND", path))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        if simulateConnectionFailure { throw WebDAVError.connectionFailed("mock") }
        return files.keys
            .filter { $0.hasPrefix(path) && $0 != path }
            .map { key in
                WebDAVEntry(
                    href: key,
                    contentLength: Int64(files[key]?.count ?? 0),
                    lastModified: nil,
                    isDirectory: false
                )
            }
            .sorted { $0.href < $1.href }
    }

    func createDirectory(path: String) async throws {
        methodCalls.append(("MKCOL", path))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        // Directories are just paths ending with /
        files[path] = Data()
    }

    func testConnection() async throws {
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        if simulateConnectionFailure { throw WebDAVError.connectionFailed("mock") }
    }

    // MARK: Feature #46 (WI-3) — atomic blob publication primitives

    func move(fromPath: String, toPath: String) async throws {
        methodCalls.append(("MOVE", "\(fromPath) -> \(toPath)"))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        if simulateConnectionFailure { throw WebDAVError.connectionFailed("mock") }
        if simulateMoveNotImplemented { throw WebDAVError.httpError(501) }
        guard let data = files.removeValue(forKey: fromPath) else {
            throw WebDAVError.notFound(fromPath)
        }
        // Overwrite: F semantics — fail if destination already exists.
        guard files[toPath] == nil else {
            throw WebDAVError.httpError(412)
        }
        files[toPath] = data
    }

    func existsWithSize(at path: String) async throws -> Int64? {
        methodCalls.append(("PROPFIND-exists", path))
        if simulateAuthFailure { throw WebDAVError.authenticationFailed }
        if simulateConnectionFailure { throw WebDAVError.connectionFailed("mock") }
        if let override = existsWithSizeOverride { return override(path) }
        guard let data = files[path] else { return nil }
        return Int64(data.count)
    }

    /// Per-test override for existsWithSize — lets blob-store tests simulate
    /// truncated uploads (PUT succeeds but server reports a different size).
    var existsWithSizeOverride: ((String) -> Int64?)?

    /// When true, MOVE throws httpError(501) — simulates a server that
    /// doesn't implement MOVE.
    var simulateMoveNotImplemented = false
}

// MARK: - Mock Data Collector

/// Collects backup data for WebDAVProvider without needing a real database.
final class MockBackupDataCollector: BackupDataCollecting, @unchecked Sendable {
    var annotations: [String: Any] = [:]
    var positions: [String: Any] = [:]
    var settings: [String: Any] = [:]
    var collections: [String: Any] = [:]
    var bookSources: [String: Any] = [:]
    var perBookSettings: [String: Any] = [:]

    var bookCount: Int = 3

    func collectAnnotations() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["highlights": [], "bookmarks": []])
    }

    func collectPositions() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["positions": []])
    }

    func collectSettings() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["theme": "light"])
    }

    func collectCollections() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["collections": []])
    }

    func collectBookSources() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sources": []])
    }

    func collectPerBookSettings() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["perBook": []])
    }

    func collectReplacementRules() async throws -> Data {
        try JSONSerialization.data(withJSONObject: ["rules": []])
    }

    func getBookCount() async -> Int {
        bookCount
    }
}

// MARK: - Mock Data Restorer

/// Records which restore methods were called with what data.
final class MockBackupDataRestorer: BackupDataRestoring, @unchecked Sendable {
    var restoredAnnotations: Data?
    var restoredPositions: Data?
    var restoredSettings: Data?
    var restoredCollections: Data?
    var restoredBookSources: Data?
    var restoredPerBookSettings: Data?
    var restoredReplacementRules: Data?

    /// Count of restore calls for verification.
    var restoreCallCount: Int {
        [restoredAnnotations, restoredPositions, restoredSettings,
         restoredCollections, restoredBookSources, restoredPerBookSettings,
         restoredReplacementRules].compactMap({ $0 }).count
    }

    func restoreAnnotations(from data: Data) async throws {
        restoredAnnotations = data
    }

    func restorePositions(from data: Data) async throws {
        restoredPositions = data
    }

    func restoreSettings(from data: Data) async throws {
        restoredSettings = data
    }

    func restoreCollections(from data: Data) async throws {
        restoredCollections = data
    }

    func restoreBookSources(from data: Data) async throws {
        restoredBookSources = data
    }

    func restorePerBookSettings(from data: Data) async throws {
        restoredPerBookSettings = data
    }

    func restoreReplacementRules(from data: Data) async throws {
        restoredReplacementRules = data
    }
}

// MARK: - WebDAVProvider Tests

@Suite("WebDAVProvider")
struct WebDAVProviderTests {

    // MARK: - Helpers

    private func makeProvider(
        transport: MockWebDAVTransport? = nil,
        dataCollector: MockBackupDataCollector? = nil,
        dataRestorer: MockBackupDataRestorer? = nil
    ) -> (WebDAVProvider, MockWebDAVTransport, MockBackupDataCollector, MockBackupDataRestorer) {
        let t = transport ?? MockWebDAVTransport()
        let dc = dataCollector ?? MockBackupDataCollector()
        let dr = dataRestorer ?? MockBackupDataRestorer()
        let provider = WebDAVProvider(
            transport: t,
            dataCollector: dc,
            dataRestorer: dr,
            deviceName: "Test iPhone",
            appVersion: "1.0.0"
        )
        return (provider, t, dc, dr)
    }

    // MARK: - Backup

    @Test func backup_createsZIPArchive() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        // Should have uploaded exactly one file
        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        #expect(uploadedPaths.count == 1)
    }

    @Test func backup_archiveStoredInCorrectPath() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        #expect(uploadedPaths.count == 1)
        let path = uploadedPaths.first!
        #expect(path.hasPrefix("VReader/backups/"))
    }

    @Test func backup_includesMetadata() async throws {
        let (provider, transport, _, _) = makeProvider()

        let metadata = try await provider.backup { _ in }

        #expect(metadata.deviceName == "Test iPhone")
        #expect(metadata.appVersion == "1.0.0")
        #expect(metadata.bookCount == 3)
        #expect(metadata.totalSizeBytes > 0)
    }

    @Test func backup_metadataIncludedInArchive() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        // The uploaded ZIP should contain metadata.json
        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("metadata.json"))
    }

    @Test func backup_includesAnnotations() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("annotations.json"))
    }

    @Test func backup_includesPositions() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("positions.json"))
    }

    @Test func backup_includesSettings() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("settings.json"))
    }

    @Test func backup_includesCollections() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("collections.json"))
    }

    @Test func backup_includesBookSources() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("book-sources.json"))
    }

    @Test func backup_includesPerBookSettings() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("per-book-settings.json"))
    }

    @Test func backup_progressReported() async throws {
        let (provider, _, _, _) = makeProvider()
        let collector = BackupProgressCollector()

        _ = try await provider.backup { value in
            Task { await collector.record(value) }
        }

        // Give progress callbacks time to be recorded
        try await Task.sleep(for: .milliseconds(100))

        let values = await collector.values
        #expect(!values.isEmpty, "Expected at least one progress report")
        // All values should be in [0, 1]
        for v in values {
            #expect(v >= 0.0 && v <= 1.0, "Progress \(v) out of range")
        }
        // Should contain 0.0 and 1.0
        #expect(values.contains(0.0), "Should report 0.0 start")
        #expect(values.contains(1.0), "Should report 1.0 completion")
    }

    @Test func backup_multipleBackups_uniqueIDs() async throws {
        let (provider, _, _, _) = makeProvider()

        let m1 = try await provider.backup { _ in }
        let m2 = try await provider.backup { _ in }

        #expect(m1.id != m2.id)
    }

    @Test func backup_authFailure_throwsStorageError() async throws {
        let transport = MockWebDAVTransport()
        transport.simulateAuthFailure = true
        let (provider, _, _, _) = makeProvider(transport: transport)

        do {
            _ = try await provider.backup { _ in }
            Issue.record("Expected error")
        } catch let error as BackupError {
            guard case .storageUnavailable = error else {
                Issue.record("Expected storageUnavailable, got \(error)")
                return
            }
        }
    }

    // MARK: - Restore

    @Test func restore_extractsZIP() async throws {
        let (provider, _, _, _) = makeProvider()

        let metadata = try await provider.backup { _ in }
        // Should not throw — proves ZIP was stored and can be retrieved
        try await provider.restore(backupId: metadata.id) { _ in }
    }

    @Test func restore_backupNotFound_error() async throws {
        let (provider, _, _, _) = makeProvider()
        let bogusId = UUID()

        do {
            try await provider.restore(backupId: bogusId) { _ in }
            Issue.record("Expected backupNotFound error")
        } catch let error as BackupError {
            guard case .backupNotFound(let id) = error else {
                Issue.record("Expected backupNotFound, got \(error)")
                return
            }
            #expect(id == bogusId)
        }
    }

    @Test func restore_progressReported() async throws {
        let (provider, _, _, _) = makeProvider()
        let metadata = try await provider.backup { _ in }
        let collector = BackupProgressCollector()

        try await provider.restore(backupId: metadata.id) { value in
            Task { await collector.record(value) }
        }

        try await Task.sleep(for: .milliseconds(100))
        let values = await collector.values
        #expect(!values.isEmpty)
        #expect(values.contains(1.0), "Should report 1.0 completion")
    }

    @Test func restore_delegatesToRestorer_annotations() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredAnnotations != nil, "Annotations should be restored")
    }

    @Test func restore_delegatesToRestorer_positions() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredPositions != nil, "Positions should be restored")
    }

    @Test func restore_delegatesToRestorer_settings() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredSettings != nil, "Settings should be restored")
    }

    @Test func restore_delegatesToRestorer_collections() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredCollections != nil, "Collections should be restored")
    }

    @Test func restore_delegatesToRestorer_bookSources() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredBookSources != nil, "Book sources should be restored")
    }

    @Test func restore_delegatesToRestorer_perBookSettings() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredPerBookSettings != nil, "Per-book settings should be restored")
    }

    @Test func restore_delegatesToRestorer_replacementRules() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoredReplacementRules != nil, "Replacement rules should be restored")
    }

    @Test func restore_allFilesRestored() async throws {
        let restorer = MockBackupDataRestorer()
        let (provider, _, _, _) = makeProvider(dataRestorer: restorer)
        let metadata = try await provider.backup { _ in }

        try await provider.restore(backupId: metadata.id) { _ in }

        #expect(restorer.restoreCallCount == 7, "All 7 data types should be restored")
    }

    // MARK: - Backup Includes Replacement Rules (Issue 2)

    @Test func backup_includesReplacementRules() async throws {
        let (provider, transport, _, _) = makeProvider()

        _ = try await provider.backup { _ in }

        let uploadedPaths = transport.files.keys.filter { $0.hasSuffix(".vreader.zip") }
        let zipData = transport.files[uploadedPaths.first!]!
        let entries = try ZIPWriter.listEntryNames(in: zipData)
        #expect(entries.contains("replacement-rules.json"))
    }

    // MARK: - List Backups

    @Test func listBackups_sortedNewestFirst() async throws {
        let (provider, _, _, _) = makeProvider()

        _ = try await provider.backup { _ in }
        try await Task.sleep(for: .milliseconds(10))
        _ = try await provider.backup { _ in }
        try await Task.sleep(for: .milliseconds(10))
        _ = try await provider.backup { _ in }

        let list = try await provider.listBackups()
        #expect(list.count == 3)
        for i in 1..<list.count {
            #expect(list[i - 1].createdAt >= list[i].createdAt)
        }
    }

    @Test func listBackups_emptyServer_returnsEmpty() async throws {
        let (provider, _, _, _) = makeProvider()

        let list = try await provider.listBackups()
        #expect(list.isEmpty)
    }

    @Test func listBackups_afterDelete_excludesDeleted() async throws {
        let (provider, _, _, _) = makeProvider()

        let m1 = try await provider.backup { _ in }
        _ = try await provider.backup { _ in }

        try await provider.deleteBackup(id: m1.id)

        let list = try await provider.listBackups()
        #expect(list.count == 1)
        #expect(!list.contains(where: { $0.id == m1.id }))
    }

    // MARK: - Delete Backup

    @Test func deleteBackup_removesFromServer() async throws {
        let (provider, transport, _, _) = makeProvider()

        let metadata = try await provider.backup { _ in }
        let fileCountBefore = transport.files.count

        try await provider.deleteBackup(id: metadata.id)

        #expect(transport.files.count < fileCountBefore)
    }

    @Test func deleteBackup_unknownId_throwsNotFound() async throws {
        let (provider, _, _, _) = makeProvider()
        let bogusId = UUID()

        do {
            try await provider.deleteBackup(id: bogusId)
            Issue.record("Expected backupNotFound error")
        } catch let error as BackupError {
            guard case .backupNotFound(let id) = error else {
                Issue.record("Expected backupNotFound, got \(error)")
                return
            }
            #expect(id == bogusId)
        }
    }

    // MARK: - Connection Test

    @Test func connectionTest_success() async throws {
        let transport = MockWebDAVTransport()
        let (provider, _, _, _) = makeProvider(transport: transport)

        // Should not throw
        try await provider.testConnection()
    }

    @Test func connectionTest_authFailure_throwsError() async throws {
        let transport = MockWebDAVTransport()
        transport.simulateAuthFailure = true
        let (provider, _, _, _) = makeProvider(transport: transport)

        do {
            try await provider.testConnection()
            Issue.record("Expected auth error")
        } catch {
            // Expected
        }
    }

    @Test func connectionTest_connectionFailure_throwsError() async throws {
        let transport = MockWebDAVTransport()
        transport.simulateConnectionFailure = true
        let (provider, _, _, _) = makeProvider(transport: transport)

        do {
            try await provider.testConnection()
            Issue.record("Expected connection error")
        } catch {
            // Expected
        }
    }
}

// MARK: - ZIPWriter Tests

@Suite("ZIPWriter")
struct ZIPWriterTests {

    @Test func createArchive_withFiles_producesValidZIP() throws {
        let entries: [ZIPWriter.Entry] = [
            ZIPWriter.Entry(name: "test.txt", data: Data("hello".utf8)),
            ZIPWriter.Entry(name: "nested/file.json", data: Data("{\"key\":1}".utf8)),
        ]
        let zipData = try ZIPWriter.createArchive(entries: entries)
        #expect(zipData.count > 0)
        // ZIP magic bytes: PK\x03\x04
        #expect(zipData[0] == 0x50)
        #expect(zipData[1] == 0x4B)
    }

    @Test func createArchive_emptyEntries_producesValidZIP() throws {
        let zipData = try ZIPWriter.createArchive(entries: [])
        #expect(zipData.count > 0)
        // Even empty ZIP has an EOCD record
    }

    @Test func listEntryNames_roundTrips() throws {
        let entries: [ZIPWriter.Entry] = [
            ZIPWriter.Entry(name: "metadata.json", data: Data("{\"v\":1}".utf8)),
            ZIPWriter.Entry(name: "annotations.json", data: Data("[]".utf8)),
        ]
        let zipData = try ZIPWriter.createArchive(entries: entries)
        let names = try ZIPWriter.listEntryNames(in: zipData)
        #expect(names.contains("metadata.json"))
        #expect(names.contains("annotations.json"))
        #expect(names.count == 2)
    }

    @Test func createArchive_largeData_stores() throws {
        let largeData = Data(repeating: 0x42, count: 100_000)
        let entries = [ZIPWriter.Entry(name: "big.bin", data: largeData)]
        let zipData = try ZIPWriter.createArchive(entries: entries)
        #expect(zipData.count > 0)
        let names = try ZIPWriter.listEntryNames(in: zipData)
        #expect(names.contains("big.bin"))
    }

    @Test func createArchive_unicodeFilenames_supported() throws {
        let entries = [
            ZIPWriter.Entry(name: "中文.json", data: Data("{}".utf8)),
            ZIPWriter.Entry(name: "émojis-🎉.txt", data: Data("test".utf8)),
        ]
        let zipData = try ZIPWriter.createArchive(entries: entries)
        let names = try ZIPWriter.listEntryNames(in: zipData)
        #expect(names.contains("中文.json"))
        #expect(names.contains("émojis-🎉.txt"))
    }

    @Test func extractEntry_roundTripsContent() throws {
        let content = Data("hello world 你好世界".utf8)
        let entries = [ZIPWriter.Entry(name: "test.txt", data: content)]
        let zipData = try ZIPWriter.createArchive(entries: entries)
        let extracted = try ZIPWriter.extractEntry(named: "test.txt", from: zipData)
        #expect(extracted == content)
    }

    @Test func extractEntry_notFound_throws() throws {
        let zipData = try ZIPWriter.createArchive(entries: [
            ZIPWriter.Entry(name: "a.txt", data: Data("a".utf8)),
        ])
        #expect(throws: (any Error).self) {
            try ZIPWriter.extractEntry(named: "missing.txt", from: zipData)
        }
    }
}

// MARK: - Test Helpers

private actor BackupProgressCollector {
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        values.append(value)
    }
}
