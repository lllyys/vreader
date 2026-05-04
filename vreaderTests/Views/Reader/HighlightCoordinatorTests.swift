// Purpose: Tests for HighlightCoordinator (Phase R4b).
// Validates create/handleRemoval/restoreAll lifecycle using mock
// renderer and persistence.
//
// @coordinates-with: HighlightCoordinator.swift, HighlightRenderer.swift,
//   HighlightPersisting.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "coord_test_sha256_0000000000000000000000000000000000000",
    fileByteCount: 100,
    format: .txt
)

private func makeLocator(start: Int = 0, end: Int = 10) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: nil,
        charRangeStartUTF16: start, charRangeEndUTF16: end,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

private func makeRecord(
    id: UUID = UUID(), start: Int = 0, end: Int = 10
) -> HighlightRecord {
    HighlightRecord(
        highlightId: id,
        locator: makeLocator(start: start, end: end),
        anchor: nil, profileKey: "k", selectedText: "text", color: "yellow",
        note: nil, createdAt: Date(), updatedAt: Date()
    )
}

// MARK: - Mocks

@MainActor
private final class MockRenderer: HighlightRenderer {
    var appliedRecords: [HighlightRecord] = []
    var removedIds: [UUID] = []
    var restoreCalls = 0
    var lastRestoredRecords: [HighlightRecord]?

    func apply(record: HighlightRecord) {
        appliedRecords.append(record)
    }

    func remove(id: UUID) {
        removedIds.append(id)
    }

    var lastRestoreEvaluatorWasNonNil: Bool = false
    var lastRestoreHref: String?

    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) {
        restoreCalls += 1
        lastRestoredRecords = records
        lastRestoreHref = href
        lastRestoreEvaluatorWasNonNil = (evaluator != nil)
    }
}

private final class MockPersistence: HighlightPersisting, @unchecked Sendable {
    var addCallCount = 0
    var removeCallCount = 0
    var fetchCallCount = 0
    var stubbedHighlights: [HighlightRecord] = []
    var shouldThrow = false
    var lastAddedAnchor: AnnotationAnchor?

    func addHighlight(
        locator: Locator, selectedText: String, color: String,
        note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        try await addHighlight(
            locator: locator, anchor: nil, selectedText: selectedText,
            color: color, note: note, toBookWithKey: key
        )
    }

    func addHighlight(
        locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
        color: String, note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        addCallCount += 1
        lastAddedAnchor = anchor
        return HighlightRecord(
            highlightId: UUID(), locator: locator, anchor: anchor,
            profileKey: "\(key):hash", selectedText: selectedText, color: color,
            note: note, createdAt: Date(), updatedAt: Date()
        )
    }

    func removeHighlight(highlightId: UUID) async throws {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        removeCallCount += 1
    }

    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        fetchCallCount += 1
        return stubbedHighlights
    }
}

// MARK: - Tests

@Suite("HighlightCoordinator")
struct HighlightCoordinatorTests {

    @Test @MainActor func createPersistsAndApplies() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        let record = await coordinator.create(
            locator: makeLocator(start: 10, end: 20),
            selectedText: "hello",
            color: "yellow"
        )

        #expect(record != nil)
        #expect(persistence.addCallCount == 1)
        #expect(renderer.appliedRecords.count == 1)
        #expect(renderer.appliedRecords[0].selectedText == "hello")
    }

    @Test @MainActor func createPassesAnchorToPersistence() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )
        let anchor = AnnotationAnchor.pdf(page: 3, rects: [.zero])

        _ = await coordinator.create(
            locator: makeLocator(),
            anchor: anchor,
            selectedText: "text"
        )

        #expect(persistence.lastAddedAnchor != nil)
    }

    @Test @MainActor func createReturnsNilOnPersistenceFailure() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        persistence.shouldThrow = true
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        let record = await coordinator.create(
            locator: makeLocator(), selectedText: "text"
        )

        #expect(record == nil)
        #expect(renderer.appliedRecords.isEmpty)
    }

    @Test @MainActor func createUsesDefaultColorYellow() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        let record = await coordinator.create(
            locator: makeLocator(), selectedText: "text"
        )

        #expect(record?.color == "yellow")
    }

    @Test @MainActor func handleRemovalRemovesAndRestores() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        persistence.stubbedHighlights = [makeRecord(start: 0, end: 5)]
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )
        let id = UUID()

        await coordinator.handleRemoval(highlightId: id)

        #expect(renderer.removedIds.count == 1)
        #expect(renderer.removedIds[0] == id)
        #expect(renderer.restoreCalls == 1)
        #expect(renderer.lastRestoredRecords?.count == 1)
    }

    @Test @MainActor func handleRemovalSkipsRestoreOnFetchFailure() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        persistence.shouldThrow = true
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        await coordinator.handleRemoval(highlightId: UUID())

        // remove() still called even though fetch failed
        #expect(renderer.removedIds.count == 1)
        // restore() NOT called — fetch failure leaves visuals unchanged
        #expect(renderer.restoreCalls == 0)
    }

    @Test @MainActor func restoreAllFetchesAndRestores() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        persistence.stubbedHighlights = [
            makeRecord(start: 0, end: 10),
            makeRecord(start: 20, end: 30),
        ]
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        await coordinator.restoreAll()

        #expect(persistence.fetchCallCount == 1)
        #expect(renderer.restoreCalls == 1)
        #expect(renderer.lastRestoredRecords?.count == 2)
    }

    @Test @MainActor func restoreAllSkipsOnFetchFailure() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        persistence.shouldThrow = true
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        await coordinator.restoreAll()

        // On fetch failure, leave visuals unchanged
        #expect(renderer.restoreCalls == 0)
    }

    @Test @MainActor func createWithNote() async {
        let renderer = MockRenderer()
        let persistence = MockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        let record = await coordinator.create(
            locator: makeLocator(),
            selectedText: "text",
            note: "my note"
        )

        #expect(record?.note == "my note")
        #expect(renderer.appliedRecords.count == 1)
    }
}
#endif
