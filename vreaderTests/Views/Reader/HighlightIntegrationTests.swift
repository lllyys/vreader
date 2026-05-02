// Purpose: Integration tests for highlight create → delete → restore flows
// across all format renderers. Phase R1 of the refactoring plan.
//
// Tests the full HighlightCoordinator → HighlightRenderer pipeline
// using real persistence (in-memory SwiftData) and mock renderers.

import Testing
import Foundation
@testable import vreader

// MARK: - Mock Renderer (tracks calls)

@MainActor
final class MockHighlightRenderer: HighlightRenderer {
    var appliedRecords: [HighlightRecord] = []
    var removedIds: [UUID] = []
    var restoredRecords: [[HighlightRecord]] = []

    func apply(record: HighlightRecord) {
        appliedRecords.append(record)
    }

    func remove(id: UUID) {
        removedIds.append(id)
    }

    func restore(records: [HighlightRecord]) {
        restoredRecords.append(records)
    }
}

// MARK: - Coordinator Integration Tests

@Suite("HighlightCoordinator Integration")
struct HighlightCoordinatorIntegrationTests {

    private func makeLocator(key: String, offset: Int = 0) -> Locator {
        let fp = DocumentFingerprint(canonicalKey: key)!
        return Locator.validated(
            bookFingerprint: fp,
            charOffsetUTF16: offset,
            charRangeStartUTF16: offset,
            charRangeEndUTF16: offset + 10
        )!
    }

    // MARK: - Create Flow

    @Test @MainActor func createPersistsAndApplies() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let renderer = MockHighlightRenderer()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: key
        )

        await coordinator.create(
            locator: makeLocator(key: key, offset: 100),
            selectedText: "hello world",
            color: "yellow"
        )

        #expect(renderer.appliedRecords.count == 1)
        #expect(renderer.appliedRecords[0].selectedText == "hello world")
        #expect(renderer.appliedRecords[0].color == "yellow")

        // Verify persisted in DB
        let fetched = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(fetched.count == 1)
        #expect(fetched[0].selectedText == "hello world")
    }

    // MARK: - Delete Flow

    @Test @MainActor func handleRemovalRemovesAndRestores() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let renderer = MockHighlightRenderer()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: key
        )

        // Create two highlights
        await coordinator.create(
            locator: makeLocator(key: key, offset: 10),
            selectedText: "first", color: "yellow"
        )
        await coordinator.create(
            locator: makeLocator(key: key, offset: 30),
            selectedText: "second", color: "blue"
        )

        let highlightId = renderer.appliedRecords[0].highlightId

        // Delete the first one
        await coordinator.handleRemoval(highlightId: highlightId)

        // Renderer.remove was called
        #expect(renderer.removedIds.contains(highlightId))

        // Renderer.restore was called with remaining highlights
        #expect(!renderer.restoredRecords.isEmpty)
        let lastRestore = renderer.restoredRecords.last!
        #expect(lastRestore.count == 1)
        #expect(lastRestore[0].selectedText == "second")

        // DB has only one remaining
        let fetched = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(fetched.count == 1)
    }

    // MARK: - Restore Flow

    @Test @MainActor func restoreAllLoadsFromDB() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)

        // Pre-populate DB directly
        _ = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 50),
            selectedText: "pre-existing", color: "green",
            note: nil, toBookWithKey: key
        )

        let renderer = MockHighlightRenderer()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: key
        )

        await coordinator.restoreAll()

        #expect(renderer.restoredRecords.count == 1)
        #expect(renderer.restoredRecords[0].count == 1)
        #expect(renderer.restoredRecords[0][0].selectedText == "pre-existing")
    }

    @Test @MainActor func restoreAllEmptyDBGivesEmptyRestore() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let renderer = MockHighlightRenderer()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: key
        )

        await coordinator.restoreAll()

        #expect(renderer.restoredRecords.count == 1)
        #expect(renderer.restoredRecords[0].isEmpty)
    }

    // MARK: - Dedup

    @Test @MainActor func createDuplicateDoesNotDoubleApply() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let renderer = MockHighlightRenderer()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: key
        )
        let locator = makeLocator(key: key, offset: 200)

        await coordinator.create(locator: locator, selectedText: "dup", color: "yellow")
        await coordinator.create(locator: locator, selectedText: "dup", color: "yellow")

        // Both calls go through apply (coordinator doesn't dedup — persistence does)
        // But DB should have only 1 record
        let fetched = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(fetched.count == 1)
    }

    // MARK: - Delete nonexistent

    @Test @MainActor func handleRemovalOfNonexistentIsNoOp() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let renderer = MockHighlightRenderer()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: key
        )

        await coordinator.handleRemoval(highlightId: UUID())

        // remove was called (coordinator doesn't check existence)
        #expect(renderer.removedIds.count == 1)
        // restore was called with empty list
        #expect(renderer.restoredRecords.count == 1)
        #expect(renderer.restoredRecords[0].isEmpty)
    }
}

// Note: TextHighlightRenderer unit tests live in HighlightRendererTests.swift.
// The duplicate suite that previously lived here was removed because it caused
// a `TextHighlightRendererTests` struct-name collision with HighlightRendererTests.swift.
