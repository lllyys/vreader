// Purpose: Tests for the feature #109 one-shot launch backfill that recomputes
// derived locator keys (Highlight/Bookmark/AnnotationNote profileKey,
// ReadingPosition locatorHash) under NFC canonicalization (bug #356) and repairs
// preexisting invalid (non-finite) locators. The backfill replaces a SwiftData
// migration stage, which cannot fire for a schema-identical data transform.
//
// @coordinates-with: LocatorKeyBackfillMigration.swift, Locator.swift,
//   {Highlight,Bookmark,AnnotationNote,ReadingPosition}.swift, SchemaV1.swift
//   (VReaderMigrationPlan)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("LocatorKeyBackfillMigration")
struct LocatorKeyBackfillMigrationTests {

    // MARK: - Helpers

    private func freshDefaults() -> UserDefaults {
        // A throwaway suite so the gate flag never leaks across tests / into
        // the real app domain.
        UserDefaults(suiteName: "backfill-test-\(UUID().uuidString)")!
    }

    private func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SchemaV9.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private static let fp = DocumentFingerprint(
        contentSHA256: String(repeating: "c", count: 64), fileByteCount: 4096, format: .epub
    )

    private func ascii() -> Locator {
        Locator(bookFingerprint: Self.fp, href: "ch1.xhtml", progression: 0.2, totalProgression: 0.4,
                cfi: nil, page: nil, charOffsetUTF16: 50, charRangeStartUTF16: 50, charRangeEndUTF16: 80,
                textQuote: "plain ascii", textContextBefore: nil, textContextAfter: nil)
    }
    private func nfd() -> Locator {
        Locator(bookFingerprint: Self.fp, href: "ch2.xhtml", progression: 0.6, totalProgression: 0.6,
                cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                charRangeEndUTF16: nil, textQuote: "cafe\u{0301}", textContextBefore: nil, textContextAfter: nil)
    }
    private func nonFinite() -> Locator {
        Locator(bookFingerprint: Self.fp, href: "ch3.xhtml", progression: .infinity, totalProgression: .infinity,
                cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                charRangeEndUTF16: nil, textQuote: "broken", textContextBefore: nil, textContextAfter: nil)
    }

    // MARK: - Plan no longer carries a custom stage (#109 pivot)

    @Test func migrationPlanStaysAtV9WithNoCustomStage() {
        #expect(VReaderMigrationPlan.schemas.count == 9)
        #expect(String(describing: VReaderMigrationPlan.schemas.last!) == String(describing: SchemaV9.self))
        #expect(VReaderMigrationPlan.stages.isEmpty)
    }

    // MARK: - Value-level recompute / repair

    @Test func repairedForCanonicalizationNullsNonFiniteAndValidates() {
        for bad in [Double.infinity, -Double.infinity, Double.nan] {
            let invalid = Locator(
                bookFingerprint: Self.fp, href: "x.html", progression: bad, totalProgression: bad,
                cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                charRangeEndUTF16: nil, textQuote: "q", textContextBefore: nil, textContextAfter: nil
            )
            #expect(invalid.validate() == .nonFiniteProgression)
            let repaired = invalid.repairedForCanonicalization()
            #expect(repaired.validate() == nil)
            #expect(repaired.progression == nil)
            #expect(repaired.totalProgression == nil)
            #expect(repaired.textQuote == "q")   // anchor preserved
            #expect(repaired.href == "x.html")
        }
    }

    @Test func recomputeKeyIsConsistentWithCanonicalHash() {
        let h = Highlight(locator: nfd(), selectedText: "x")
        h.recomputeKey()
        #expect(h.profileKey == "\(h.locator.bookFingerprint.canonicalKey):\(h.locator.canonicalHash)")
        // The NFC form equals the precomposed twin's hash.
        let twin = Locator(bookFingerprint: Self.fp, href: "ch2.xhtml", progression: 0.6, totalProgression: 0.6,
                           cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                           charRangeEndUTF16: nil, textQuote: "caf\u{00e9}", textContextBefore: nil, textContextAfter: nil)
        #expect(nfd().canonicalHash == twin.canonicalHash)
    }

    // MARK: - Backfill over a populated store

