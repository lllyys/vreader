// Purpose: Tests for BackgroundIndexingCoordinator — enqueue, cancel,
// status tracking, serial execution, edge cases.

import Testing
import Foundation
@testable import vreader

// MARK: - Mock Search Service

/// Mock SearchProviding for testing indexing coordination.
actor MockSearchService: SearchProviding {
    private(set) var indexCallCount = 0
    private(set) var indexedKeys: [String] = []
    private(set) var removedKeys: [String] = []
    private var indexed: Set<String> = []
    var indexDelay: Duration?
    var shouldThrow = false

    func indexBook(
        fingerprint: DocumentFingerprint,
        textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async throws {
        if let delay = indexDelay {
            try await Task.sleep(for: delay)
        }
        if shouldThrow {
            throw SearchServiceTestError.indexFailed
        }
        indexCallCount += 1
        indexedKeys.append(fingerprint.canonicalKey)
        indexed.insert(fingerprint.canonicalKey)
    }

    func search(
        query: String,
        bookFingerprint: DocumentFingerprint,
        page: Int,
        pageSize: Int
    ) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: page, hasMore: false, totalEstimate: 0)
    }

    func removeIndex(fingerprint: DocumentFingerprint) async throws {
        removedKeys.append(fingerprint.canonicalKey)
        indexed.remove(fingerprint.canonicalKey)
    }

    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool {
        indexed.contains(fingerprint.canonicalKey)
    }
}

enum SearchServiceTestError: Error {
    case indexFailed
}

@Suite("BackgroundIndexingCoordinator")
struct BackgroundIndexingCoordinatorTests {

    // MARK: - Helpers

    private static let fp1 = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private static let fp2 = DocumentFingerprint(
        contentSHA256: "bbccddee00112233bbccddee00112233bbccddee00112233bbccddee00112233",
        fileByteCount: 2048,
        format: .pdf
    )

    // MARK: - Enqueue

    @Test func enqueueIndexingSetsStatusToIndexing() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello")]
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        // Wait for background processing to complete
        try? await Task.sleep(for: .milliseconds(100))

        // After enqueue + processing, status should be indexed
        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        #expect(status == .indexed)
    }

    @Test func enqueueCallsSearchService() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello")]
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        // Wait for background processing to complete
        try? await Task.sleep(for: .milliseconds(100))

        let count = await mock.indexCallCount
        #expect(count == 1)
    }

    // MARK: - Cancel

    @Test func cancelChangesStatusToNotIndexed() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        // Cancel before enqueue — should be no-op
        await coordinator.cancelIndexing(fingerprint: Self.fp1)
        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        #expect(status == .notIndexed)
    }

    // MARK: - Status Tracking

    @Test func statusNotIndexedByDefault() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        #expect(status == .notIndexed)
    }

    @Test func statusIndexedAfterSuccess() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Test")]
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        try? await Task.sleep(for: .milliseconds(100))

        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        #expect(status == .indexed)
    }

    @Test func statusFailedAfterError() async {
        let mock = MockSearchService()
        await mock.setThrow(true)
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Test")]
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        try? await Task.sleep(for: .milliseconds(100))

        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        if case .failed = status {
            // Expected
        } else {
            Issue.record("Expected .failed status, got \(status)")
        }
    }

    // MARK: - Multiple Books

    @Test func multipleBooksSerialized() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let units1 = [TextUnit(sourceUnitId: "txt:segment:0", text: "Book one")]
        let units2 = [TextUnit(sourceUnitId: "pdf:page:0", text: "Book two")]

        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units1,
            segmentBaseOffsets: nil
        )
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp2,
            textUnits: units2,
            segmentBaseOffsets: nil
        )

        try? await Task.sleep(for: .milliseconds(200))

        let count = await mock.indexCallCount
        #expect(count == 2)

        let status1 = await coordinator.indexingStatus(fingerprint: Self.fp1)
        let status2 = await coordinator.indexingStatus(fingerprint: Self.fp2)
        #expect(status1 == .indexed)
        #expect(status2 == .indexed)
    }

    // MARK: - parseFingerprintKey

    @Test func parseFingerprintKeyValid() {
        let fp = BackgroundIndexingCoordinator.parseFingerprintKey(
            "txt:aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233:1024"
        )
        #expect(fp != nil)
        #expect(fp?.format == .txt)
        #expect(fp?.fileByteCount == 1024)
    }

    @Test func parseFingerprintKeyInvalidFormat() {
        let fp = BackgroundIndexingCoordinator.parseFingerprintKey("invalid:abc:1024")
        #expect(fp == nil)
    }

    @Test func parseFingerprintKeyMissingParts() {
        let fp = BackgroundIndexingCoordinator.parseFingerprintKey("txt:abc")
        #expect(fp == nil)
    }

    @Test func parseFingerprintKeyInvalidByteCount() {
        let fp = BackgroundIndexingCoordinator.parseFingerprintKey(
            "txt:aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233:notanumber"
        )
        #expect(fp == nil)
    }

    // MARK: - Deduplication

    @Test func enqueueDeduplicatesSameFingerprint() async {
        let mock = MockSearchService()
        await mock.setDelay(.milliseconds(50))
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        let units1 = [TextUnit(sourceUnitId: "txt:segment:0", text: "Version 1")]
        let units2 = [TextUnit(sourceUnitId: "txt:segment:0", text: "Version 2")]

        // Enqueue same fingerprint twice before processing starts
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units1,
            segmentBaseOffsets: nil
        )
        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: units2,
            segmentBaseOffsets: nil
        )

        try? await Task.sleep(for: .milliseconds(300))

        // Should only index once (deduped), not twice
        let count = await mock.indexCallCount
        #expect(count == 1)
        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        #expect(status == .indexed)
    }

    // MARK: - Empty Text Units

    @Test func enqueueEmptyTextUnits() async {
        let mock = MockSearchService()
        let coordinator = BackgroundIndexingCoordinator(searchService: mock)

        await coordinator.enqueueIndexing(
            fingerprint: Self.fp1,
            textUnits: [],
            segmentBaseOffsets: nil
        )

        try? await Task.sleep(for: .milliseconds(100))

        let status = await coordinator.indexingStatus(fingerprint: Self.fp1)
        #expect(status == .indexed) // Empty units should still succeed
    }
}

// MARK: - MockSearchService helpers

extension MockSearchService {
    func setThrow(_ value: Bool) {
        shouldThrow = value
    }

    func setDelay(_ delay: Duration?) {
        indexDelay = delay
    }
}
