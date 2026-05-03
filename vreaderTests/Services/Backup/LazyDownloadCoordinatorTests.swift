// Purpose: Tests for LazyDownloadCoordinator @MainActor observable state
// transitions: progress, completion, failure, terminal-outcome ordering
// invariants, and the prepareToDownload retry seam. Feature #47 WI-3a.

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
        #expect(coord.terminalKeys.isEmpty)
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

    @Test func didProgress_unknownTotalBytesMapsToNil() {
        // URLSession reports NSURLSessionTransferSizeUnknown == -1 when
        // the server didn't send Content-Length. UI consumers must see
        // this as nil so they render an indeterminate spinner instead of
        // dividing by -1.
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "k", bytesWritten: 42, totalBytes: -1)
        let p = coord.progressByKey["k"]
        #expect(p?.bytesWritten == 42)
        #expect(p?.totalBytes == nil)
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
        #expect(coord.terminalKeys.contains("epub:abc:1024"))
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
        #expect(coord.terminalKeys.contains("epub:abc:1024"))
        if case .failed(_, let reason) = coord.outcomes["epub:abc:1024"] {
            #expect(reason == "network timeout")
        } else {
            Issue.record("expected .failed outcome")
        }
    }

    // MARK: - Terminal-outcome invariants

    @Test func didProgress_afterCompletion_isIgnored() {
        // The delegate hops to MainActor via independent Tasks, so a stale
        // didWriteData callback can land after didFinish. Coordinator must
        // not resurrect progress for a key that already completed.
        let coord = LazyDownloadCoordinator()
        let staged = URL(fileURLWithPath: "/tmp/staged.epub")
        coord.didFinishDownload(fingerprintKey: "k", meta: makeMeta(), stagedURL: staged)
        coord.didProgress(fingerprintKey: "k", bytesWritten: 999, totalBytes: 1024)
        #expect(coord.progressByKey["k"] == nil)
    }

    @Test func didProgress_afterFailure_isIgnored() {
        let coord = LazyDownloadCoordinator()
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "boom")
        coord.didProgress(fingerprintKey: "k", bytesWritten: 1, totalBytes: 10)
        #expect(coord.progressByKey["k"] == nil)
    }

    @Test func didFinishDownload_doesNotOverwriteFailure() {
        // If a failure already landed (e.g., move-from-tmp error), a late
        // success event must not silently flip the outcome to .completed.
        let coord = LazyDownloadCoordinator()
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "boom")
        coord.didFinishDownload(
            fingerprintKey: "k",
            meta: makeMeta(),
            stagedURL: URL(fileURLWithPath: "/tmp/x.epub")
        )
        if case .failed(_, let reason) = coord.outcomes["k"] {
            #expect(reason == "boom")
        } else {
            Issue.record("expected outcome to remain .failed")
        }
    }

    @Test func didFinishDownloadFailed_doesNotOverwriteCompletion() {
        let coord = LazyDownloadCoordinator()
        let staged = URL(fileURLWithPath: "/tmp/x.epub")
        coord.didFinishDownload(fingerprintKey: "k", meta: makeMeta(), stagedURL: staged)
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "late error")
        if case .completed(_, let url) = coord.outcomes["k"] {
            #expect(url == staged)
        } else {
            Issue.record("expected outcome to remain .completed")
        }
    }

    @Test func didProgress_afterClearOutcome_isStillIgnored() {
        // clearOutcome dismisses the UI-visible outcome but must NOT
        // unblock late progress callbacks — terminal state is sticky.
        let coord = LazyDownloadCoordinator()
        coord.didFinishDownload(
            fingerprintKey: "k",
            meta: makeMeta(),
            stagedURL: URL(fileURLWithPath: "/tmp/x.epub")
        )
        coord.clearOutcome(for: "k")
        coord.didProgress(fingerprintKey: "k", bytesWritten: 1, totalBytes: 10)
        #expect(coord.progressByKey["k"] == nil)
        #expect(coord.terminalKeys.contains("k"))
    }

    // MARK: - Outcome lifecycle

    @Test func clearOutcome_removesOutcomeButNotTerminalGuard() {
        let coord = LazyDownloadCoordinator()
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "x")
        #expect(coord.outcomes["k"] != nil)
        coord.clearOutcome(for: "k")
        #expect(coord.outcomes["k"] == nil)
        #expect(coord.terminalKeys.contains("k"))
    }

    @Test func prepareToDownload_clearsOutcomeAndTerminalGuard() {
        // Retry path: WI-4a's enqueue layer calls this before a fresh
        // download starts so subsequent progress is accepted again.
        let coord = LazyDownloadCoordinator()
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "x")
        coord.prepareToDownload(fingerprintKey: "k")
        #expect(coord.outcomes["k"] == nil)
        #expect(coord.terminalKeys.contains("k") == false)

        coord.didProgress(fingerprintKey: "k", bytesWritten: 5, totalBytes: 10)
        #expect(coord.progressByKey["k"]?.bytesWritten == 5)
    }

    @Test func reset_clearsAllState() {
        let coord = LazyDownloadCoordinator()
        coord.didProgress(fingerprintKey: "a", bytesWritten: 1, totalBytes: 10)
        coord.didFinishDownloadFailed(fingerprintKey: "b", reason: "x")
        coord.reset()
        #expect(coord.progressByKey.isEmpty)
        #expect(coord.outcomes.isEmpty)
        #expect(coord.terminalKeys.isEmpty)
    }
}
