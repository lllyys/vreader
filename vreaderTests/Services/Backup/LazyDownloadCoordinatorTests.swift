// Purpose: Tests for LazyDownloadCoordinator — verifies the @MainActor
// observable state transitions in response to forwarded events from the
// nonisolated LazyDownloadDelegate. Feature #47 WI-3a skeleton scope —
// no lifecycle persistence (WI-3b) or import dispatch (WI-4a) yet.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("LazyDownloadCoordinator — feature #47 WI-3a")
struct LazyDownloadCoordinatorTests {

    private func makeMeta(
        key: String = "epub:abc:1024",
        sha: String = String(repeating: "a", count: 64),
        bytes: Int64 = 1024,
        ext: String = "epub"
    ) -> LazyDownloadTaskMeta {
        LazyDownloadTaskMeta(
            fingerprintKey: key,
            blobPath: "VReader/books/epub/\(sha)_\(bytes).epub",
            expectedSHA256: sha,
            expectedByteCount: bytes,
            originalExtension: ext
        )
    }

    // MARK: - Initial state

    @Test func freshCoordinatorHasNoProgressOrOutcomes() {
        let coord = LazyDownloadCoordinator()
        #expect(coord.progressByKey.isEmpty)
        #expect(coord.outcomes.isEmpty)
    }

    // MARK: - Progress

    @Test func didProgress_updatesProgressForKey() {
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "epub:abc:1024", bytesWritten: 256, totalBytes: 1024)
        let p = coord.progressByKey["epub:abc:1024"]
        #expect(p?.bytesWritten == 256)
        #expect(p?.totalBytes == 1024)
    }

    @Test func didProgress_updatesAreIndependentPerKey() {
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "epub:a:1", bytesWritten: 10, totalBytes: 100)
        coord.didProgress(fingerprintKey: "epub:b:2", bytesWritten: 50, totalBytes: 100)
        #expect(coord.progressByKey.count == 2)
        #expect(coord.progressByKey["epub:a:1"]?.bytesWritten == 10)
        #expect(coord.progressByKey["epub:b:2"]?.bytesWritten == 50)
    }

    // MARK: - Completion

    @Test func didFinishDownload_clearsProgressAndRecordsOutcome() {
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "epub:abc:1024", bytesWritten: 1024, totalBytes: 1024)
        let staged = URL(fileURLWithPath: "/tmp/staged-blob.epub")
        coord.didFinishDownload(
            fingerprintKey: "epub:abc:1024",
            meta: makeMeta(),
            stagedURL: staged
        )
        #expect(coord.progressByKey["epub:abc:1024"] == nil)
        if case .completed(_, let url) = coord.outcomes["epub:abc:1024"] {
            #expect(url == staged)
        } else {
            Issue.record("expected .completed outcome")
        }
    }

    // MARK: - Failure

    @Test func didFinishDownloadFailed_clearsProgressAndRecordsFailedOutcome() {
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "epub:abc:1024", bytesWritten: 100, totalBytes: 1024)
        coord.didFinishDownloadFailed(
            fingerprintKey: "epub:abc:1024",
            reason: "network timeout"
        )
        #expect(coord.progressByKey["epub:abc:1024"] == nil)
        if case .failed(_, let reason) = coord.outcomes["epub:abc:1024"] {
            #expect(reason == "network timeout")
        } else {
            Issue.record("expected .failed outcome")
        }
    }

    // MARK: - Outcome lifecycle

    @Test func clearOutcome_removesOutcomeForKey() {
        let coord = LazyDownloadCoordinator()
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "x")
        #expect(coord.outcomes["k"] != nil)
        coord.clearOutcome(for: "k")
        #expect(coord.outcomes["k"] == nil)
    }

    @Test func reset_clearsAllState() {
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "a", bytesWritten: 1, totalBytes: 10)
        coord.didFinishDownloadFailed(fingerprintKey: "b", reason: "x")
        coord.reset()
        #expect(coord.progressByKey.isEmpty)
        #expect(coord.outcomes.isEmpty)
    }
}

@Suite("LazyDownloadTaskMeta — feature #47 WI-3a")
struct LazyDownloadTaskMetaTests {

    @Test func encode_decode_roundTrips() throws {
        let original = LazyDownloadTaskMeta(
            fingerprintKey: "epub:abc:1024",
            blobPath: "VReader/books/epub/foo_1024.epub",
            expectedSHA256: String(repeating: "a", count: 64),
            expectedByteCount: 1024,
            originalExtension: "epub"
        )
        let encoded = try #require(original.encodeAsTaskDescription())
        let decoded = try #require(LazyDownloadTaskMeta.decode(fromTaskDescription: encoded))
        #expect(decoded == original)
    }

    @Test func decode_nilDescription_returnsNil() {
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: nil) == nil)
    }

    @Test func decode_garbageDescription_returnsNil() {
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: "not json") == nil)
    }

    @Test func decode_unknownSchemaVersion_returnsNil() throws {
        // A future v2 task description must be rejected by a v1 client so
        // the orphan handler kicks in (cancel + flip row to .failed).
        let futureMeta = """
        {"schemaVersion":99,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(String(repeating: "a", count: 64))","expectedByteCount":1,"originalExtension":"epub"}
        """
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: futureMeta) == nil)
    }

    @Test func currentSchemaVersionIsOne() {
        #expect(LazyDownloadTaskMeta.currentSchemaVersion == 1)
    }
}
