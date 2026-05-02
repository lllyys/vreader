// Purpose: Contract tests for the BackupProvider protocol.
// Verifies that any conforming type (starting with MockBackupProvider)
// satisfies the behavioral contract: backup, restore, list, delete, progress, cancellation.
//
// @coordinates-with: BackupProvider.swift, MockBackupProvider.swift

import Testing
import Foundation
@testable import vreader

@Suite("BackupProvider Contract")
struct BackupProviderContractTests {

    // MARK: - Helpers

    private func makeMock() -> MockBackupProvider {
        MockBackupProvider()
    }

    // MARK: - backup

    @Test func backup_producesMetadata_withAllFields() async throws {
        let mock = makeMock()
        let metadata = try await mock.backup { _ in }

        #expect(metadata.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(!metadata.deviceName.isEmpty)
        #expect(!metadata.appVersion.isEmpty)
        #expect(metadata.bookCount >= 0)
        #expect(metadata.totalSizeBytes >= 0)
        // createdAt should be recent (within last 5 seconds)
        #expect(abs(metadata.createdAt.timeIntervalSinceNow) < 5)
    }

    @Test func backup_progressReports_0to1() async throws {
        let mock = makeMock()
        let collector = ProgressCollector()

        _ = try await mock.backup { value in
            collector.record(value)
        }

        // Give progress callbacks time to be recorded
        try await Task.sleep(for: .milliseconds(50))

        let values = collector.values
        #expect(!values.isEmpty, "Expected at least one progress report")
        // Values should be in [0, 1]
        for v in values {
            #expect(v >= 0.0 && v <= 1.0, "Progress \(v) out of range [0, 1]")
        }
        // Should end at 1.0
        #expect(values.last == 1.0, "Final progress should be 1.0")
        // Values should be non-decreasing
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1], "Progress should be non-decreasing")
        }
    }

    @Test func backup_multipleBackups_produceDifferentIDs() async throws {
        let mock = makeMock()
        let m1 = try await mock.backup { _ in }
        let m2 = try await mock.backup { _ in }

        #expect(m1.id != m2.id, "Each backup should have a unique ID")
    }

    // MARK: - restore

    @Test func restore_fromValidId_succeeds() async throws {
        let mock = makeMock()
        let metadata = try await mock.backup { _ in }

        // Should not throw
        try await mock.restore(backupId: metadata.id) { _ in }
    }

    @Test func restore_fromInvalidId_throwsError() async throws {
        let mock = makeMock()
        let bogusId = UUID()

        do {
            try await mock.restore(backupId: bogusId) { _ in }
            Issue.record("Expected backupNotFound error")
        } catch let error as BackupError {
            guard case .backupNotFound(let id) = error else {
                Issue.record("Expected backupNotFound, got \(error)")
                return
            }
            #expect(id == bogusId)
        }
    }

    @Test func restore_progressReports_0to1() async throws {
        let mock = makeMock()
        let metadata = try await mock.backup { _ in }
        let collector = ProgressCollector()

        try await mock.restore(backupId: metadata.id) { value in
            collector.record(value)
        }

        try await Task.sleep(for: .milliseconds(50))

        let values = collector.values
        #expect(!values.isEmpty, "Expected at least one progress report during restore")
        #expect(values.last == 1.0, "Final restore progress should be 1.0")
    }

    // MARK: - listBackups

    @Test func listBackups_returnsEmpty_whenNoneExist() async throws {
        let mock = makeMock()
        let list = try await mock.listBackups()

        #expect(list.isEmpty)
    }

    @Test func listBackups_returnsSortedByDate() async throws {
        let mock = makeMock()

        // Create backups with slight time gaps
        _ = try await mock.backup { _ in }
        try await Task.sleep(for: .milliseconds(10))
        _ = try await mock.backup { _ in }
        try await Task.sleep(for: .milliseconds(10))
        _ = try await mock.backup { _ in }

        let list = try await mock.listBackups()
        #expect(list.count == 3)

        // Newest first
        for i in 1..<list.count {
            #expect(
                list[i - 1].createdAt >= list[i].createdAt,
                "Backups should be sorted newest first"
            )
        }
    }

    @Test func listBackups_reflectsDeletedBackups() async throws {
        let mock = makeMock()
        let m1 = try await mock.backup { _ in }
        _ = try await mock.backup { _ in }

        #expect(try await mock.listBackups().count == 2)

        try await mock.deleteBackup(id: m1.id)

        #expect(try await mock.listBackups().count == 1)
    }

    // MARK: - deleteBackup

    @Test func deleteBackup_existingId_succeeds() async throws {
        let mock = makeMock()
        let metadata = try await mock.backup { _ in }

        try await mock.deleteBackup(id: metadata.id)

        let list = try await mock.listBackups()
        #expect(!list.contains(where: { $0.id == metadata.id }))
    }

    @Test func deleteBackup_unknownId_throwsNotFound() async throws {
        let mock = makeMock()
        let bogusId = UUID()

        do {
            try await mock.deleteBackup(id: bogusId)
            Issue.record("Expected backupNotFound error")
        } catch let error as BackupError {
            guard case .backupNotFound(let id) = error else {
                Issue.record("Expected backupNotFound, got \(error)")
                return
            }
            #expect(id == bogusId)
        }
    }

    // MARK: - Cancellation

    @Test func cancellation_throwsCancelledError() async throws {
        let mock = makeMock()
        mock.simulateCancellation = true

        do {
            _ = try await mock.backup { _ in }
            Issue.record("Expected cancelled error")
        } catch let error as BackupError {
            #expect(error == .cancelled)
        }
    }

    // MARK: - BackupMetadata Codable

    @Test func metadata_codable_roundTrip() throws {
        let original = BackupMetadata(
            id: UUID(),
            createdAt: Date(),
            deviceName: "iPhone 17 Pro",
            appVersion: "0.1.0",
            bookCount: 42,
            totalSizeBytes: 1_073_741_824 // 1 GB
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupMetadata.self, from: data)

        #expect(decoded.id == original.id)
        #expect(abs(decoded.createdAt.timeIntervalSince(original.createdAt)) < 0.001)
        #expect(decoded.deviceName == original.deviceName)
        #expect(decoded.appVersion == original.appVersion)
        #expect(decoded.bookCount == original.bookCount)
        #expect(decoded.totalSizeBytes == original.totalSizeBytes)
    }

    @Test func metadata_codable_zeroBooks() throws {
        let original = BackupMetadata(
            id: UUID(),
            createdAt: Date(),
            deviceName: "Test",
            appVersion: "0.1.0",
            bookCount: 0,
            totalSizeBytes: 0
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupMetadata.self, from: data)

        #expect(decoded.bookCount == 0)
        #expect(decoded.totalSizeBytes == 0)
    }

    @Test func metadata_codable_largeSize() throws {
        let original = BackupMetadata(
            id: UUID(),
            createdAt: Date(),
            deviceName: "iPad",
            appVersion: "1.0.0",
            bookCount: 10000,
            totalSizeBytes: Int64.max
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupMetadata.self, from: data)

        #expect(decoded.totalSizeBytes == Int64.max)
        #expect(decoded.bookCount == 10000)
    }

    @Test func metadata_identifiable_usesId() {
        let uuid = UUID()
        let m = BackupMetadata(
            id: uuid,
            createdAt: Date(),
            deviceName: "Test",
            appVersion: "0.1.0",
            bookCount: 0,
            totalSizeBytes: 0
        )

        // Identifiable conformance: id property is the UUID
        #expect(m.id == uuid)
    }
}

// MARK: - Test Helpers

/// Lock-protected progress value collector for race-free *synchronous* capture
/// from `@Sendable` callbacks. Was an actor previously, but actor-await
/// scheduling under parallel test execution made the ordering check flaky.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func record(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }
}
