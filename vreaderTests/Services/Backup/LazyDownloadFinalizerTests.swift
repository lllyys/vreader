// Purpose: Tests for LazyDownloadFinalizer — the WI-4b component that
// promotes a downloaded staged file into the user's library by:
// 1. Verifying SHA-256 against expected hash from LazyDownloadTaskMeta.
// 2. Moving the staged file to the canonical sandbox path.
// 3. Flipping Book.fileState .remoteOnly → .local + clearing blobPath.
//
// Bug #115: this wiring was deferred when feature #47 shipped and never
// landed. Without it, downloads complete but Book rows stay .remoteOnly
// forever, so the gray library row never becomes openable.

import CryptoKit
import Foundation
import Testing
import SwiftData
@testable import vreader

@Suite("LazyDownloadFinalizer — bug #115 (WI-4b)")
struct LazyDownloadFinalizerTests {

    // MARK: - Fixture helpers

    /// Generates random bytes, writes them to a unique temp file with the
    /// given extension, and returns (URL, hex SHA-256, byteCount). The
    /// caller must clean up the URL when done.
    private func makeStagedFile(extensionName: String = "epub", byteCount: Int = 1024) throws -> (url: URL, sha256: String, bytes: Int64) {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount { bytes[i] = UInt8(i % 256) }
        let data = Data(bytes)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LazyDownloadFinalizerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("staged_\(UUID().uuidString)").appendingPathExtension(extensionName)
        try data.write(to: url)
        let hash = SHA256.hash(data: data)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return (url, hex, Int64(byteCount))
    }

    private func makePersistence() throws -> PersistenceActor {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return PersistenceActor(modelContainer: container)
    }

    private func makeRemoteOnlyBookRecord(fingerprintKey: String, originalExtension: String) -> BookRecord {
        let parts = fingerprintKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        let format = String(parts[0])
        let sha = String(parts[1])
        let bytes = Int64(parts[2]) ?? 0
        let fingerprint = DocumentFingerprint.validated(
            contentSHA256: sha,
            fileByteCount: bytes,
            format: BookFormat(rawValue: format)!
        )!
        return BookRecord(
            fingerprintKey: fingerprintKey,
            title: "Test Book",
            author: "Test Author",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: ImportProvenance(source: .restore, importedAt: Date(), originalURLBookmarkData: nil),
            detectedEncoding: nil,
            addedAt: Date(),
            originalExtension: originalExtension,
            lastOpenedAt: nil,
            fileState: .remoteOnly,
            blobPath: "VReader/books/\(format)/\(sha)_\(bytes).\(originalExtension)"
        )
    }

    /// Resolves the canonical sandbox URL inside a per-test temp directory
    /// so we don't pollute the real ImportedBooks folder.
    private func makeIsolatedResolver() -> (URL, @Sendable (String, String) -> URL) {
        let booksDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LazyDownloadFinalizerTests-Books-\(UUID().uuidString)", isDirectory: true)
        let resolver: @Sendable (String, String) -> URL = { key, ext in
            let safeName = key.replacingOccurrences(of: ":", with: "_")
            return booksDir.appendingPathComponent(safeName).appendingPathExtension(ext)
        }
        return (booksDir, resolver)
    }

    // MARK: - Happy path

