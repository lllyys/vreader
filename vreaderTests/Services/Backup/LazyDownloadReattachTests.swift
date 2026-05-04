// Purpose: Tests for LazyDownloadCoordinator's reattach + reconcile
// behavior at init — recovers in-flight task progress from the
// background URLSession and flips orphaned `.downloading` rows to
// `.failed` so the row UI surfaces a retry CTA. Feature #47 WI-3b.

import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import vreader

/// Hand-built mock for `BackgroundDownloadSessioning`. Stores a fixed
/// list of descriptors that `allInFlightDownloads()` returns; tests
/// configure it before constructing the coordinator.
final class MockBackgroundDownloadSession: BackgroundDownloadSessioning, @unchecked Sendable {
    private let descriptors: [LazyDownloadTaskDescriptor]
    /// Records of every enqueueDownload call (request, taskDescription).
    private(set) var enqueuedRequests: [(request: URLRequest, taskDescription: String)] = []
    private var nextTaskID: Int = 100

    init(descriptors: [LazyDownloadTaskDescriptor]) {
        self.descriptors = descriptors
    }

    func allInFlightDownloads() async -> [LazyDownloadTaskDescriptor] {
        descriptors
    }

    func enqueueDownload(request: URLRequest, taskDescription: String) -> Int {
        enqueuedRequests.append((request, taskDescription))
        let id = nextTaskID
        nextTaskID += 1
        return id
    }
}

/// Mock that suspends `allInFlightDownloads()` until `release()` is
/// called. Used to drive deterministic races between coordinator-state
/// mutations (didFinishDownload, didFinishDownloadFailed) and the
/// reattach pass.
final class GatedMockBackgroundDownloadSession: BackgroundDownloadSessioning, @unchecked Sendable {
    private let descriptors: [LazyDownloadTaskDescriptor]
    private let stream: AsyncStream<Void>
    private let trigger: AsyncStream<Void>.Continuation

    init(descriptors: [LazyDownloadTaskDescriptor]) {
        self.descriptors = descriptors
        var capture: AsyncStream<Void>.Continuation!
        self.stream = AsyncStream<Void> { continuation in capture = continuation }
        self.trigger = capture
    }

    func release() { trigger.yield() }

    func allInFlightDownloads() async -> [LazyDownloadTaskDescriptor] {
        var iter = stream.makeAsyncIterator()
        _ = await iter.next()
        return descriptors
    }

    func enqueueDownload(request: URLRequest, taskDescription: String) -> Int { 0 }
}

@MainActor
@Suite("LazyDownloadCoordinator — reattach + reconcile (WI-3b)")
struct LazyDownloadReattachTests {

    private func validSHA(_ char: Character) -> String { String(repeating: char, count: 64) }

    private func makeMeta(key: String, sha: String, bytes: Int64 = 1024) -> LazyDownloadTaskMeta {
        LazyDownloadTaskMeta(
            fingerprintKey: key,
            blobPath: "VReader/books/epub/\(sha)_\(bytes).epub",
            expectedSHA256: sha,
            expectedByteCount: bytes,
            originalExtension: "epub"
        )
    }

