// Purpose: Round-trip tests for BackupDataCollector + BackupDataRestorer.
// Exercises every section produced by the collector against a real in-memory
// PersistenceActor + isolated UserDefaults + temp PerBookSettings dir.
//
// @coordinates-with: BackupDataCollector.swift, BackupDataRestorer.swift,
//   PersistenceActor+Backup.swift, WebDAVProvider.swift

import Testing
import Foundation
import SwiftData
@testable import vreader

// MARK: - Library Manifest collection (feature #46 WI-6)

@Suite("BackupDataCollector — collectLibraryManifest (feature #46 WI-6)")
struct BackupDataCollectorLibraryManifestTests {

    private func makeCollector(persistence: PersistenceActor) -> BackupDataCollector {
        BackupDataCollector(
            persistence: persistence,
            defaults: UserDefaults(suiteName: "manifest-test-\(UUID().uuidString)")!,
            perBookSettingsBaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pbs-\(UUID().uuidString)", isDirectory: true)
        )
    }

    @Test func emptyLibrary_emitsEmptyManifest() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let collector = makeCollector(persistence: persistence)
        let data = try await collector.collectLibraryManifest()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.books.isEmpty)
    }

    @Test func multipleBooks_emitsOneEntryPerBook_withCorrectBlobPath() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let collector = makeCollector(persistence: persistence)
        let key1 = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Alice",
            sha: String(repeating: "a", count: 64),
            byteCount: 1024
        )
        let key2 = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "MOBI Book",
            sha: String(repeating: "b", count: 64),
            byteCount: 4096
        )

        let data = try await collector.collectLibraryManifest()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
        #expect(envelope.books.count == 2)
        let keys = envelope.books.map(\.fingerprintKey)
        #expect(keys == keys.sorted())
        #expect(Set(keys) == Set([key1, key2]))
        for entry in envelope.books {
            guard let format = BookFormat(rawValue: entry.format) else {
                Issue.record("unknown format \(entry.format)")
                continue
            }
            let expected = BlobPath.make(format: format, sha256: entry.sha256, byteCount: entry.byteCount)
            #expect(entry.blobPath == expected)
        }
    }

    @Test func mobiBook_preservesOriginalExtensionInManifest() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let collector = makeCollector(persistence: persistence)
        let sha = String(repeating: "c", count: 64)
        let fp = DocumentFingerprint(contentSHA256: sha, fileByteCount: 8192, format: .azw3)
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "Old Kindle Book",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date(),
            originalExtension: "mobi"
        )
        _ = try await persistence.insertBook(record)
        let data = try await collector.collectLibraryManifest()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
        #expect(envelope.books.count == 1)
        #expect(envelope.books[0].originalExtension == "mobi")
        #expect(envelope.books[0].format == "azw3")
    }
}

@Suite("BackupDataCollector + BackupDataRestorer")
struct BackupCollectorRestorerSuite {

    // MARK: - Fixture builders

    private static let suiteCounter = Atomic<Int>(0)
    private static let testCounter = Atomic<Int>(0)