    @Test func finalize_movesFileToCanonicalPath_andFlipsFileStateToLocal() async throws {
        let staged = try makeStagedFile(extensionName: "epub", byteCount: 2048)
        defer { try? FileManager.default.removeItem(at: staged.url.deletingLastPathComponent()) }
        let fingerprintKey = "epub:\(staged.sha256):\(staged.bytes)"
        let persistence = try makePersistence()
        _ = try await persistence.insertBook(makeRemoteOnlyBookRecord(fingerprintKey: fingerprintKey, originalExtension: "epub"))

        let (booksDir, resolver) = makeIsolatedResolver()
        defer { try? FileManager.default.removeItem(at: booksDir) }

        let finalizer = LazyDownloadFinalizer(persistence: persistence, canonicalURLResolver: resolver)
        let meta = LazyDownloadTaskMeta(
            fingerprintKey: fingerprintKey,
            blobPath: "VReader/books/epub/\(staged.sha256)_\(staged.bytes).epub",
            expectedSHA256: staged.sha256,
            expectedByteCount: staged.bytes,
            originalExtension: "epub"
        )

        try await finalizer.finalize(stagedURL: staged.url, meta: meta)

        // File moved to canonical path
        let canonical = resolver(fingerprintKey, "epub")
        #expect(FileManager.default.fileExists(atPath: canonical.path))
        #expect(!FileManager.default.fileExists(atPath: staged.url.path))

        // Book row flipped to .local with blobPath cleared
        let states = try await persistence.fingerprintKeys(withFileState: .local)
        #expect(states.contains(fingerprintKey))
        let remoteOnly = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(!remoteOnly.contains(fingerprintKey))
    }

    // MARK: - Mismatch

    @Test func finalize_sha256Mismatch_throwsAndLeavesFileAndStateUntouched() async throws {
        let staged = try makeStagedFile(extensionName: "epub", byteCount: 1024)
        defer { try? FileManager.default.removeItem(at: staged.url.deletingLastPathComponent()) }
        let wrongSHA = String(repeating: "9", count: 64)
        let fingerprintKey = "epub:\(wrongSHA):\(staged.bytes)"
        let persistence = try makePersistence()
        _ = try await persistence.insertBook(makeRemoteOnlyBookRecord(fingerprintKey: fingerprintKey, originalExtension: "epub"))

        let (booksDir, resolver) = makeIsolatedResolver()
        defer { try? FileManager.default.removeItem(at: booksDir) }

        let finalizer = LazyDownloadFinalizer(persistence: persistence, canonicalURLResolver: resolver)
        let meta = LazyDownloadTaskMeta(
            fingerprintKey: fingerprintKey,
            blobPath: "x",
            expectedSHA256: wrongSHA,
            expectedByteCount: staged.bytes,
            originalExtension: "epub"
        )

        await #expect(throws: LazyDownloadFinalizer.Failure.self) {
            try await finalizer.finalize(stagedURL: staged.url, meta: meta)
        }

