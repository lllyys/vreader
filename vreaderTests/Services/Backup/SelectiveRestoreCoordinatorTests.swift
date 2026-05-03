// Purpose: Tests for SelectiveRestoreCoordinator — the 3-phase
// orchestrator (preplant remoteOnly → materialize selected → restore
// metadata) for the picker-driven restore flow. Feature #47 WI-4b.

import Testing
import Foundation
import CryptoKit
@testable import vreader

@Suite("SelectiveRestoreCoordinator — feature #47 WI-4b")
struct SelectiveRestoreCoordinatorTests {

    // MARK: - Mocks

    actor StubBlobReader: BackupBlobReading {
        var blobs: [String: Data] = [:]
        func setBlob(_ data: Data, at path: String) { blobs[path] = data }
        func existsWithSize(at path: String) async throws -> Int64? {
            blobs[path].map { Int64($0.count) }
        }
        func download(from path: String) async throws -> Data {
            guard let d = blobs[path] else {
                throw BackupBlobStoreError.underlying("not found: \(path)")
            }
            return d
        }
    }

    actor RecordingDataRestorer: BackupDataRestoring {
        private(set) var calls: [String] = []
        func restoreAnnotations(from data: Data) async throws { calls.append("annotations:\(data.count)") }
        func restorePositions(from data: Data) async throws { calls.append("positions:\(data.count)") }
        func restoreSettings(from data: Data) async throws { calls.append("settings:\(data.count)") }
        func restoreCollections(from data: Data) async throws { calls.append("collections:\(data.count)") }
        func restoreBookSources(from data: Data) async throws { calls.append("bookSources:\(data.count)") }
        func restorePerBookSettings(from data: Data) async throws { calls.append("perBookSettings:\(data.count)") }
        func restoreReplacementRules(from data: Data) async throws { calls.append("replacementRules:\(data.count)") }
        func recordedCalls() -> [String] { calls }
    }

