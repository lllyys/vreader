// Purpose: Tests for SelectiveRestoreCoordinator — the 3-phase
// orchestrator (preplant remoteOnly → materialize selected → restore
// metadata) for the picker-driven restore flow. Feature #47 WI-4b.

import Testing
import Foundation
import CryptoKit
@testable import vreader

// Bug #225: this suite was test-isolation-broken.
// `preplant_partialSuccess_notifiesForLandedRowsOnly` and
// `preplant_postsBookFileStateDidChange_perRow` capture `.bookFileStateDidChange`
// posts through a `NotificationCenter` observer registered with `object: nil`,
// and `restoreSelectively`'s preplant phase posts `.bookFileStateDidChange` per
// row on the shared global center. Swift Testing runs the suite's `@Test`s in
// parallel, so a sibling test's `restoreSelectively` posts polluted the
// capturing test's `receivedKeys` with cross-fingerprint / duplicate keys,
// breaking the per-row assertions.
//
// `.serialized` alone did NOT fix it — the suite mixes `@MainActor` and
// non-isolated `@Test`s, and the observed pollution proved the suite's tests
// still overlapped. The deterministic fix: the two capturing tests mint their
// entries from `makeUniqueEPUBBytes()` (globally-unique fingerprintKeys) and
// observe through `observePreplant(expectedKeys:)`, which records only posts
// whose `fingerprintKey` is in the test's own key set. A sibling's posts carry
// different keys and are dropped — so the capture is exact regardless of
// parallel scheduling. `.serialized` is kept as documented intent + cheap
// defense-in-depth (same trait the bug #213 `BookSourceHTTPClient` suite uses).
@Suite("SelectiveRestoreCoordinator — feature #47 WI-4b", .serialized)
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

    /// Bug #225: EPUB bytes whose SHA — and therefore `fingerprintKey` — is
    /// globally unique. The seed-based `makeEPUBBytes(seed:)` produces the
    /// SAME key for the same seed across tests, so a sibling test's
    /// `.bookFileStateDidChange` post can carry a key a capturing test also
    /// expects. Tests that observe notifications mint their entries from
    /// these unique bytes so no sibling can ever produce a colliding key,
    /// making the observer's key-set filter exact regardless of Swift
    /// Testing's parallel scheduling.
    private static func makeUniqueEPUBBytes() -> Data {
        var bytes = Data([0x50, 0x4B, 0x03, 0x04])
        withUnsafeBytes(of: UUID().uuid) { bytes.append(contentsOf: $0) }
        bytes.append(Data(repeating: 0xA5, count: 1024))
        return bytes
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

        // Bug #230 / GH #954: record progress values synchronously under a
        // lock. `progress` is `@Sendable (Double) -> Void` and the coordinator
        // calls it synchronously while it runs, so recording inline guarantees
        // every value is captured in call order by the time
        // `restoreSelectively` returns. The previous `{ v in Task { await
        // collector.record(v) } }` spawned a detached Task per callback and
        // relied on `Task.yield()` to drain them — but `Task.yield()` is not a
        // synchronization primitive, so under load the final callback's Task
        // (recording 1.0) could be unscheduled when the test read `values`,
        // leaving `values.last == 0.85` and flaking the assertion.
        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [Double] = []
            func record(_ v: Double) { lock.lock(); storage.append(v); lock.unlock() }
            var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
        }
        let collector = Collector()

        _ = try await coordinator.restoreSelectively(
            manifest: [entry],
            selectedKeys: [entry.fingerprintKey],
            metadataSections: SelectiveRestoreMetadataSections(),
            progress: { v in collector.record(v) }
        )
        let values = collector.values
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

    // MARK: - Bug #116: preplant must notify Library so rows show without app relaunch

    /// Reference holder for notification capture. The observer block runs
    /// on `.main` queue but Swift concurrency doesn't see that, so we use
    /// `nonisolated(unsafe)` access with the test confined to MainActor.
    @MainActor
    private final class PreplantNotificationCapture {
        var receivedKeys: [String] = []
    }

    /// Bug #225: registers a `.bookFileStateDidChange` observer that records
    /// ONLY posts whose `fingerprintKey` is in `expectedKeys`. The suite's
    /// other tests post `.bookFileStateDidChange` on the shared global
    /// `NotificationCenter`, and Swift Testing runs `@Test`s in parallel —
    /// so without a per-test filter a sibling's posts pollute this test's
    /// `receivedKeys`. The capturing tests mint their entries from
    /// `makeUniqueEPUBBytes()`, so `expectedKeys` are globally unique and
    /// no sibling can ever produce a colliding key — the filter is exact.
    /// Returns the capture object plus the observer token; caller must
    /// `removeObserver` in a `defer`.
    @MainActor
    private static func observePreplant(
        expectedKeys: Set<String>
    ) -> (capture: PreplantNotificationCapture, token: NSObjectProtocol) {
        let capture = PreplantNotificationCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .bookFileStateDidChange, object: nil, queue: .main
        ) { n in
            let key = n.userInfo?["fingerprintKey"] as? String
            MainActor.assumeIsolated {
                if let key, expectedKeys.contains(key) {
                    capture.receivedKeys.append(key)
                }
            }
        }
        return (capture, token)
    }

    // MARK: - Bug #119: partial-success preplant still notifies for landed rows

    @MainActor
    @Test func preplant_partialSuccess_notifiesForLandedRowsOnly() async throws {
        // Bug #119: insertRemoteOnlyBookRecords has documented partial-success
        // semantics — earlier rows persist before a later row throws. The
        // earlier #116 fix posted notifications only after a clean
        // try-await return, so a throw on record N skipped notifications
        // for rows 1..N-1 even though they were already in the DB. The
        // fix uses the new partialBulkInsert error to drain insertedKeys
        // and still notify for what landed. Reproduce: build a 3-entry
        // manifest where entry #2's fingerprintKey doesn't match its
        // canonical key (insertBook throws .invalidContent on it).
        let (coordinator, persistence, _, _) = try await Self.makeRig()
        // Bug #225: unique bytes → globally-unique fingerprintKeys so a
        // sibling test's posts cannot collide with this test's observer.
        let goodA = Self.makeEntry(title: "A", bytes: Self.makeUniqueEPUBBytes())
        let goodC = Self.makeEntry(title: "C", bytes: Self.makeUniqueEPUBBytes())
        // Entry B carries a fingerprintKey that doesn't match its
        // computed fingerprint — trips PersistenceError.invalidContent
        // inside insertBook.
        let realB = Self.makeEntry(title: "B", bytes: Self.makeUniqueEPUBBytes())
        let badB = BackupLibraryEntry(
            fingerprintKey: "epub:0000000000000000000000000000000000000000000000000000000000000000:9999",
            format: realB.format,
            sha256: realB.sha256,
            byteCount: realB.byteCount,
            originalExtension: realB.originalExtension,
            title: realB.title,
            author: realB.author,
            addedAt: realB.addedAt,
            lastOpenedAt: realB.lastOpenedAt,
            blobPath: realB.blobPath
        )

        // Filter on every manifest key (not just goodA's): only goodA
        // should land + notify, but including badB/goodC means a
        // regression that wrongly notifies for B or C still surfaces.
        let observed = Self.observePreplant(
            expectedKeys: [goodA.fingerprintKey, badB.fingerprintKey, goodC.fingerprintKey]
        )
        let capture = observed.capture
        defer { NotificationCenter.default.removeObserver(observed.token) }

        do {
            _ = try await coordinator.restoreSelectively(
                manifest: [goodA, badB, goodC],
                selectedKeys: [],
                metadataSections: SelectiveRestoreMetadataSections(),
                progress: { _ in }
            )
            Issue.record("expected throw on bad entry B")
        } catch let PersistenceError.partialBulkInsert(insertedKeys, _) {
            // Phase 1 throws after row A inserts but row B trips invalidContent.
            #expect(insertedKeys == [goodA.fingerprintKey])
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Bug #119 invariant: notifications fire for what actually
        // landed. Row A is persisted, so the user must see it on the
        // next library refresh — not stranded until app relaunch.
        #expect(capture.receivedKeys == [goodA.fingerprintKey])

        // Sanity: persistence really has only row A, not B or C (the
        // throw stopped Phase 1 mid-batch).
        let remoteKeys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(remoteKeys == [goodA.fingerprintKey])
    }

    @MainActor
    @Test func preplant_postsBookFileStateDidChange_perRow() async throws {
        // Bug #116: SelectiveRestorePicker dismissal didn't refresh the
        // library because the preplant path inserted .remoteOnly rows
        // directly via PersistenceActor without notifying observers.
        // After the fix, every preplanted row posts .bookFileStateDidChange
        // so LibraryView's existing observer triggers a force-refresh.
        let (coordinator, _, _, _) = try await Self.makeRig()
        // Bug #225: unique bytes → globally-unique fingerprintKeys so a
        // sibling test's posts cannot collide with this test's observer.
        let entries = (0..<3).map { i in
            Self.makeEntry(title: "B\(i)", bytes: Self.makeUniqueEPUBBytes())
        }
        let expectedKeys = Set(entries.map(\.fingerprintKey))

        let observed = Self.observePreplant(expectedKeys: expectedKeys)
        let capture = observed.capture
        defer { NotificationCenter.default.removeObserver(observed.token) }

        _ = try await coordinator.restoreSelectively(
            manifest: entries,
            selectedKeys: [],
            metadataSections: SelectiveRestoreMetadataSections(),
            progress: { _ in }
        )

        // Drain the .main queue so .bookFileStateDidChange posts deliver
        // before we assert. addObserver delivers on the next runloop tick.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Each preplanted row must post exactly once. The key-set filter in
        // `observePreplant` already drops sibling-test pollution, so the
        // cardinality check pins "one notification per row" — a regression
        // that double-posts a row would slip past a bare Set comparison.
        #expect(capture.receivedKeys.count == entries.count)
        #expect(Set(capture.receivedKeys) == expectedKeys)
    }
}