        // Staged file untouched, canonical not created, row still .remoteOnly
        #expect(FileManager.default.fileExists(atPath: staged.url.path))
        let canonical = resolver(fingerprintKey, "epub")
        #expect(!FileManager.default.fileExists(atPath: canonical.path))
        let remoteOnly = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(remoteOnly.contains(fingerprintKey))
    }

    // MARK: - Idempotency on retry

    // MARK: - Coordinator integration (bug #115)

    /// Reference-type holder so an @objc-style notification block can
    /// mutate observed state without inout/Sendable contortions. The
    /// block is single-threaded (queue: .main) and the test is @MainActor.
    @MainActor
    private final class NotificationCapture {
        var receivedKey: String?
        var receivedState: String?
    }

    @MainActor
    @Test func coordinator_didFinishDownload_promotesRowToLocal_andPostsNotification() async throws {
        // Bug #115: didFinishDownload must run the finalizer asynchronously,
        // flip the Book row to .local, and post .bookFileStateDidChange so
        // the library can refresh without polling.
        let staged = try makeStagedFile(extensionName: "epub", byteCount: 4096)
        defer { try? FileManager.default.removeItem(at: staged.url.deletingLastPathComponent()) }
        let fingerprintKey = "epub:\(staged.sha256):\(staged.bytes)"
        let persistence = try makePersistence()
        _ = try await persistence.insertBook(makeRemoteOnlyBookRecord(fingerprintKey: fingerprintKey, originalExtension: "epub"))

        let (booksDir, resolver) = makeIsolatedResolver()
        defer { try? FileManager.default.removeItem(at: booksDir) }
        let finalizer = LazyDownloadFinalizer(persistence: persistence, canonicalURLResolver: resolver)

        let session = MockBackgroundDownloadSession(descriptors: [])
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence, finalizer: finalizer)
        await coord.waitForReattach()

        let capture = NotificationCapture()
        // The notification block runs on .main but Swift concurrency
        // doesn't see that — extract the primitives we need from the
        // notification synchronously, then hop to MainActor for the
        // capture mutation.
        nonisolated(unsafe) let unsafeKey = fingerprintKey
        let token = NotificationCenter.default.addObserver(
            forName: .bookFileStateDidChange, object: nil, queue: .main
        ) { n in
            let key = n.userInfo?["fingerprintKey"] as? String
            let state = n.userInfo?["state"] as? String
            MainActor.assumeIsolated {
                if key == unsafeKey {
                    capture.receivedKey = key
                    capture.receivedState = state
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let meta = LazyDownloadTaskMeta(
            fingerprintKey: fingerprintKey,
            blobPath: "VReader/books/epub/\(staged.sha256)_\(staged.bytes).epub",
            expectedSHA256: staged.sha256,
            expectedByteCount: staged.bytes,
            originalExtension: "epub"
        )

        coord.didFinishDownload(fingerprintKey: fingerprintKey, meta: meta, stagedURL: staged.url)

        // Wait up to 2s for the async finalize Task to complete and post.
        let deadline = Date().addingTimeInterval(2)
        while capture.receivedKey == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(capture.receivedKey == fingerprintKey)
        #expect(capture.receivedState == BookFileState.local.rawValue)

        // DB row flipped, file moved.
        let states = try await persistence.fingerprintKeys(withFileState: .local)
        #expect(states.contains(fingerprintKey))
        let canonical = resolver(fingerprintKey, "epub")
        #expect(FileManager.default.fileExists(atPath: canonical.path))

        // Coordinator outcome reflects success.
        if case .completed(let key, _) = coord.outcomes[fingerprintKey] {
            #expect(key == fingerprintKey)
        } else {
            Issue.record("expected coordinator outcome to be .completed, got \(String(describing: coord.outcomes[fingerprintKey]))")
        }
    }

    @Test func finalize_overwritesPreexistingCanonicalFile() async throws {
        // Retry after a partial failure: the canonical file may already
        // exist from a previous attempt. Finalize must replace it.
        let staged = try makeStagedFile(extensionName: "epub", byteCount: 1024)
        defer { try? FileManager.default.removeItem(at: staged.url.deletingLastPathComponent()) }
        let fingerprintKey = "epub:\(staged.sha256):\(staged.bytes)"
        let persistence = try makePersistence()
        _ = try await persistence.insertBook(makeRemoteOnlyBookRecord(fingerprintKey: fingerprintKey, originalExtension: "epub"))

        let (booksDir, resolver) = makeIsolatedResolver()
        defer { try? FileManager.default.removeItem(at: booksDir) }
        let canonical = resolver(fingerprintKey, "epub")
        try FileManager.default.createDirectory(at: canonical.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 16).write(to: canonical)

        let finalizer = LazyDownloadFinalizer(persistence: persistence, canonicalURLResolver: resolver)
        let meta = LazyDownloadTaskMeta(
            fingerprintKey: fingerprintKey,
            blobPath: "x",
            expectedSHA256: staged.sha256,
            expectedByteCount: staged.bytes,
            originalExtension: "epub"
        )

        try await finalizer.finalize(stagedURL: staged.url, meta: meta)

        #expect(FileManager.default.fileExists(atPath: canonical.path))
        let bytes = try Data(contentsOf: canonical)
        #expect(bytes.count == 1024)
        let states = try await persistence.fingerprintKeys(withFileState: .local)
        #expect(states.contains(fingerprintKey))
    }
}
