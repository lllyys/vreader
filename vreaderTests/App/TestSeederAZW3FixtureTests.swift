// Purpose: Tests for Bug #233 / GH #964's `TestSeeder.seedMiniAZW3()` seed —
// a single real, openable AZW3 book (the bundled `mini-azw3.azw3`, Project
// Gutenberg #1064) so the XCUITest harness can open a Foliate-rendered book
// from the standard `launchApp(seed:)` path. Mirrors `seedMiniEPUB` (Bug #214
// / GH #834): the `.books` seed's AZW3 fixtures (if any) are metadata-only and
// never open, so AZW3 reader-screen verification needs its own real-file seed.
//
// The load-bearing assertion runs the LIVE `seedMiniAZW3` against a disposable
// in-memory SwiftData store and reads the persisted `BookRecord` back —
// proving the seed actually inserts a book whose `format` is `azw3` and whose
// canonical key is distinct from the EPUB fixture's.

import Testing
import Foundation
import SwiftData
@testable import vreader

#if DEBUG

@Suite("TestSeeder.seedMiniAZW3")
struct TestSeederAZW3FixtureTests {

    /// The seed inserts exactly one book and that book's persisted format is
    /// `azw3` — the property the Foliate reader path keys on. If the bundled
    /// `mini-azw3.azw3` resource is missing the seed logs a warning and
    /// inserts nothing; `test_all_entriesResolveInTheTestBundle` in
    /// `DebugFixtureCatalogTests` is the companion gate that the resource is
    /// actually present in the DEBUG test bundle.
    @Test func seedMiniAZW3InsertsOneOpenableAZW3Book() async throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)

        await TestSeeder.seedMiniAZW3(persistence: persistence)

        let books = try await persistence.fetchAllLibraryBooks()
        #expect(books.count == 1,
                "seedMiniAZW3 should insert exactly one book, got \(books.count)")

        let book = try #require(books.first)
        // `LibraryBookItem.format` is the raw `BookFormat` string; the AZW3
        // fixture must persist as `azw3` so the reader dispatcher routes it
        // to the Foliate host.
        #expect(book.format == BookFormat.azw3.rawValue,
                "seeded book format should be azw3, got \(book.format)")
    }

    /// The AZW3 fixture seed and the EPUB fixture seed must produce distinct
    /// `DocumentFingerprint.canonicalKey`s when both are live-seeded — a
    /// shared hash literal or identical (format, byteCount) pair would let
    /// one seed's book collide with the other's. Mirrors the
    /// `seedMDMultiPage` ⇄ `seedMDWithTOC` distinctness gate.
    @Test func seedMiniAZW3AndSeedMiniEPUBProduceDistinctCanonicalKeys() async throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)

        await TestSeeder.seedMiniEPUB(persistence: persistence)
        let epubBooks = try await persistence.fetchAllLibraryBooks()
        let epubKey = epubBooks.first?.fingerprintKey
        #expect(epubKey != nil)

        await TestSeeder.seedMiniAZW3(persistence: persistence)
        let azw3Books = try await persistence.fetchAllLibraryBooks()
        let azw3Key = azw3Books.first?.fingerprintKey
        #expect(azw3Key != nil)

        #expect(epubKey != azw3Key,
                "seedMiniEPUB and seedMiniAZW3 produced identical canonicalKey '\(epubKey ?? "nil")' — distinctness regression")
    }

    /// `ImportedBooks/` — the directory `seedMiniAZW3` writes its backing
    /// file into. The file's basename is the persisted `fingerprintKey`
    /// with `:` replaced by `_` (reconstructed in the test from the live
    /// key); this helper only supplies the parent directory.
    private static func importedBooksDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
    }

    /// The seed writes a real backing file to disk under
    /// `ImportedBooks/<canonicalKey-with-colons-as-underscores>.azw3`. The
    /// Foliate reader resolves the file from the persisted `fingerprintKey`,
    /// so without this file an AZW3 row would exist but never open —
    /// recreating the failure mode the seed is meant to avoid (Codex Gate-4
    /// Medium). The test deletes any stale fixture file FIRST so it proves
    /// the CURRENT seed wrote the file — `clearAllBooks` only deletes
    /// SwiftData rows, not `ImportedBooks/` files, so a leftover file from a
    /// prior run would otherwise mask a write-path regression (Codex Gate-4
    /// round-2 Medium).
    @Test func seedMiniAZW3WritesBackingFileToDisk() async throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)

        // Seed once to learn the deterministic file path, then delete the
        // file and re-seed — the post-delete re-seed is what the assertion
        // actually proves.
        await TestSeeder.seedMiniAZW3(persistence: persistence)
        let firstBooks = try await persistence.fetchAllLibraryBooks()
        let firstBook = try #require(firstBooks.first, "seedMiniAZW3 should insert a book")
        let safeName = firstBook.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let filePath = Self.importedBooksDirectory()
            .appendingPathComponent(safeName)
            .appendingPathExtension("azw3")

        // Remove any file the seed (or a prior test run) wrote, so the next
        // assertion can only pass if the re-seed re-creates it.
        try? FileManager.default.removeItem(at: filePath)
        #expect(!FileManager.default.fileExists(atPath: filePath.path),
                "precondition: fixture file should be absent before re-seed")

        await TestSeeder.seedMiniAZW3(persistence: persistence)

        #expect(FileManager.default.fileExists(atPath: filePath.path),
                "seedMiniAZW3 should write a backing file at \(filePath.path)")
    }

    /// The seed clears any pre-existing library state before inserting, so a
    /// prior seed's books don't leak into the AZW3-fixture launch. Mirrors
    /// `seedMiniEPUB`'s leading `clearAllBooks`.
    @Test func seedMiniAZW3ClearsPriorBooksFirst() async throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)

        // Seed a different fixture first, then the AZW3 fixture.
        await TestSeeder.seedBooks(persistence: persistence)
        let before = try await persistence.fetchAllLibraryBooks()
        #expect(before.count > 1, "seedBooks should populate multiple books")

        await TestSeeder.seedMiniAZW3(persistence: persistence)
        let after = try await persistence.fetchAllLibraryBooks()
        #expect(after.count == 1,
                "seedMiniAZW3 should clear prior books and leave exactly one, got \(after.count)")
        #expect(after.first?.format == BookFormat.azw3.rawValue)
    }
}

#endif