    private func makeRecord(
        sha: String,
        title: String = "Book",
        fileState: BookFileState
    ) -> BookRecord {
        let fp = DocumentFingerprint(
            contentSHA256: sha,
            fileByteCount: 1024,
            format: .epub
        )
        return BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: title,
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: ImportProvenance(
                source: .filesApp,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: nil
            ),
            detectedEncoding: nil,
            addedAt: Date(),
            originalExtension: "epub",
            fileState: fileState,
            blobPath: "VReader/books/epub/\(sha)_1024.epub"
        )
    }

    // MARK: - Reattach

    @Test func reattach_emptySession_completesQuickly() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let session = MockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()
        #expect(coord.progressByKey.isEmpty)
        #expect(coord.outcomes.isEmpty)
    }

    @Test func reattach_seedsIndeterminateProgressForLiveTasks() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let shaA = validSHA("a")
        let shaB = validSHA("b")
        // Persisted rows must already be `.downloading` for reattach to
        // seed progress — stale OS tasks for non-`.downloading` rows are
        // ignored (covered separately).
        let recordA = makeRecord(sha: shaA, fileState: .downloading)
        let recordB = makeRecord(sha: shaB, fileState: .downloading)
        _ = try await persistence.insertBook(recordA)
        _ = try await persistence.insertBook(recordB)

        let metaA = makeMeta(key: recordA.fingerprintKey, sha: shaA)
        let metaB = makeMeta(key: recordB.fingerprintKey, sha: shaB)
        let descA = LazyDownloadTaskDescriptor(taskIdentifier: 1, taskDescription: metaA.encodeAsTaskDescription())
        let descB = LazyDownloadTaskDescriptor(taskIdentifier: 2, taskDescription: metaB.encodeAsTaskDescription())
        let session = MockBackgroundDownloadSession(descriptors: [descA, descB])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        #expect(coord.progressByKey.count == 2)
        // bytesWritten 0, totalBytes nil — UI shows indeterminate spinner
        // until first real didWriteData callback arrives.
        let pA = coord.progressByKey[recordA.fingerprintKey]
        #expect(pA?.bytesWritten == 0)
        #expect(pA?.totalBytes == nil)
        let pB = coord.progressByKey[recordB.fingerprintKey]
        #expect(pB?.bytesWritten == 0)
        #expect(pB?.totalBytes == nil)
    }

    @Test func reattach_skipsTasksWithUndecodableDescription() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let descGarbage = LazyDownloadTaskDescriptor(taskIdentifier: 1, taskDescription: "garbage")
        let descNil = LazyDownloadTaskDescriptor(taskIdentifier: 2, taskDescription: nil)
        let session = MockBackgroundDownloadSession(descriptors: [descGarbage, descNil])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        #expect(coord.progressByKey.isEmpty)
    }

    // MARK: - Reconcile

    @Test func reconcile_orphanedDownloadingRow_flipsToFailed() async throws {
        // Persistence has a `.downloading` row but the session has no
        // matching live task — app crashed mid-flight.
        let persistence = try CollectionTestHelper.makePersistence()
        let orphan = makeRecord(sha: validSHA("a"), fileState: .downloading)
        _ = try await persistence.insertBook(orphan)

        let session = MockBackgroundDownloadSession(descriptors: [])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        // Persistence flipped to .failed.
        let downloadingKeys = try await persistence.fingerprintKeys(withFileState: .downloading)
        #expect(downloadingKeys.isEmpty)
        let failedKeys = try await persistence.fingerprintKeys(withFileState: .failed)
        #expect(failedKeys == [orphan.fingerprintKey])

        // Coordinator records a .failed outcome and marks the key terminal.
        #expect(coord.terminalKeys.contains(orphan.fingerprintKey))
        if case .failed(_, let reason) = coord.outcomes[orphan.fingerprintKey] {
            #expect(reason == "interrupted-by-app-termination")
        } else {
            Issue.record("expected .failed outcome for orphan")
        }
    }

    @Test func reconcile_liveDownloadingRow_isNotFlipped() async throws {
        // Persistence has a `.downloading` row AND the session has a
        // matching live task. Reconcile leaves the row alone — the live
        // delegate callbacks will drive it to its real outcome.
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = validSHA("a")
        let live = makeRecord(sha: sha, fileState: .downloading)
        _ = try await persistence.insertBook(live)

        let liveMeta = makeMeta(key: live.fingerprintKey, sha: sha)
        let liveDesc = LazyDownloadTaskDescriptor(
            taskIdentifier: 1,
            taskDescription: liveMeta.encodeAsTaskDescription()
        )
        let session = MockBackgroundDownloadSession(descriptors: [liveDesc])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        let stillDownloading = try await persistence.fingerprintKeys(withFileState: .downloading)
        #expect(stillDownloading == [live.fingerprintKey])
        let failed = try await persistence.fingerprintKeys(withFileState: .failed)
        #expect(failed.isEmpty)
        // Coordinator seeded indeterminate progress, did NOT mark terminal.
        #expect(coord.progressByKey[live.fingerprintKey] != nil)
        #expect(coord.terminalKeys.contains(live.fingerprintKey) == false)
    }

    @Test func reconcile_postsBookFileStateDidChange() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let orphan = makeRecord(sha: validSHA("a"), fileState: .downloading)
        _ = try await persistence.insertBook(orphan)

        nonisolated(unsafe) var receivedKey: String?
        nonisolated(unsafe) var receivedState: String?
        let token = NotificationCenter.default.addObserver(
            forName: .bookFileStateDidChange, object: nil, queue: nil
        ) { note in
            receivedKey = note.userInfo?["fingerprintKey"] as? String
            receivedState = note.userInfo?["state"] as? String
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let session = MockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        #expect(receivedKey == orphan.fingerprintKey)
        #expect(receivedState == "failed")
    }

    @Test func reconcile_doesNotTouchLocalOrRemoteOnlyOrFailedRows() async throws {
        // Only `.downloading` rows are reconciled. `.local`, `.remoteOnly`,
        // `.failed`, `.missingRemote` rows must be left alone.
        let persistence = try CollectionTestHelper.makePersistence()
        let local = makeRecord(sha: validSHA("a"), fileState: .local)
        let remote = makeRecord(sha: validSHA("b"), fileState: .remoteOnly)
        let failed = makeRecord(sha: validSHA("c"), fileState: .failed)
        let missing = makeRecord(sha: validSHA("d"), fileState: .missingRemote)
        _ = try await persistence.insertBook(local)
        _ = try await persistence.insertBook(remote)
        _ = try await persistence.insertBook(failed)
        _ = try await persistence.insertBook(missing)

        let session = MockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        #expect(try await persistence.fingerprintKeys(withFileState: .local) == [local.fingerprintKey])
        #expect(try await persistence.fingerprintKeys(withFileState: .remoteOnly) == [remote.fingerprintKey])
        #expect(try await persistence.fingerprintKeys(withFileState: .failed) == [failed.fingerprintKey])
        #expect(try await persistence.fingerprintKeys(withFileState: .missingRemote) == [missing.fingerprintKey])
    }

    @Test func reattach_mixedLiveAndOrphan_reconcilesOnlyOrphan() async throws {
        // Persistence has TWO `.downloading` rows. Session has a live
        // task for ONE of them. The other should be reconciled.
        let persistence = try CollectionTestHelper.makePersistence()
        let liveSHA = validSHA("a")
        let orphanSHA = validSHA("b")
        let live = makeRecord(sha: liveSHA, fileState: .downloading)
        let orphan = makeRecord(sha: orphanSHA, fileState: .downloading)
        _ = try await persistence.insertBook(live)
        _ = try await persistence.insertBook(orphan)

        let liveMeta = makeMeta(key: live.fingerprintKey, sha: liveSHA)
        let liveDesc = LazyDownloadTaskDescriptor(
            taskIdentifier: 1,
            taskDescription: liveMeta.encodeAsTaskDescription()
        )
        let session = MockBackgroundDownloadSession(descriptors: [liveDesc])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        let stillDownloading = try await persistence.fingerprintKeys(withFileState: .downloading)
        #expect(stillDownloading == [live.fingerprintKey])
        let failed = try await persistence.fingerprintKeys(withFileState: .failed)
        #expect(failed == [orphan.fingerprintKey])
        #expect(coord.progressByKey[live.fingerprintKey] != nil)
        #expect(coord.terminalKeys.contains(orphan.fingerprintKey))
    }

    @Test func reattach_liveTaskForLocalRow_isIgnored() async throws {
        // The OS handed us a live task whose persisted row is `.local`
        // (already finalized). Don't seed progress, don't treat as
        // orphan. The task will be cancelled by enqueue path later.
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = validSHA("a")
        let local = makeRecord(sha: sha, fileState: .local)
        _ = try await persistence.insertBook(local)

        let staleMeta = makeMeta(key: local.fingerprintKey, sha: sha)
        let staleDesc = LazyDownloadTaskDescriptor(
            taskIdentifier: 1,
            taskDescription: staleMeta.encodeAsTaskDescription()
        )
        let session = MockBackgroundDownloadSession(descriptors: [staleDesc])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        // No progress seeded; row stays `.local`.
        #expect(coord.progressByKey.isEmpty)
        #expect(try await persistence.fingerprintKeys(withFileState: .local) == [local.fingerprintKey])
    }

    @Test func reattach_liveTaskForFailedRow_isIgnored() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = validSHA("a")
        let failed = makeRecord(sha: sha, fileState: .failed)
        _ = try await persistence.insertBook(failed)

        let staleMeta = makeMeta(key: failed.fingerprintKey, sha: sha)
        let staleDesc = LazyDownloadTaskDescriptor(
            taskIdentifier: 1,
            taskDescription: staleMeta.encodeAsTaskDescription()
        )
        let session = MockBackgroundDownloadSession(descriptors: [staleDesc])

        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        #expect(coord.progressByKey.isEmpty)
        #expect(try await persistence.fingerprintKeys(withFileState: .failed) == [failed.fingerprintKey])
    }

    // MARK: - Terminal-key races vs reattach

    @Test func reattach_completedRaceDuringInit_doesNotOverwriteOutcome() async throws {
        // didFinishDownload races reattach. Persistence still says
        // .downloading because WI-4a's finalizer hasn't yet flipped it
        // to .local. Reattach must NOT overwrite the .completed outcome
        // with .failed and must NOT touch persistence (the finalizer
        // owns that transition).
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = validSHA("a")
        let row = makeRecord(sha: sha, fileState: .downloading)
        _ = try await persistence.insertBook(row)

        let gatedSession = GatedMockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: gatedSession, persistence: persistence)

        // didFinishDownload runs before reattach observes anything.
        coord.didFinishDownload(
            fingerprintKey: row.fingerprintKey,
            meta: makeMeta(key: row.fingerprintKey, sha: sha),
            stagedURL: URL(fileURLWithPath: "/tmp/staged.epub")
        )

        gatedSession.release()
        await coord.waitForReattach()

        // .completed outcome preserved.
        if case .completed = coord.outcomes[row.fingerprintKey] {
            // ok
        } else {
            Issue.record("expected .completed outcome to survive reattach")
        }
        // Persistence still .downloading (WI-4a's finalizer will advance).
        let downloading = try await persistence.fingerprintKeys(withFileState: .downloading)
        #expect(downloading == [row.fingerprintKey])
    }

    @Test func reattach_failedRaceDuringInit_preservesSpecificReason() async throws {
        // didFinishDownloadFailed races reattach with a specific reason
        // ("network timeout"). Reattach reconciles persistence to
        // .failed but must NOT overwrite the existing outcome.
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = validSHA("a")
        let row = makeRecord(sha: sha, fileState: .downloading)
        _ = try await persistence.insertBook(row)

        let gatedSession = GatedMockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: gatedSession, persistence: persistence)

        coord.didFinishDownloadFailed(fingerprintKey: row.fingerprintKey, reason: "network timeout")

        gatedSession.release()
        await coord.waitForReattach()

        // Outcome reason preserved (more specific than termination).
        if case .failed(_, let reason) = coord.outcomes[row.fingerprintKey] {
            #expect(reason == "network timeout")
        } else {
            Issue.record("expected .failed outcome to survive reattach")
        }
        // Persistence flipped to .failed.
        let failed = try await persistence.fingerprintKeys(withFileState: .failed)
        #expect(failed == [row.fingerprintKey])
    }

    // MARK: - Skeleton init backward compat

    @Test func skeletonInit_completesReattachImmediately() async {
        let coord = LazyDownloadCoordinator()
        await coord.waitForReattach()
        #expect(coord.progressByKey.isEmpty)
        #expect(coord.outcomes.isEmpty)
    }

    // MARK: - Bug #118 follow-up: end-to-end reattach recovery suppresses .failed

    @Test func reattach_canonicalFileOnDiskWithMatchingSHA_recoversToLocalAndSuppressesFailed() async throws {
        // Bug #118 follow-up (Codex round 2): when a `.downloading` row
        // has no live URLSession task BUT the canonical sandbox file
        // already exists with matching SHA — the previous finalize
        // moved the file but the persistence save failed — reattach
        // must recover the row to `.local` rather than flipping to
        // `.failed`. Without recovery, valid local bytes get discarded
        // and the next user tap re-downloads.
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = validSHA("a")
        let row = makeRecord(sha: sha, fileState: .downloading)
        _ = try await persistence.insertBook(row)

        // Build an isolated sandbox + matching file.
        let booksDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LazyReattachRecoveryBooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: booksDir) }

        let resolver: @Sendable (String, String) -> URL = { key, ext in
            let safe = key.replacingOccurrences(of: ":", with: "_")
            return booksDir.appendingPathComponent(safe).appendingPathExtension(ext)
        }
        // makeRecord uses 1024-byte size + sha = "aaa...". Build bytes
        // that hash to the seeded sha so localFileSHA256 agrees.
        let canonical = resolver(row.fingerprintKey, "epub")
        // The seed `validSHA("a")` is a 64-char "a" string — a synthetic
        // fingerprint that won't match real bytes. Override the
        // verifier by writing bytes with the synthetic SHA pre-baked
        // via direct DocumentFingerprint — but that's not possible
        // here. Instead, write 1024 real bytes + use their actual SHA
        // for the seeded record, not validSHA("a"). Re-do.
        let realPayload = Data(repeating: 0xAB, count: 1024)
        let realSHA = realPayload.withUnsafeBytes { ptr -> String in
            let bytes = ptr.bindMemory(to: UInt8.self).baseAddress!
            var hash = [UInt8](repeating: 0, count: 32)
            // Use CryptoKit-equivalent — Foundation's CC_SHA256.
            // For test simplicity, fall through to CryptoKit:
            return ""
        }
        // Easier: use CryptoKit directly via the test helper pattern.
        let realSHA2 = Data(SHA256.hash(data: realPayload)).map { String(format: "%02x", $0) }.joined()
        _ = realSHA  // unused — using realSHA2

        // Rebuild row with the real SHA + write the file.
        let realFingerprint = DocumentFingerprint(
            contentSHA256: realSHA2,
            fileByteCount: 1024,
            format: .epub
        )
        let realRow = BookRecord(
            fingerprintKey: realFingerprint.canonicalKey,
            title: "Recovery Test",
            author: nil,
            coverImagePath: nil,
            fingerprint: realFingerprint,
            provenance: ImportProvenance(source: .restore, importedAt: Date(), originalURLBookmarkData: nil),
            detectedEncoding: nil,
            addedAt: Date(),
            originalExtension: "epub",
            lastOpenedAt: nil,
            fileState: .downloading,
            blobPath: "VReader/books/epub/\(realSHA2)_1024.epub"
        )
        _ = try await persistence.insertBook(realRow)

        let realCanonical = resolver(realRow.fingerprintKey, "epub")
        try FileManager.default.createDirectory(at: realCanonical.deletingLastPathComponent(), withIntermediateDirectories: true)
        try realPayload.write(to: realCanonical)

        let finalizer = LazyDownloadFinalizer(persistence: persistence, canonicalURLResolver: resolver)
        let session = MockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence, finalizer: finalizer)
        await coord.waitForReattach()

        // The seeded row (`row`) had a synthetic SHA so it can't recover
        // — reattach should flip it to .failed via the original path.
        // The realRow has matching bytes — reattach must recover it to
        // .local and NOT flip to .failed.
        let local = try await persistence.fingerprintKeys(withFileState: .local)
        #expect(local.contains(realRow.fingerprintKey), "row with on-disk file + matching SHA should be recovered to .local")
        let failed = try await persistence.fingerprintKeys(withFileState: .failed)
        #expect(!failed.contains(realRow.fingerprintKey), "recovered row must NOT be flipped to .failed")

        // Coordinator outcome reflects success.
        if case .completed(let key, let stagedURL) = coord.outcomes[realRow.fingerprintKey] {
            #expect(key == realRow.fingerprintKey)
            #expect(stagedURL == realCanonical)
        } else {
            Issue.record("expected .completed outcome for recovered row, got \(String(describing: coord.outcomes[realRow.fingerprintKey]))")
        }

        // The synthetic-SHA row (no matching disk file) STILL flips to .failed.
        #expect(failed.contains(row.fingerprintKey))
    }
}
