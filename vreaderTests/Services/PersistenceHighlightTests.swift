// Purpose: Tests for PersistenceActor+Highlights — CRUD, deduplication, and edge cases.
// Phase R1 of the refactoring plan.

import Testing
import Foundation
@testable import vreader

@Suite("PersistenceActor — Highlights")
struct PersistenceHighlightTests {

    private func makeLocator(key: String, offset: Int = 0) -> Locator {
        // Tolerate deliberately-bogus keys (e.g. "wrong:key:123") used by
        // mismatched-key rejection tests. A real canonical key parses;
        // otherwise we derive a deterministic, well-formed fallback fingerprint
        // so the rejection path can run without trapping on a force-unwrap.
        let fp = DocumentFingerprint(canonicalKey: key)
            ?? CollectionTestHelper.makeBogusFingerprint(seed: key)
        return Locator.validated(
            bookFingerprint: fp,
            charOffsetUTF16: offset,
            charRangeStartUTF16: offset,
            charRangeEndUTF16: offset + 10
        )!
    }

    // MARK: - Add

    @Test func addHighlightCreatesRecord() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 100)

        let record = try await persistence.addHighlight(
            locator: locator, selectedText: "hello", color: "yellow",
            note: nil, toBookWithKey: key
        )

        #expect(record.selectedText == "hello")
        #expect(record.color == "yellow")
        #expect(record.note == nil)
    }

    @Test func addHighlightWithNote() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 200)

        let record = try await persistence.addHighlight(
            locator: locator, selectedText: "world", color: "blue",
            note: "important", toBookWithKey: key
        )

        #expect(record.note == "important")
    }

    @Test func addHighlightRejectsMismatchedKey() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let wrongLocator = makeLocator(key: "wrong:key:123", offset: 0)

        await #expect(throws: (any Error).self) {
            try await persistence.addHighlight(
                locator: wrongLocator, selectedText: "x", color: "y",
                note: nil, toBookWithKey: key
            )
        }
    }

    @Test func addHighlightToMissingBookThrows() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        // A valid, parseable canonical key for a book that was never inserted —
        // ensures the bookFingerprint/key guard passes and the persistence
        // layer hits the actual missing-book lookup.
        let missingKey = CollectionTestHelper.makeFingerprint(
            sha: String(repeating: "b", count: 64), byteCount: 1, format: .epub
        ).canonicalKey
        let locator = makeLocator(key: missingKey, offset: 0)

        await #expect(throws: (any Error).self) {
            try await persistence.addHighlight(
                locator: locator, selectedText: "x", color: "y",
                note: nil, toBookWithKey: missingKey
            )
        }
    }

    // MARK: - Deduplication

    @Test func addDuplicateHighlightReturnsSameId() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 300)

        let first = try await persistence.addHighlight(
            locator: locator, selectedText: "dup", color: "yellow",
            note: nil, toBookWithKey: key
        )
        let second = try await persistence.addHighlight(
            locator: locator, selectedText: "dup", color: "yellow",
            note: nil, toBookWithKey: key
        )

        #expect(first.highlightId == second.highlightId)
    }

    // MARK: - Fetch

    @Test func fetchHighlightsReturnsAll() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)

        _ = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 10), selectedText: "a",
            color: "yellow", note: nil, toBookWithKey: key
        )
        _ = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 20), selectedText: "b",
            color: "blue", note: nil, toBookWithKey: key
        )

        let all = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(all.count == 2)
    }

    @Test func fetchHighlightsForMissingBookReturnsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let all = try await persistence.fetchHighlights(forBookWithKey: "nonexistent:key:0")
        #expect(all.isEmpty)
    }

    // MARK: - Delete

    @Test func removeHighlightDeletesRecord() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let record = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 50), selectedText: "del",
            color: "red", note: nil, toBookWithKey: key
        )

        try await persistence.removeHighlight(highlightId: record.highlightId)

        let remaining = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(remaining.isEmpty)
    }

    @Test func removeNonexistentHighlightIsIdempotent() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        try await persistence.removeHighlight(highlightId: UUID())
        // No throw — idempotent
    }

    // MARK: - Update

    @Test func updateHighlightNote() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let record = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 60), selectedText: "note",
            color: "yellow", note: nil, toBookWithKey: key
        )

        try await persistence.updateHighlightNote(highlightId: record.highlightId, note: "updated")

        let all = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(all.first?.note == "updated")
    }

    @Test func updateHighlightColor() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let record = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 70), selectedText: "color",
            color: "yellow", note: nil, toBookWithKey: key
        )

        try await persistence.updateHighlightColor(highlightId: record.highlightId, color: "green")

        let all = try await persistence.fetchHighlights(forBookWithKey: key)
        #expect(all.first?.color == "green")
    }
}