    /// Creates an isolated SchemaV4 in-memory ModelContainer.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV4.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePersistence() throws -> PersistenceActor {
        PersistenceActor(modelContainer: try makeContainer())
    }

    /// Returns both the container and a persistence actor wrapping it, so tests
    /// can do raw ModelContext queries without crossing the actor boundary.
    private func makePersistenceAndContainer() throws -> (ModelContainer, PersistenceActor) {
        let container = try makeContainer()
        return (container, PersistenceActor(modelContainer: container))
    }

    /// Builds a Locator for the given fingerprint with optional EPUB href/progression.
    private func makeLocator(
        fingerprint: DocumentFingerprint,
        href: String? = nil,
        progression: Double? = nil
    ) -> Locator {
        Locator.validated(
            bookFingerprint: fingerprint,
            href: href,
            progression: progression
        )!
    }

    /// Per-test isolated UserDefaults using a unique suite name.
    private func makeIsolatedDefaults(label: String) -> UserDefaults {
        let id = Self.suiteCounter.incrementAndGet()
        let suite = "vreader.backup.test.\(label).\(id).\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    /// Per-test temp dir for PerBookSettingsStore.
    private func makeTempDir(label: String) throws -> URL {
        let id = Self.testCounter.incrementAndGet()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vreader-backup-tests-\(label)-\(id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFingerprint(
        sha: String = String(repeating: "a", count: 64),
        byteCount: Int64 = 1024,
        format: BookFormat = .epub
    ) -> DocumentFingerprint {
        DocumentFingerprint(contentSHA256: sha, fileByteCount: byteCount, format: format)
    }

    private func insertBook(
        _ persistence: PersistenceActor,
        title: String = "Test Book",
        sha: String = String(repeating: "a", count: 64)
    ) async throws -> DocumentFingerprint {
        let fp = makeFingerprint(sha: sha)
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: title,
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: ImportProvenance(
                source: .filesApp,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: nil
            ),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)
        return fp
    }

    // MARK: - Settings

    @Test func settingsRoundTrips() async throws {
        let defaultsA = makeIsolatedDefaults(label: "settingsA")
        let defaultsB = makeIsolatedDefaults(label: "settingsB")

        defaultsA.set("dark", forKey: "readerTheme")
        defaultsA.set(true, forKey: "readerAutoPageTurn")
        defaultsA.set(7.5, forKey: "readerAutoPageTurnInterval")
        let typographyData = "{\"fontSize\":18}".data(using: .utf8)!
        defaultsA.set(typographyData, forKey: "readerTypography")

        let persistence = try makePersistence()
        let perBookDir = try makeTempDir(label: "settings")
        let collector = BackupDataCollector(
            persistence: persistence, defaults: defaultsA, perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectSettings()

        let restorer = BackupDataRestorer(
            persistence: persistence, defaults: defaultsB, perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreSettings(from: data)

        #expect(defaultsB.string(forKey: "readerTheme") == "dark")
        #expect(defaultsB.bool(forKey: "readerAutoPageTurn") == true)
        #expect(defaultsB.double(forKey: "readerAutoPageTurnInterval") == 7.5)
        #expect(defaultsB.data(forKey: "readerTypography") == typographyData)
    }

    @Test func settingsSkipsUnknownKeys() async throws {
        let defaultsA = makeIsolatedDefaults(label: "settingsUnknownA")
        let defaultsB = makeIsolatedDefaults(label: "settingsUnknownB")

        defaultsA.set("dark", forKey: "readerTheme")
        defaultsA.set("malicious", forKey: "someUnrelatedAppKey")

        let persistence = try makePersistence()
        let perBookDir = try makeTempDir(label: "settings-unknown")
        let collector = BackupDataCollector(
            persistence: persistence, defaults: defaultsA, perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectSettings()

        let restorer = BackupDataRestorer(
            persistence: persistence, defaults: defaultsB, perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreSettings(from: data)

        #expect(defaultsB.string(forKey: "readerTheme") == "dark")
        #expect(defaultsB.string(forKey: "someUnrelatedAppKey") == nil)
    }

    /// Feature #54 WI-5: `readerReadingMode` is no longer in
    /// `BackupSettingsKeys.all` — new backups stop snapshotting the
    /// retired key.
    @Test func settingsKeys_doNotIncludeRetiredReadingModeKey() {
        #expect(
            !BackupSettingsKeys.all.contains("readerReadingMode"),
            "feature #54 WI-5 removed `readerReadingMode` from BackupSettingsKeys.all"
        )
    }

    /// Feature #54 WI-5: restoring an OLD backup whose settings section
    /// still carries `readerReadingMode` must not crash. `restoreSettings`
    /// iterates whatever `defaults` dictionary the archive captured (it is
    /// NOT filtered against the current `BackupSettingsKeys.all`), so the
    /// orphan key faithfully lands in UserDefaults. The next launch's
    /// `ReadingModeMigration.run` is what clears it (covered by
    /// `ReadingModeMigrationTests`).
    ///
    /// The fixture is hand-built as a pre-#54 `BackupSettingsEnvelope`
    /// rather than produced by the current collector: WI-5 removed
    /// `readerReadingMode` from `BackupSettingsKeys.all`, so `collectSettings()`
    /// can no longer emit it — only a hand-crafted old payload exercises
    /// the stale-key restore path.
    @Test func settingsRestore_oldBackupWithReadingMode_doesNotCrash() async throws {
        let defaultsB = makeIsolatedDefaults(label: "oldRMB")

        // Pre-#54 archive: `defaults` includes the retired `readerReadingMode`
        // key alongside a current key. Built directly, not via the collector.
        let oldEnvelope = BackupSettingsEnvelope(
            schemaVersion: 1,
            defaults: [
                "readerTheme": .string("dark"),
                "readerReadingMode": .string("unified"),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(oldEnvelope)

        let persistence = try makePersistence()
        let restorer = BackupDataRestorer(
            persistence: persistence,
            defaults: defaultsB,
            perBookSettingsBaseURL: try makeTempDir(label: "old-rm")
        )
        // Must not throw — restoreSettings replays every key the archive holds.
        try await restorer.restoreSettings(from: data)
        #expect(defaultsB.string(forKey: "readerTheme") == "dark")
        // The restorer does not drop the retired key — it writes through what
        // the old archive carried. `ReadingModeMigration` (run at next launch)
        // is the component that removes it; the restore step just tolerates it.
        #expect(defaultsB.string(forKey: "readerReadingMode") == "unified")
    }

    // MARK: - Annotations (highlights / bookmarks / notes)

    @Test func annotationsRoundTrip() async throws {
        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "Source Book")
        let key = fp.canonicalKey
        let locator = makeLocator(fingerprint: fp, href: "chapter-1.xhtml", progression: 0.42)

        let highlight = try await sourcePersistence.addHighlight(
            locator: locator,
            selectedText: "selected passage",
            color: "yellow",
            note: "interesting bit",
            toBookWithKey: key
        )
        let bookmark = try await sourcePersistence.addBookmark(
            locator: locator,
            title: "Important page",
            toBookWithKey: key
        )
        let note = try await sourcePersistence.addAnnotation(
            locator: locator,
            content: "note body",
            toBookWithKey: key
        )

        let perBookDir = try makeTempDir(label: "ann")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "annA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectAnnotations()

        // Restore into a fresh persistence with the same book
        let destPersistence = try makePersistence()
        _ = try await insertBook(destPersistence, title: "Source Book")
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "annB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreAnnotations(from: data)

        let restoredHighlights = try await destPersistence.fetchHighlights(forBookWithKey: key)
        let restoredBookmarks = try await destPersistence.fetchBookmarks(forBookWithKey: key)
        let restoredNotes = try await destPersistence.fetchAnnotations(forBookWithKey: key)

        #expect(restoredHighlights.count == 1)
        #expect(restoredHighlights.first?.selectedText == "selected passage")
        #expect(restoredHighlights.first?.note == "interesting bit")
        #expect(restoredBookmarks.count == 1)
        #expect(restoredBookmarks.first?.title == "Important page")
        #expect(restoredNotes.count == 1)
        #expect(restoredNotes.first?.content == "note body")
        // Sanity-check ids exist (not necessarily equal — production addHighlight mints new UUIDs)
        #expect(highlight.highlightId != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
        #expect(bookmark.bookmarkId != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
        #expect(note.annotationId != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
    }

    @Test func annotationsRestorePreservesIdsAndIsIdempotent() async throws {
        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "ID Preservation")
        let key = fp.canonicalKey
        let locator = makeLocator(fingerprint: fp, href: "ch1.xhtml", progression: 0.3)

        let originalHighlight = try await sourcePersistence.addHighlight(
            locator: locator, selectedText: "selected", color: "yellow", note: "note v1", toBookWithKey: key
        )
        let originalNote = try await sourcePersistence.addAnnotation(
            locator: locator, content: "preserved note", toBookWithKey: key
        )

        let perBookDir = try makeTempDir(label: "ann-ids")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "annIdsA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectAnnotations()

        let destPersistence = try makePersistence()
        _ = try await insertBook(destPersistence, title: "ID Preservation")
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "annIdsB"),
            perBookSettingsBaseURL: perBookDir
        )

        // First restore — exercises the insert branch.
        try await restorer.restoreAnnotations(from: data)
        let firstHighlights = try await destPersistence.fetchHighlights(forBookWithKey: key)
        let firstNotes = try await destPersistence.fetchAnnotations(forBookWithKey: key)
        #expect(firstHighlights.count == 1)
        #expect(firstNotes.count == 1)
        #expect(firstHighlights.first?.highlightId == originalHighlight.highlightId)
        #expect(firstHighlights.first?.color == "yellow")
        #expect(firstHighlights.first?.note == "note v1")
        #expect(firstHighlights.first?.selectedText == "selected")
        #expect(firstNotes.first?.annotationId == originalNote.annotationId)
        #expect(firstNotes.first?.content == "preserved note")

        // Second restore — exercises the UUID-match update branch.
        // Should remain idempotent and the row's fields should still match the archive.
        try await restorer.restoreAnnotations(from: data)
        let secondHighlights = try await destPersistence.fetchHighlights(forBookWithKey: key)
        let secondNotes = try await destPersistence.fetchAnnotations(forBookWithKey: key)
        #expect(secondHighlights.count == 1, "Restore should be idempotent for highlights")
        #expect(secondNotes.count == 1, "Restore should be idempotent for notes")
        #expect(secondHighlights.first?.highlightId == originalHighlight.highlightId)
        #expect(secondHighlights.first?.note == "note v1")
        #expect(secondNotes.first?.content == "preserved note")
    }

    @Test func annotationsRestoreDedupesByLocationAcrossDifferentUUID() async throws {
        // Arrange: source produces a highlight at a given location; dest already
        // has a *different-UUID* highlight at the same location (e.g. user
        // re-highlighted on the new device before restoring). The restore
        // should overwrite the local row with the backup's UUID/payload, not
        // create a second highlight at the same anchor.
        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "Same Location")
        let key = fp.canonicalKey
        let locator = makeLocator(fingerprint: fp, href: "ch1.xhtml", progression: 0.5)

        let backedUpHighlight = try await sourcePersistence.addHighlight(
            locator: locator, selectedText: "x", color: "yellow", note: "from backup", toBookWithKey: key
        )

        let perBookDir = try makeTempDir(label: "ann-prof")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "profA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectAnnotations()

        let destPersistence = try makePersistence()
        _ = try await insertBook(destPersistence, title: "Same Location")
        // Dest has its own pre-existing highlight at the same location with a
        // different UUID and different payload.
        let localHighlight = try await destPersistence.addHighlight(
            locator: locator, selectedText: "x", color: "blue", note: "local note", toBookWithKey: key
        )
        #expect(localHighlight.highlightId != backedUpHighlight.highlightId)

        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "profB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreAnnotations(from: data)

        let restored = try await destPersistence.fetchHighlights(forBookWithKey: key)
        #expect(restored.count == 1, "Should not duplicate a highlight at the same location")
        // The surviving row should now carry the backup's payload AND UUID
        // so sync identity tracks the source device.
        #expect(restored.first?.color == "yellow")
        #expect(restored.first?.note == "from backup")
        #expect(restored.first?.highlightId == backedUpHighlight.highlightId)
    }

    @Test func annotationsSkipsMissingBook() async throws {
        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "Will Be Missing")
        let key = fp.canonicalKey
        let locator = makeLocator(fingerprint: fp, href: "ch1", progression: 0.1)
        _ = try await sourcePersistence.addHighlight(
            locator: locator,
            selectedText: "x",
            color: "yellow",
            note: nil,
            toBookWithKey: key
        )

        let perBookDir = try makeTempDir(label: "ann-missing")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "missA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectAnnotations()

        // Dest has NO book — restore should silently skip
        let destPersistence = try makePersistence()
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "missB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreAnnotations(from: data)
        // No assertion beyond "doesn't throw" — skipping missing books is the contract.
    }

    // MARK: - Positions

    @Test func positionsRoundTrip() async throws {
        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "Pos Book")
        let key = fp.canonicalKey
        let locator = makeLocator(fingerprint: fp, href: "chapter-3.xhtml", progression: 0.66)
        try await sourcePersistence.savePosition(
            bookFingerprintKey: key, locator: locator, deviceId: ""
        )

        let perBookDir = try makeTempDir(label: "pos")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "posA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectPositions()

        let destPersistence = try makePersistence()
        _ = try await insertBook(destPersistence, title: "Pos Book")
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "posB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restorePositions(from: data)

        let restored = try await destPersistence.loadPosition(bookFingerprintKey: key)
        #expect(restored?.href == "chapter-3.xhtml")
        #expect(abs((restored?.progression ?? 0) - 0.66) < 0.001)
    }

    // MARK: - Collections

    @Test func collectionsRoundTrip() async throws {
        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "Coll Book")
        let key = fp.canonicalKey
        _ = try await sourcePersistence.createCollection(name: "Sci-Fi")
        try await sourcePersistence.addBookToCollection(
            bookFingerprintKey: key, collectionName: "Sci-Fi"
        )

        let perBookDir = try makeTempDir(label: "coll")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "collA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectCollections()

        let destPersistence = try makePersistence()
        _ = try await insertBook(destPersistence, title: "Coll Book")
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "collB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreCollections(from: data)

        let restored = try await destPersistence.fetchAllCollections()
        #expect(restored.contains { $0.name == "Sci-Fi" })
        let books = try await destPersistence.fetchBooksInCollection(name: "Sci-Fi")
        #expect(books.contains(key))
    }

    // MARK: - Book Sources

    @Test func bookSourcesRoundTrip() async throws {
        let (sourceContainer, sourcePersistence) = try makePersistenceAndContainer()
        // Insert a BookSource directly via ModelContext (no PersistenceActor extension yet).
        let mc = ModelContext(sourceContainer)
        let src = BookSource(
            sourceURL: "https://example.com",
            sourceName: "Example",
            sourceGroup: "Test",
            sourceType: 0,
            enabled: true,
            searchURL: "https://example.com/?q={{key}}",
            header: nil,
            customOrder: 1
        )
        mc.insert(src)
        try mc.save()

        let perBookDir = try makeTempDir(label: "bs")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "bsA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectBookSources()

        let (destContainer, destPersistence) = try makePersistenceAndContainer()
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "bsB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreBookSources(from: data)

        let mcDest = ModelContext(destContainer)
        let restored = try mcDest.fetch(FetchDescriptor<BookSource>())
        #expect(restored.count == 1)
        #expect(restored.first?.sourceURL == "https://example.com")
        #expect(restored.first?.sourceName == "Example")
    }

    // MARK: - Per-book settings

    @Test func perBookSettingsRoundTrip() async throws {
        let perBookDirA = try makeTempDir(label: "pbA")
        let perBookDirB = try makeTempDir(label: "pbB")

        let sourcePersistence = try makePersistence()
        let fp = try await insertBook(sourcePersistence, title: "PB Book")
        let key = fp.canonicalKey

        let override = PerBookSettingsOverride(
            fontSize: 22,
            fontName: "serif",
            lineSpacing: 1.8,
            letterSpacing: nil,
            themeName: "sepia"
        )
        try PerBookSettingsStore.save(override, for: key, baseURL: perBookDirA)

        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "pbA"),
            perBookSettingsBaseURL: perBookDirA
        )
        let data = try await collector.collectPerBookSettings()

        let destPersistence = try makePersistence()
        _ = try await insertBook(destPersistence, title: "PB Book")
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "pbB"),
            perBookSettingsBaseURL: perBookDirB
        )
        try await restorer.restorePerBookSettings(from: data)

        let restored = PerBookSettingsStore.settings(for: key, baseURL: perBookDirB)
        #expect(restored?.fontSize == 22)
        #expect(restored?.fontName == "serif")
        #expect(restored?.lineSpacing == 1.8)
        #expect(restored?.themeName == "sepia")
    }

    // MARK: - Replacement Rules

    @Test func replacementRulesRoundTrip() async throws {
        let (sourceContainer, sourcePersistence) = try makePersistenceAndContainer()
        let mc = ModelContext(sourceContainer)
        let rule = ContentReplacementRule(
            pattern: "foo",
            replacement: "bar",
            isRegex: false,
            scopeKey: "",
            enabled: true,
            order: 1,
            label: "demo rule"
        )
        mc.insert(rule)
        try mc.save()

        let perBookDir = try makeTempDir(label: "rr")
        let collector = BackupDataCollector(
            persistence: sourcePersistence,
            defaults: makeIsolatedDefaults(label: "rrA"),
            perBookSettingsBaseURL: perBookDir
        )
        let data = try await collector.collectReplacementRules()

        let (destContainer, destPersistence) = try makePersistenceAndContainer()
        let restorer = BackupDataRestorer(
            persistence: destPersistence,
            defaults: makeIsolatedDefaults(label: "rrB"),
            perBookSettingsBaseURL: perBookDir
        )
        try await restorer.restoreReplacementRules(from: data)

        let mcDest = ModelContext(destContainer)
        let restored = try mcDest.fetch(FetchDescriptor<ContentReplacementRule>())
        #expect(restored.count == 1)
        #expect(restored.first?.pattern == "foo")
        #expect(restored.first?.replacement == "bar")
        #expect(restored.first?.label == "demo rule")
    }

    // MARK: - Book count

    @Test func bookCountReflectsLibrarySize() async throws {
        let persistence = try makePersistence()
        let collector = BackupDataCollector(
            persistence: persistence,
            defaults: makeIsolatedDefaults(label: "count"),
            perBookSettingsBaseURL: try makeTempDir(label: "count")
        )
        let initialCount = await collector.getBookCount()
        #expect(initialCount == 0)

        _ = try await insertBook(persistence, title: "B1", sha: String(repeating: "a", count: 64))
        _ = try await insertBook(persistence, title: "B2", sha: String(repeating: "b", count: 64))

        let postCount = await collector.getBookCount()
        #expect(postCount == 2)
    }

    // MARK: - Schema version forward compat

    @Test func collectorEmitsCurrentSchemaVersion() async throws {
        // Feature #58 WI-5 bumped kBackupCurrentSchemaVersion 1 → 2. The
        // collector always emits the current version; the restorer accepts
        // both 1 and 2 (kBackupAcceptedSchemaVersions).
        let persistence = try makePersistence()
        let collector = BackupDataCollector(
            persistence: persistence,
            defaults: makeIsolatedDefaults(label: "schema"),
            perBookSettingsBaseURL: try makeTempDir(label: "schema")
        )
        let data = try await collector.collectCollections()
        let envelope = try JSONDecoder().decode(BackupCollectionsEnvelope.self, from: data)
        #expect(envelope.schemaVersion == kBackupCurrentSchemaVersion)
        #expect(envelope.schemaVersion == 2)
    }

    @Test func restorerAcceptsAV1Section() async throws {
        // The v1↔v2 envelope shapes for the pre-#58 sections are byte-identical
        // — a v1-tagged section must still restore after the v2 bump.
        let v1Envelope = BackupCollectionsEnvelope(schemaVersion: 1, collections: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(v1Envelope)

        let persistence = try makePersistence()
        let restorer = BackupDataRestorer(
            persistence: persistence,
            defaults: makeIsolatedDefaults(label: "v1accept"),
            perBookSettingsBaseURL: try makeTempDir(label: "v1accept")
        )
        // Must NOT throw — v1 is in kBackupAcceptedSchemaVersions.
        try await restorer.restoreCollections(from: data)
    }

    @Test func restorerRejectsFutureSchemaVersion() async throws {
        // Hand-craft an envelope claiming schema v999 — restorer must reject it.
        let envelope = BackupCollectionsEnvelope(schemaVersion: 999, collections: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let persistence = try makePersistence()
        let restorer = BackupDataRestorer(
            persistence: persistence,
            defaults: makeIsolatedDefaults(label: "future"),
            perBookSettingsBaseURL: try makeTempDir(label: "future")
        )

        await #expect(throws: BackupRestoreError.self) {
            try await restorer.restoreCollections(from: data)
        }
    }
}

// MARK: - Test-local atomic counter

/// Minimal atomic int for unique suite naming across parallel tests.
final class Atomic<Value>: @unchecked Sendable where Value: Numeric {
    private let lock = NSLock()
    private var value: Value
    init(_ initial: Value) { self.value = initial }
    func incrementAndGet() -> Value {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
