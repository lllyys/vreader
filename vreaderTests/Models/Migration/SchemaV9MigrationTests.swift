// Purpose: Tests for SchemaV9 migration — adds the additive ChatSession @Model
// entity + the new to-many Book.chatSessions cascade relationship (Feature #88,
// WI-1). Purely-additive (a new entity + a new to-many relationship), so
// SwiftData's implicit lightweight migration applies and the explicit stages
// list stays empty. The V8→V9 round-trip on a POPULATED store asserts existing
// rows survive AND a ChatSession can attach to a Book AND book-delete cascades.
//
// @coordinates-with: SchemaV8.swift, SchemaV9.swift, ChatSession.swift,
//   Book.swift, dev-docs/plans/20260605-feature-88-conversation-sessions.md (WI-1)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("SchemaV9Migration")
struct SchemaV9MigrationTests {

    // MARK: - SchemaV9 structure

    @Test func schemaV9VersionIsNineZeroZero() {
        #expect(SchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
    }

    @Test func schemaV9AddsChatSessionToV8ModelSet() {
        let v9Names = Set(SchemaV9.models.map { String(describing: $0) })
        let v8Names = Set(SchemaV8.models.map { String(describing: $0) })
        // V9 = V8's set ∪ { ChatSession }, nothing removed.
        #expect(v9Names == v8Names.union(["ChatSession"]))
        #expect(v9Names.contains("ChatSession"))
    }

    @Test func migrationPlanIncludesV9AsLast() {
        let last = VReaderMigrationPlan.schemas.last
        #expect(last != nil)
        #expect(String(describing: last!) == String(describing: SchemaV9.self))
    }

    @Test func migrationPlanLengthIsNine() {
        #expect(VReaderMigrationPlan.schemas.count == 9)
    }

    @Test func migrationPlanHasNoExplicitStages() {
        // V8→V9 adds a new entity + a new to-many relationship — implicit
        // lightweight migration, no explicit stage required.
        #expect(VReaderMigrationPlan.stages.isEmpty)
    }

    // MARK: - V8 populated store survives migration to V9

    @Test func migratingPopulatedV8StoreOpensUnderV9AndPreservesRows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v8v9-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("store.sqlite")

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 4096,
            format: .epub
        )
        let provenance = ImportProvenance(
            source: .filesApp,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalURLBookmarkData: nil
        )
        let locator = Locator(
            bookFingerprint: fp, href: "ch1.xhtml",
            progression: 0.2, totalProgression: 0.4,
            cfi: nil, page: nil,
            charOffsetUTF16: 50, charRangeStartUTF16: 50, charRangeEndUTF16: 80,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        // Populate a V8 store: Book + Highlight + Bookmark.
        do {
            let v8 = try ModelContainer(
                for: Schema(SchemaV8.models),
                configurations: [ModelConfiguration(url: storeURL)]
            )
            let ctx = ModelContext(v8)
            let book = Book(fingerprint: fp, title: "Moby-Dick", provenance: provenance)
            let highlight = Highlight(locator: locator, selectedText: "Call me Ishmael")
            let bookmark = Bookmark(locator: locator, title: "Opening")
            book.highlights.append(highlight)
            book.bookmarks.append(bookmark)
            ctx.insert(book)
            try ctx.save()
        }

        // Reopen under V9 with the migration plan.
        let v9 = try ModelContainer(
            for: Schema(SchemaV9.models),
            migrationPlan: VReaderMigrationPlan.self,
            configurations: [ModelConfiguration(url: storeURL)]
        )
        let ctx = ModelContext(v9)

        // Existing rows survive intact.
        let books = try ctx.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        let migratedBook = try #require(books.first)
        #expect(migratedBook.title == "Moby-Dick")
        #expect(migratedBook.highlights.count == 1)
        #expect(migratedBook.highlights.first?.selectedText == "Call me Ishmael")
        #expect(migratedBook.bookmarks.count == 1)
        #expect(migratedBook.bookmarks.first?.title == "Opening")
        // New to-many relationship defaults to empty for migrated books.
        #expect(migratedBook.chatSessions.isEmpty)

        // A ChatSession can be inserted attached to the migrated Book.
        let session = ChatSession(
            bookFingerprintKey: fp.canonicalKey,
            title: "First conversation",
            messages: [ChatMessage(role: .user, content: "Hi")]
        )
        migratedBook.chatSessions.append(session)
        ctx.insert(session)
        try ctx.save()

        let sessions = try ctx.fetch(FetchDescriptor<ChatSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.bookFingerprintKey == fp.canonicalKey)
        #expect(sessions.first?.book?.fingerprintKey == fp.canonicalKey)
    }

    // MARK: - Book-delete cascades to its ChatSessions

    @Test func deletingBookCascadeDeletesChatSessions() throws {
        let schema = Schema(SchemaV9.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "c", count: 64),
            fileByteCount: 2048,
            format: .txt
        )
        let provenance = ImportProvenance(
            source: .filesApp,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalURLBookmarkData: nil
        )
        let book = Book(fingerprint: fp, title: "Cascade Book", provenance: provenance)
        let session = ChatSession(
            bookFingerprintKey: fp.canonicalKey,
            title: "Doomed conversation",
            messages: [ChatMessage(role: .user, content: "Bye")]
        )
        book.chatSessions.append(session)
        ctx.insert(book)
        ctx.insert(session)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<ChatSession>()).count == 1)

        ctx.delete(book)
        try ctx.save()

        // The cascade rule on Book.chatSessions removes the session.
        #expect(try ctx.fetch(FetchDescriptor<ChatSession>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Book>()).isEmpty)
    }
}