    // MARK: - Helpers

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("selrestore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeEntry(
        title: String,
        bytes: Data
    ) -> BackupLibraryEntry {
        let sha = sha256Hex(bytes)
        return BackupLibraryEntry(
            fingerprintKey: "epub:\(sha):\(bytes.count)",
            format: "epub",
            sha256: sha,
            byteCount: Int64(bytes.count),
            originalExtension: "epub",
            title: title,
            author: "A",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: .epub, sha256: sha, byteCount: Int64(bytes.count))
        )
    }

    private static func makeEPUBBytes(seed: UInt8) -> Data {
        Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: seed, count: 1024)
    }

    /// Returns (coordinator, persistence, dataRestorer, blobReader).
    private static func makeRig() async throws -> (
        SelectiveRestoreCoordinator,
        PersistenceActor,
        RecordingDataRestorer,
        StubBlobReader
    ) {
        let blobReader = StubBlobReader()
        let persistence = try CollectionTestHelper.makePersistence()
        let sandbox = try makeTempDir()
        let temp = try makeTempDir()
        let importer = BookImporter(persistence: persistence, sandboxBooksDirectory: sandbox)
        let resolver: SandboxURLResolver = { fingerprintKey, ext in
            let safe = fingerprintKey.replacingOccurrences(of: ":", with: "_")
            return sandbox.appendingPathComponent(safe).appendingPathExtension(ext)
        }
        let materializer = BookFileMaterializer(
            blobStore: blobReader,
            importer: importer,
            tempDirectory: temp,
            resolveSandboxURL: resolver
        )
        let dataRestorer = RecordingDataRestorer()
        let coordinator = SelectiveRestoreCoordinator(
            materializer: materializer,
            persistence: persistence,
            dataRestorer: dataRestorer
        )
        return (coordinator, persistence, dataRestorer, blobReader)
    }

    // MARK: - Acceptance: 5-entry manifest, pick 2

    @Test func restoreSelectively_pick2of5_yields2localPlus3remoteOnly() async throws {
        let (coordinator, persistence, _, blobReader) = try await Self.makeRig()
        let entries = (0..<5).map { i in
            Self.makeEntry(title: "Book \(i)", bytes: Self.makeEPUBBytes(seed: UInt8(i)))
        }
        // Stage blobs so the materializer can fetch the selected ones.
        for entry in entries {
            await blobReader.setBlob(Self.makeEPUBBytes(seed: UInt8(entries.firstIndex(where: { $0.fingerprintKey == entry.fingerprintKey })!)), at: entry.blobPath)
        }

        let selected: Set<String> = [entries[1].fingerprintKey, entries[3].fingerprintKey]
        let summary = try await coordinator.restoreSelectively(
            manifest: entries,
            selectedKeys: selected,
            metadataSections: SelectiveRestoreMetadataSections(),
            progress: { _ in }
        )

        #expect(summary.localCount == 2)
        #expect(summary.remoteOnlyCount == 3)

        // Verify persistence shape: 2 .local, 3 .remoteOnly, total 5.
        let localKeys = try await persistence.fingerprintKeys(withFileState: .local)
        let remoteKeys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(localKeys.count == 2)
        #expect(Set(remoteKeys) == Set([entries[0], entries[2], entries[4]].map(\.fingerprintKey)))
    }

    // MARK: - Phase ordering / progress

    @Test func progress_movesMonotonically_through3Phases() async throws {
        let (coordinator, _, _, blobReader) = try await Self.makeRig()
        let entry = Self.makeEntry(title: "X", bytes: Self.makeEPUBBytes(seed: 1))
        await blobReader.setBlob(Self.makeEPUBBytes(seed: 1), at: entry.blobPath)

        actor Collector { var values: [Double] = []; func record(_ v: Double) { values.append(v) } }
        let collector = Collector()

        _ = try await coordinator.restoreSelectively(
            manifest: [entry],
            selectedKeys: [entry.fingerprintKey],
            metadataSections: SelectiveRestoreMetadataSections(),
            progress: { v in Task { await collector.record(v) } }
        )
        await Task.yield()
        await Task.yield()
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
        // Monotonic non-decreasing.
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }

    // MARK: - All-remoteOnly + all-selected edges

    @Test func restoreSelectively_emptySelection_allBecomeRemoteOnly() async throws {
        let (coordinator, persistence, _, _) = try await Self.makeRig()
        let entries = (0..<3).map { i in
            Self.makeEntry(title: "B\(i)", bytes: Self.makeEPUBBytes(seed: UInt8(i)))
        }
        let summary = try await coordinator.restoreSelectively(
            manifest: entries,
            selectedKeys: [],
            metadataSections: SelectiveRestoreMetadataSections(),
            progress: { _ in }
        )
        #expect(summary.localCount == 0)
        #expect(summary.remoteOnlyCount == 3)
        let remoteKeys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(Set(remoteKeys) == Set(entries.map(\.fingerprintKey)))
    }

    @Test func restoreSelectively_emptyManifest_succeedsAndRestoresMetadata() async throws {
        let (coordinator, persistence, dataRestorer, _) = try await Self.makeRig()
        let summary = try await coordinator.restoreSelectively(
            manifest: [],
            selectedKeys: [],
            metadataSections: SelectiveRestoreMetadataSections(
                positions: Data("{}".utf8)
            ),
            progress: { _ in }
        )
        #expect(summary.localCount == 0)
        #expect(summary.remoteOnlyCount == 0)
        let remote = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(remote.isEmpty)
        let calls = await dataRestorer.recordedCalls()
        #expect(calls.contains(where: { $0.hasPrefix("positions:") }))
    }

    // MARK: - Metadata restore phase

    @Test func metadataSections_eachPresentInvokesCorrespondingRestorer() async throws {
        let (coordinator, _, dataRestorer, _) = try await Self.makeRig()
        let sections = SelectiveRestoreMetadataSections(
            annotations: Data("a".utf8),
            positions: Data("p".utf8),
            settings: Data("s".utf8),
            collections: Data("c".utf8),
            bookSources: Data("bs".utf8),
            perBookSettings: Data("pbs".utf8),
            replacementRules: Data("rr".utf8)
        )
        _ = try await coordinator.restoreSelectively(
            manifest: [],
            selectedKeys: [],
            metadataSections: sections,
            progress: { _ in }
        )
        let calls = await dataRestorer.recordedCalls()
        #expect(calls.contains("annotations:1"))
        #expect(calls.contains("positions:1"))
        #expect(calls.contains("settings:1"))
        #expect(calls.contains("collections:1"))
        #expect(calls.contains("bookSources:2"))
        #expect(calls.contains("perBookSettings:3"))
        #expect(calls.contains("replacementRules:2"))
    }

    @Test func metadataSections_missingSection_skipsRestorerCall() async throws {
        let (coordinator, _, dataRestorer, _) = try await Self.makeRig()
        // Only positions present.
        _ = try await coordinator.restoreSelectively(
            manifest: [],
            selectedKeys: [],
            metadataSections: SelectiveRestoreMetadataSections(positions: Data("p".utf8)),
            progress: { _ in }
        )
        let calls = await dataRestorer.recordedCalls()
        #expect(calls == ["positions:1"])
    }

    // MARK: - Don't downgrade existing local rows

    @Test func restoreSelectively_existingLocalEntry_isPreserved() async throws {
        let (coordinator, persistence, _, _) = try await Self.makeRig()
        let entry = Self.makeEntry(title: "Already Here", bytes: Self.makeEPUBBytes(seed: 7))
        // Pre-insert as a local row.
        let existingRecord = BookRecord(
            fingerprintKey: entry.fingerprintKey,
            title: "Existing Local",
            author: nil,
            coverImagePath: nil,
            fingerprint: DocumentFingerprint(
                contentSHA256: entry.sha256,
                fileByteCount: entry.byteCount,
                format: .epub
            ),
            provenance: ImportProvenance(
                source: .filesApp,
                importedAt: Date(),
                originalURLBookmarkData: nil
            ),
            detectedEncoding: nil,
            addedAt: Date(),
            originalExtension: "epub",
            fileState: .local,
            blobPath: nil
        )
        _ = try await persistence.insertBook(existingRecord)

        // User does NOT select it (so it would be preplanted as remoteOnly).
        let summary = try await coordinator.restoreSelectively(
            manifest: [entry],
            selectedKeys: [],
            metadataSections: SelectiveRestoreMetadataSections(),
            progress: { _ in }
        )
        // Coordinator reports 1 preplanted (intent), but persistence
        // didn't downgrade — insertRemoteOnlyBookRecords is idempotent
        // vs existing local rows (verified in WI-3b foundation tests).
        #expect(summary.remoteOnlyCount == 1)
        let local = try await persistence.fingerprintKeys(withFileState: .local)
        #expect(local == [entry.fingerprintKey])
        let remote = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(remote.isEmpty)
    }
}