    @Test func backfillRecomputesAllKeysAndRepairsNonFinite() throws {
        let container = try inMemoryContainer()
        let defaults = freshDefaults()
        let nonFiniteLoc = nonFinite()
        #expect(nonFiniteLoc.validate() == .nonFiniteProgression)   // invalid at seed

        let seed = ModelContext(container)
        let book = Book(fingerprint: Self.fp, title: "Moby-Dick",
                        provenance: ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1), originalURLBookmarkData: nil))
        book.highlights.append(Highlight(locator: ascii(), selectedText: "ascii"))
        book.highlights.append(Highlight(locator: nfd(), selectedText: "nfd"))
        book.highlights.append(Highlight(locator: nonFiniteLoc, selectedText: "nonfinite"))
        book.bookmarks.append(Bookmark(locator: ascii(), title: "bm"))
        let pos = ReadingPosition(locator: nfd())
        book.readingPosition = pos
        seed.insert(book); seed.insert(pos)
        try seed.save()

        LocatorKeyBackfillMigration.run(container: container, defaults: defaults)

        let ctx = ModelContext(container)
        let highlights = try ctx.fetch(FetchDescriptor<Highlight>())
        #expect(highlights.count == 3)   // no row dropped
        for h in highlights {
            #expect(h.profileKey == "\(h.locator.bookFingerprint.canonicalKey):\(h.locator.canonicalHash)")
            #expect(h.locator.validate() == nil)   // every row valid post-backfill
        }
        // NFD text preserved verbatim in the stored locator.
        #expect(highlights.contains { $0.locator.textQuote == "cafe\u{0301}" })
        // The seeded non-finite locator was REPAIRED in place (genuine stored change).
        let repaired = try #require(highlights.first { $0.selectedText == "nonfinite" })
        #expect(repaired.locator.progression == nil)
        #expect(repaired.locator.totalProgression == nil)
        #expect(repaired.locator.textQuote == "broken")   // anchor preserved

        let positions = try ctx.fetch(FetchDescriptor<ReadingPosition>())
        #expect(positions.count == 1)
        #expect(positions.first?.locatorHash == positions.first?.locator.canonicalHash)

        // Gate flag set after a successful run.
        #expect(defaults.bool(forKey: LocatorKeyBackfillMigration.completionFlagKey) == true)
    }

    @Test func backfillIsGatedByCompletionFlag() throws {
        let container = try inMemoryContainer()
        let defaults = freshDefaults()
        // Preset the flag → the backfill must NOT touch the store.
        defaults.set(true, forKey: LocatorKeyBackfillMigration.completionFlagKey)

        let seed = ModelContext(container)
        let book = Book(fingerprint: Self.fp, title: "X",
                        provenance: ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1), originalURLBookmarkData: nil))
        book.highlights.append(Highlight(locator: nonFinite(), selectedText: "nonfinite"))
        seed.insert(book)
        try seed.save()

        LocatorKeyBackfillMigration.run(container: container, defaults: defaults)

        let ctx = ModelContext(container)
        let h = try #require(try ctx.fetch(FetchDescriptor<Highlight>()).first)
        // Gate held → the invalid locator was left untouched (not repaired).
        #expect(h.locator.progression?.isInfinite == true)
    }

    @Test func backfillOverPersistedStoreAcrossRelaunch() throws {
        // Disk-backed: prove the real launch-on-reopen path repairs a PERSISTED
        // row and the gate behaves across a simulated relaunch (fresh container
        // each "launch", same store file).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backfill-disk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("store.sqlite")
        let defaults = freshDefaults()   // persists across the simulated relaunches

        // Launch 1: seed a persisted store, then nothing else (no backfill yet).
        do {
            let c = try ModelContainer(for: Schema(SchemaV9.models),
                                       configurations: [ModelConfiguration(url: storeURL)])
            let ctx = ModelContext(c)
            let book = Book(fingerprint: Self.fp, title: "Persisted",
                            provenance: ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1), originalURLBookmarkData: nil))
            book.highlights.append(Highlight(locator: nonFinite(), selectedText: "nonfinite"))
            book.highlights.append(Highlight(locator: nfd(), selectedText: "nfd"))
            ctx.insert(book)
            try ctx.save()
        }

        // Launch 2 (app update): reopen a FRESH container + run the launch backfill.
        do {
            let c = try ModelContainer(for: Schema(SchemaV9.models),
                                       configurations: [ModelConfiguration(url: storeURL)])
            LocatorKeyBackfillMigration.run(container: c, defaults: defaults)
            let ctx = ModelContext(c)
            let highlights = try ctx.fetch(FetchDescriptor<Highlight>())
            #expect(highlights.count == 2)
            let repaired = try #require(highlights.first { $0.selectedText == "nonfinite" })
            #expect(repaired.locator.validate() == nil)
            #expect(repaired.locator.progression == nil)
            for h in highlights {
                #expect(h.profileKey == "\(h.locator.bookFingerprint.canonicalKey):\(h.locator.canonicalHash)")
            }
            #expect(defaults.bool(forKey: LocatorKeyBackfillMigration.completionFlagKey) == true)
        }

        // Launch 3 (normal relaunch): gate is set → no-op, rows untouched.
        do {
            let c = try ModelContainer(for: Schema(SchemaV9.models),
                                       configurations: [ModelConfiguration(url: storeURL)])
            LocatorKeyBackfillMigration.run(container: c, defaults: defaults)
            let ctx = ModelContext(c)
            let highlights = try ctx.fetch(FetchDescriptor<Highlight>())
            #expect(highlights.count == 2)
            #expect(highlights.allSatisfy { $0.locator.validate() == nil })
        }
    }

    @Test func backfillIsIdempotent() throws {
        let container = try inMemoryContainer()
        let defaults = freshDefaults()

        let seed = ModelContext(container)
        let book = Book(fingerprint: Self.fp, title: "X",
                        provenance: ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1), originalURLBookmarkData: nil))
        book.highlights.append(Highlight(locator: nfd(), selectedText: "nfd"))
        seed.insert(book)
        try seed.save()

        LocatorKeyBackfillMigration.run(container: container, defaults: defaults)
        let firstKey = try #require(try ModelContext(container).fetch(FetchDescriptor<Highlight>()).first).profileKey
        // Second run is a no-op (flag set); keys unchanged.
        LocatorKeyBackfillMigration.run(container: container, defaults: defaults)
        let secondKey = try #require(try ModelContext(container).fetch(FetchDescriptor<Highlight>()).first).profileKey
        #expect(firstKey == secondKey)
    }
}
