// Purpose: Tests for LazyDownloadDelegate.stagedTempURL — verifies the
// staging path is unique per URLSession task identifier (so concurrent
// downloads don't collide) and lives under the OS-reclaimable Caches
// directory. Feature #47 WI-3a.

import Testing
import Foundation
@testable import vreader

@Suite("LazyDownloadDelegate.stagedTempURL — feature #47 WI-3a")
struct LazyDownloadDelegateStagingTests {

    private func makeMeta(
        sha: String = String(repeating: "a", count: 64),
        bytes: Int64 = 1024,
        ext: String = "epub"
    ) -> LazyDownloadTaskMeta {
        LazyDownloadTaskMeta(
            fingerprintKey: "epub:abc:\(bytes)",
            blobPath: "p",
            expectedSHA256: sha,
            expectedByteCount: bytes,
            originalExtension: ext
        )
    }

    @Test func stagedURL_includesTaskIdentifier_soConcurrentTasksDontCollide() {
        let meta = makeMeta()
        let urlA = LazyDownloadDelegate.stagedTempURL(for: meta, taskIdentifier: 1)
        let urlB = LazyDownloadDelegate.stagedTempURL(for: meta, taskIdentifier: 2)
        // Same blob, different in-flight tasks → distinct staged paths.
        #expect(urlA != urlB)
        #expect(urlA.lastPathComponent.hasSuffix(".epub"))
        #expect(urlB.lastPathComponent.hasSuffix(".epub"))
    }

    @Test func stagedURL_livesUnderCachesDirectory() {
        let url = LazyDownloadDelegate.stagedTempURL(for: makeMeta(bytes: 1), taskIdentifier: 7)
        // The OS may reclaim Caches under storage pressure — that's fine
        // because we move into the sandbox before any persistent state
        // references the staged file.
        #expect(url.path.contains("Caches"))
        #expect(url.path.contains("LazyDownloads"))
    }

    @Test func stagedURL_namePreservesShaByteCountAndTaskId() {
        // The staged file name is part of the contract import-finalization
        // (WI-4a) reads back to verify identity. Filename layout is
        // `<sha>_<bytes>_<taskId>.<ext>`.
        let url = LazyDownloadDelegate.stagedTempURL(
            for: makeMeta(sha: String(repeating: "b", count: 64), bytes: 4096, ext: "azw3"),
            taskIdentifier: 42
        )
        let name = url.lastPathComponent
        #expect(name.contains(String(repeating: "b", count: 64)))
        #expect(name.contains("_4096_"))
        #expect(name.hasSuffix("_42.azw3"))
    }
}
