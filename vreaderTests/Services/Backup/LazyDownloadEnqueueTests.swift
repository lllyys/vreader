// Purpose: Tests for the lazy-download enqueue path added in feature
// #47 WI-6 part 2: WebDAVDownloadRequestBuilder builds the
// authenticated GET request, LazyDownloadCoordinator.enqueue applies
// the Wi-Fi-only policy gate + writes a fingerprint-bearing
// taskDescription onto the URLSessionDownloadTask via the session
// protocol seam.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("LazyDownloadCoordinator.enqueue — feature #47 WI-6")
struct LazyDownloadEnqueueTests {

    // Test seam re-using `MockBackgroundDownloadSession` from the
    // reattach suite (defined in LazyDownloadReattachTests.swift).
    // Add a controllable network policy seam here.
    private final class StubMonitor: NetworkPathMonitoring, @unchecked Sendable {
        var onPathChange: (@Sendable (WebDAVNetworkInterface) -> Void)?
        func start() {}
        func cancel() {}
        func simulate(_ interface: WebDAVNetworkInterface) {
            onPathChange?(interface)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "vreader.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeRequestBuilder() -> WebDAVDownloadRequestBuilder {
        let client = WebDAVClient(
            serverURL: URL(string: "http://example.invalid")!,
            username: "user",
            password: "pass"
        )
        return WebDAVDownloadRequestBuilder(client: client)
    }

    private func makePolicy(
        wifiOnly: Bool = true,
        interface: WebDAVNetworkInterface = .wifi
    ) async -> WebDAVNetworkPolicy {
        let monitor = StubMonitor()
        let defaults = makeDefaults()
        defaults.set(wifiOnly, forKey: WebDAVNetworkPolicy.wifiOnlyKey)
        let policy = WebDAVNetworkPolicy(defaults: defaults, monitor: monitor)
        monitor.simulate(interface)
        await Task.yield()
        return policy
    }

    private func makeMeta(key: String = "epub:abc:1024") -> LazyDownloadTaskMeta {
        LazyDownloadTaskMeta(
            fingerprintKey: key,
            blobPath: "VReader/books/epub/foo_1024.epub",
            expectedSHA256: String(repeating: "a", count: 64),
            expectedByteCount: 1024,
            originalExtension: "epub"
        )
    }

    // MARK: - Skeleton init returns notReady

    @Test func enqueue_skeletonInit_returnsNotReady() async {
        let coord = LazyDownloadCoordinator()
        let policy = await makePolicy()
        let result = coord.enqueue(
            fingerprintKey: "k",
            blobPath: "p",
            expectedSHA256: String(repeating: "a", count: 64),
            expectedByteCount: 1,
            originalExtension: "epub",
            requestBuilder: makeRequestBuilder(),
            policy: policy
        )
        #expect(result == .notReady)
    }

    // MARK: - Wi-Fi gate

    @Test func enqueue_wifiOnlyAndCellular_returnsDeferredWiFi() async throws {
        let session = MockBackgroundDownloadSession(descriptors: [])
        let persistence = try CollectionTestHelper.makePersistence()
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        let policy = await makePolicy(wifiOnly: true, interface: .cellular)

        let result = coord.enqueue(
            fingerprintKey: "k",
            blobPath: "p",
            expectedSHA256: String(repeating: "a", count: 64),
            expectedByteCount: 1,
            originalExtension: "epub",
            requestBuilder: makeRequestBuilder(),
            policy: policy
        )
        #expect(result == .deferredWiFi)
        #expect(session.enqueuedRequests.isEmpty)
        #expect(coord.progressByKey.isEmpty)
    }

    // MARK: - Happy path

    @Test func enqueue_wifiAvailable_startsTaskAndSeedsProgress() async throws {
        let session = MockBackgroundDownloadSession(descriptors: [])
        let persistence = try CollectionTestHelper.makePersistence()
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        let policy = await makePolicy(wifiOnly: true, interface: .wifi)
        let meta = makeMeta()

        let result = coord.enqueue(
            fingerprintKey: meta.fingerprintKey,
            blobPath: meta.blobPath,
            expectedSHA256: meta.expectedSHA256,
            expectedByteCount: meta.expectedByteCount,
            originalExtension: meta.originalExtension,
            requestBuilder: makeRequestBuilder(),
            policy: policy
        )
        if case .started(let id) = result {
            #expect(id >= 100)
        } else {
            Issue.record("expected .started, got \(result)")
        }
        #expect(session.enqueuedRequests.count == 1)
        let enqueued = session.enqueuedRequests[0]
        // taskDescription round-trips into the same meta.
        let decoded = try #require(LazyDownloadTaskMeta.decode(fromTaskDescription: enqueued.taskDescription))
        #expect(decoded == meta)
        // Authorization header set.
        #expect(enqueued.request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        // URL points at the blob path.
        #expect(enqueued.request.url?.absoluteString.contains("foo_1024.epub") == true)
        // Progress seeded indeterminate so UI shows spinner instantly.
        let p = coord.progressByKey[meta.fingerprintKey]
        #expect(p?.bytesWritten == 0)
        #expect(p?.totalBytes == nil)
    }

    // MARK: - Wi-Fi disabled, cellular OK

    @Test func enqueue_wifiOnlyOff_andCellular_succeeds() async throws {
        let session = MockBackgroundDownloadSession(descriptors: [])
        let persistence = try CollectionTestHelper.makePersistence()
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        let policy = await makePolicy(wifiOnly: false, interface: .cellular)

        let result = coord.enqueue(
            fingerprintKey: "k",
            blobPath: "p",
            expectedSHA256: String(repeating: "a", count: 64),
            expectedByteCount: 1,
            originalExtension: "epub",
            requestBuilder: makeRequestBuilder(),
            policy: policy
        )
        if case .started = result {
            // ok
        } else {
            Issue.record("expected .started, got \(result)")
        }
    }

    // MARK: - Retry path: prepareToDownload clears terminal

    @Test func enqueue_afterFailedOutcome_clearsTerminalAndStartsAgain() async throws {
        let session = MockBackgroundDownloadSession(descriptors: [])
        let persistence = try CollectionTestHelper.makePersistence()
        let coord = LazyDownloadCoordinator(session: session, persistence: persistence)
        await coord.waitForReattach()

        // Simulate a previous failed download leaving terminal state.
        coord.didFinishDownloadFailed(fingerprintKey: "k", reason: "network timeout")
        #expect(coord.terminalKeys.contains("k"))

        let policy = await makePolicy(wifiOnly: true, interface: .wifi)
        _ = coord.enqueue(
            fingerprintKey: "k",
            blobPath: "p",
            expectedSHA256: String(repeating: "a", count: 64),
            expectedByteCount: 1,
            originalExtension: "epub",
            requestBuilder: makeRequestBuilder(),
            policy: policy
        )
        // enqueue calls prepareToDownload internally — terminal cleared.
        #expect(coord.terminalKeys.contains("k") == false)
        #expect(coord.outcomes["k"] == nil)
        #expect(coord.progressByKey["k"] != nil)
    }
}
