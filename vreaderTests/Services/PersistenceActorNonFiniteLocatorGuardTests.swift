// Purpose: feature #109 WI-2 / bug #356 — the persistence boundary must never
// store an INVALID (non-finite-progression) locator. A non-finite locator
// canonicalizes the SAME as a valid missing-progression one (canonicalJSON omits
// non-finite), so persisting it lets an invalid position collide with a valid one
// on the derived key. Every locator-writing entry point repairs the locator
// (nulls non-finite fields) before deriving keys / constructing rows.
//
// @coordinates-with: PersistenceActor+{ReadingPosition,Highlights,Bookmarks,
//   Annotations,Backup}.swift, Locator.repairedForCanonicalization()

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("PersistenceActor non-finite locator guard (#109 WI-2)")
struct PersistenceActorNonFiniteLocatorGuardTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(SchemaV9.models),
                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func nonFinite(_ fp: DocumentFingerprint) -> Locator {
        Locator(bookFingerprint: fp, href: "ch1.xhtml", progression: .infinity, totalProgression: .infinity,
                cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                charRangeEndUTF16: nil, textQuote: "broken", textContextBefore: nil, textContextAfter: nil)
    }

    @Test func addHighlightRepairsNonFiniteLocator() async throws {
        let c = try container()
        let persistence = PersistenceActor(modelContainer: c)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!

        let rec = try await persistence.addHighlight(
            locator: nonFinite(fp), selectedText: "x", color: "yellow", note: nil, toBookWithKey: key)
        #expect(rec.locator.validate() == nil)
        #expect(rec.locator.progression == nil)

        let stored = try #require(try ModelContext(c).fetch(FetchDescriptor<Highlight>()).first)
        #expect(stored.locator.validate() == nil)
        #expect(stored.locator.progression == nil)
        #expect(stored.locator.textQuote == "broken")   // anchor preserved
        #expect(stored.profileKey == "\(stored.locator.bookFingerprint.canonicalKey):\(stored.locator.canonicalHash)")
    }

    @Test func addBookmarkRepairsNonFiniteLocator() async throws {
        let c = try container()
        let persistence = PersistenceActor(modelContainer: c)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!

        _ = try await persistence.addBookmark(locator: nonFinite(fp), title: "bm", toBookWithKey: key)
        let stored = try #require(try ModelContext(c).fetch(FetchDescriptor<Bookmark>()).first)
        #expect(stored.locator.validate() == nil)
        #expect(stored.locator.progression == nil)
        #expect(stored.profileKey == "\(stored.locator.bookFingerprint.canonicalKey):\(stored.locator.canonicalHash)")
    }

    @Test func addAnnotationRepairsNonFiniteLocator() async throws {
        let c = try container()
        let persistence = PersistenceActor(modelContainer: c)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!

        _ = try await persistence.addAnnotation(locator: nonFinite(fp), content: "note", toBookWithKey: key)
        let stored = try #require(try ModelContext(c).fetch(FetchDescriptor<AnnotationNote>()).first)
        #expect(stored.locator.validate() == nil)
        #expect(stored.locator.progression == nil)
        #expect(stored.profileKey == "\(stored.locator.bookFingerprint.canonicalKey):\(stored.locator.canonicalHash)")
    }

    @Test func savePositionRepairsNonFiniteLocator() async throws {
        let c = try container()
        let persistence = PersistenceActor(modelContainer: c)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!

        try await persistence.savePosition(bookFingerprintKey: key, locator: nonFinite(fp), deviceId: "test")
        let stored = try #require(try ModelContext(c).fetch(FetchDescriptor<ReadingPosition>()).first)
        #expect(stored.locator.validate() == nil)
        #expect(stored.locator.progression == nil)
        #expect(stored.locatorHash == stored.locator.canonicalHash)
    }
}
