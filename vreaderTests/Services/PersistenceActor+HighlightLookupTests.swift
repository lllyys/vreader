// Purpose: Tests for feature #55 WI-2 — `PersistenceActor.highlight(withID:
// forBookWithKey:)`, the single-highlight lookup the note-preview path uses,
// and `PersistenceActor`'s `HighlightLookup` conformance.
//
// Covers: a found highlight round-trips; an unknown id → nil; a highlight
// under book A is not returned for book B's key (the (id, bookKey) scoping);
// `note` round-trips both a non-nil note and a nil note; a broader-palette
// color (red/orange/purple) round-trips its `color`.

import Testing
import Foundation
@testable import vreader

@Suite("PersistenceActor — HighlightLookup")
struct PersistenceActorHighlightLookupTests {

    private func makeLocator(key: String, offset: Int = 0) -> Locator {
        let fp = DocumentFingerprint(canonicalKey: key)
            ?? CollectionTestHelper.makeBogusFingerprint(seed: key)
        return Locator.validated(
            bookFingerprint: fp,
            charOffsetUTF16: offset,
            charRangeStartUTF16: offset,
            charRangeEndUTF16: offset + 10
        )!
    }

    // MARK: - Found / not-found

    @Test func highlightWithID_returnsInsertedRecord() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let inserted = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 50),
            selectedText: "the passage", color: "yellow",
            note: "my note", toBookWithKey: key
        )

        let fetched = try await persistence.highlight(
            withID: inserted.highlightId, forBookWithKey: key
        )

        let unwrapped = try #require(fetched)
        #expect(unwrapped.highlightId == inserted.highlightId)
        #expect(unwrapped.selectedText == "the passage")
        #expect(unwrapped.color == "yellow")
        #expect(unwrapped.note == "my note")
    }

    @Test func highlightWithID_unknownID_returnsNil() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)

        let fetched = try await persistence.highlight(
            withID: UUID(), forBookWithKey: key
        )
        #expect(fetched == nil)
    }

    @Test func highlightWithID_missingBookKey_returnsNil() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let inserted = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 10),
            selectedText: "x", color: "yellow", note: nil, toBookWithKey: key
        )

        // The highlight exists, but a key for a book that was never inserted
        // must not surface it.
        let bogusKey = CollectionTestHelper.makeFingerprint(
            sha: String(repeating: "f", count: 64), byteCount: 9, format: .epub
        ).canonicalKey
        let fetched = try await persistence.highlight(
            withID: inserted.highlightId, forBookWithKey: bogusKey
        )
        #expect(fetched == nil)
    }

    // MARK: - Cross-book isolation

    @Test func highlightWithID_isScopedToOwningBook() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let keyA = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Book A",
            sha: String(repeating: "a", count: 64), byteCount: 1024
        )
        let keyB = try await CollectionTestHelper.insertBook(
            persistence: persistence, title: "Book B",
            sha: String(repeating: "b", count: 64), byteCount: 2048
        )

        let inA = try await persistence.addHighlight(
            locator: makeLocator(key: keyA, offset: 30),
            selectedText: "from A", color: "green", note: "A note",
            toBookWithKey: keyA
        )

        // Same highlight id, but queried under book B's key → must be nil.
        let leaked = try await persistence.highlight(
            withID: inA.highlightId, forBookWithKey: keyB
        )
        #expect(leaked == nil)

        // And it is still found under its own book.
        let found = try await persistence.highlight(
            withID: inA.highlightId, forBookWithKey: keyA
        )
        #expect(found?.highlightId == inA.highlightId)
    }

    // MARK: - Note round-trip

    @Test func highlightWithID_roundTripsNilNote() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let inserted = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 70),
            selectedText: "no note here", color: "blue",
            note: nil, toBookWithKey: key
        )

        let fetched = try await persistence.highlight(
            withID: inserted.highlightId, forBookWithKey: key
        )
        #expect(fetched?.note == nil)
    }

    // MARK: - Broader-palette color round-trip

    @Test(arguments: ["red", "orange", "purple"])
    func highlightWithID_roundTripsBroaderPaletteColor(_ color: String) async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let inserted = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 90),
            selectedText: "colored", color: color,
            note: "n", toBookWithKey: key
        )

        let fetched = try await persistence.highlight(
            withID: inserted.highlightId, forBookWithKey: key
        )
        #expect(fetched?.color == color)
    }

    // MARK: - HighlightLookup conformance

    @Test func persistenceActorConformsToHighlightLookup() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let inserted = try await persistence.addHighlight(
            locator: makeLocator(key: key, offset: 5),
            selectedText: "via protocol", color: "yellow",
            note: "p", toBookWithKey: key
        )

        // Exercise the lookup through the protocol existential.
        let lookup: any HighlightLookup = persistence
        let fetched = try await lookup.highlight(
            withID: inserted.highlightId, forBookWithKey: key
        )
        #expect(fetched?.highlightId == inserted.highlightId)
    }
}
