// Purpose: Feature #42 Phase 1 WI-6 — unit tests for the Readium EPUB reader's
// reading-position save/restore mapping + the PersistenceActor envelope-aware
// dual-write/read. Covers (1) the pure `VReaderLocator` ↔ Readium `Locator`
// mapping pair (round-trip, engine tag, lossy legacy leg, edge cases, malformed
// JSON) and (2) the `saveVReaderLocator` / `loadVReaderLocator` round-trip
// through a REAL in-memory `PersistenceActor` (SchemaV8), including the legacy
// `locator` dual-write and the legacy-row (`vreaderLocatorData == nil`) read.
//
// The render itself (UIViewControllerRepresentable hosting
// EPUBNavigatorViewController + the locationDidChange→save wiring) is exercised
// by device verification, not here — these tests pin the testable seams.
//
// @coordinates-with vreader/ViewModels/ReadiumEPUBReaderViewModel.swift,
//   vreader/Models/VReaderLocator.swift,
//   vreader/Services/PersistenceActor+ReadingPosition.swift

import Testing
import Foundation
import SwiftData
import ReadiumShared
@testable import vreader

@Suite("ReadiumEPUBReaderViewModel position mapping (WI-6)")
struct ReadiumEPUBReaderViewModelTests {

    // MARK: - Fixtures

    private func fingerprint(format: BookFormat = .epub) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "e", count: 64),
            fileByteCount: 8192,
            format: format
        )
    }

    /// Builds a Readium `Locator` directly (no render needed) for the mapping
    /// tests. `String` is not `URLConvertible`; an EPUB spine href is a relative
    /// resource path, so `RelativeURL(path:)` is the faithful construction.
    private func readiumLocator(
        href: String,
        progression: Double?,
        mediaType: MediaType = .xhtml
    ) -> ReadiumShared.Locator {
        ReadiumShared.Locator(
            href: RelativeURL(path: href)!,
            mediaType: mediaType,
            locations: ReadiumShared.Locator.Locations(progression: progression)
        )
    }

    // MARK: - makeVReaderLocator → readiumLocator round-trip

    @Test func makeVReaderLocator_roundTrips_preservesHrefAndProgression() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "chapter1.xhtml", progression: 0.42)

        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )
        let restored = try #require(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope))

        #expect(restored.href.string == source.href.string)
        #expect(restored.locations.progression == 0.42)
    }

    @Test func makeVReaderLocator_setsReadiumEngineAndJSON() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "ch.xhtml", progression: 0.1)

        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )

        #expect(envelope.engine == .readium)
        #expect(envelope.readiumLocatorJSON != nil)
        #expect(envelope.fingerprintKey == fp.canonicalKey)
        #expect(envelope.originalFormat == .epub)
        #expect(envelope.schemaVersion == VReaderLocator.currentSchemaVersion)
    }

    /// The legacy leg is a best-effort back-compat copy so the flag can flip OFF
    /// without total loss: href + progression are carried into the legacy Locator.
    @Test func makeVReaderLocator_carriesLossyLegacyLocator() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "part2/ch3.xhtml", progression: 0.75)

        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )
        let legacy = try #require(envelope.legacyLocator)

        // The legacy href is the canonical Readium string for the resource.
        #expect(legacy.href == source.href.string)
        #expect(legacy.progression == 0.75)
        #expect(legacy.bookFingerprint == fp)
    }

    // MARK: - readiumLocator(from:) guards on engine

    @Test func readiumLocator_returnsNil_forLegacyEngineEnvelope() {
        let fp = fingerprint()
        let legacy = vreader.Locator(
            bookFingerprint: fp, href: "ch1.xhtml", progression: 0.3,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let envelope = VReaderLocator(legacyLocator: legacy)
        #expect(envelope.engine == .epubWKWebView)
        #expect(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope) == nil)
    }

    @Test func readiumLocator_returnsNil_forMalformedReadiumJSON() {
        let fp = fingerprint()
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: "{not valid json",
            legacyLocator: nil
        )
        // SwiftData-safe posture: a decode failure returns nil, never throws.
        #expect(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope) == nil)
    }

    @Test func readiumLocator_returnsNil_forNilReadiumJSON() {
        let fp = fingerprint()
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: nil, legacyLocator: nil
        )
        #expect(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope) == nil)
    }

    // MARK: - Edge cases

    @Test func makeVReaderLocator_zeroProgression_roundTrips() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "start.xhtml", progression: 0.0)
        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )
        let restored = try #require(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope))
        #expect(restored.locations.progression == 0.0)
        #expect(envelope.legacyLocator?.progression == 0.0)
    }

    /// Missing progression (nil) — Readium emits no `progression` key; the
    /// legacy leg carries nil and the round-trip preserves the absence.
    @Test func makeVReaderLocator_missingProgression_roundTrips() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "ch.xhtml", progression: nil)
        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )
        let restored = try #require(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope))
        #expect(restored.href.string == source.href.string)
        #expect(restored.locations.progression == nil)
        #expect(envelope.legacyLocator?.progression == nil)
    }

    /// CJK href round-trips through UTF-8 JSON without mojibake.
    @Test func makeVReaderLocator_cjkHref_roundTrips() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "第一章.xhtml", progression: 0.5)
        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )
        let restored = try #require(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope))
        #expect(restored.href.string == source.href.string)
        #expect(envelope.legacyLocator?.href == source.href.string)
        // The href must survive UTF-8 JSON round-trip without mojibake — the
        // canonical form decodes back to the original CJK characters.
        #expect(restored.href.string.removingPercentEncoding == "第一章.xhtml")
    }

    /// A percent-encoded / fragment-bearing href (RTL-ish + special chars) survives.
    @Test func makeVReaderLocator_specialCharHref_roundTrips() throws {
        let fp = fingerprint()
        let source = readiumLocator(href: "OEBPS/مرحبا%20بالعالم.xhtml", progression: 0.9)
        let envelope = try #require(
            ReadiumEPUBReaderViewModel.makeVReaderLocator(
                from: source, fingerprintKey: fp.canonicalKey,
                fingerprint: fp, originalFormat: .epub
            )
        )
        let restored = try #require(ReadiumEPUBReaderViewModel.readiumLocator(from: envelope))
        #expect(restored.href.string == source.href.string)
    }
}

// MARK: - PersistenceActor envelope dual-write/read (WI-6)

@Suite("PersistenceActor VReaderLocator dual-write (WI-6)")
struct PersistenceActorVReaderLocatorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV8.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 4096, format: .epub
        )
    }

    private func insertBook(
        _ persistence: PersistenceActor, fp: DocumentFingerprint
    ) async throws {
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey, title: "Readium Book", author: nil,
            coverImagePath: nil, fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil, addedAt: Date()
        )
        _ = try await persistence.insertBook(record)
    }

    private func makeEnvelope(_ fp: DocumentFingerprint) -> (VReaderLocator, vreader.Locator) {
        let legacy = vreader.Locator(
            bookFingerprint: fp, href: "ch5.xhtml", progression: 0.55,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium,
            readiumLocatorJSON: #"{"href":"ch5.xhtml","type":"application/xhtml+xml","locations":{"progression":0.55}}"#,
            legacyLocator: legacy
        )
        return (envelope, legacy)
    }

    @Test func saveThenLoad_roundTripsEnvelope() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)
        let (envelope, legacy) = makeEnvelope(fp)

        try await persistence.saveVReaderLocator(
            bookFingerprintKey: fp.canonicalKey,
            vreaderLocator: envelope, legacyLocator: legacy, deviceId: "dev-1"
        )

        let loaded = try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey)
        #expect(loaded == envelope)
    }

    /// The dual-write: the legacy `locator` is ALSO written, so a flag-OFF
    /// reopen (legacy engine reads `loadPosition`) still finds a position.
    @Test func save_alsoWritesLegacyLocator() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)
        let (envelope, legacy) = makeEnvelope(fp)

        try await persistence.saveVReaderLocator(
            bookFingerprintKey: fp.canonicalKey,
            vreaderLocator: envelope, legacyLocator: legacy, deviceId: "dev-1"
        )

        let legacyLoaded = try await persistence.loadPosition(bookFingerprintKey: fp.canonicalKey)
        #expect(legacyLoaded?.href == "ch5.xhtml")
        #expect(legacyLoaded?.progression == 0.55)
    }

    /// A pre-existing row that predates the column (vreaderLocatorData == nil)
    /// loads back as nil cleanly — no decode crash.
    @Test func loadVReaderLocator_legacyRowWithoutEnvelope_returnsNil() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)

        // Write only the legacy locator via the existing savePosition path.
        let legacy = vreader.Locator(
            bookFingerprint: fp, href: "ch1.xhtml", progression: 0.2,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        try await persistence.savePosition(
            bookFingerprintKey: fp.canonicalKey, locator: legacy, deviceId: "dev-1"
        )

        let loaded = try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey)
        #expect(loaded == nil)
    }

    /// No row at all → nil (not a throw).
    @Test func loadVReaderLocator_noPosition_returnsNil() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)

        let loaded = try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey)
        #expect(loaded == nil)
    }

    /// Saving twice overwrites the existing row's envelope (no duplicate rows).
    @Test func saveVReaderLocator_isIdempotentOnReSave() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)
        let (envelope1, legacy1) = makeEnvelope(fp)

        try await persistence.saveVReaderLocator(
            bookFingerprintKey: fp.canonicalKey,
            vreaderLocator: envelope1, legacyLocator: legacy1, deviceId: "dev-1"
        )

        let legacy2 = vreader.Locator(
            bookFingerprint: fp, href: "ch9.xhtml", progression: 0.95,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let envelope2 = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium,
            readiumLocatorJSON: #"{"href":"ch9.xhtml","type":"application/xhtml+xml","locations":{"progression":0.95}}"#,
            legacyLocator: legacy2
        )
        try await persistence.saveVReaderLocator(
            bookFingerprintKey: fp.canonicalKey,
            vreaderLocator: envelope2, legacyLocator: legacy2, deviceId: "dev-1"
        )

        let loaded = try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey)
        #expect(loaded == envelope2)
        let legacyLoaded = try await persistence.loadPosition(bookFingerprintKey: fp.canonicalKey)
        #expect(legacyLoaded?.href == "ch9.xhtml")
    }

    /// Gate-4 round-1 High: after a Readium envelope is saved, a legacy
    /// `savePosition` (flag flipped OFF, legacy engine writes a newer position)
    /// must CLEAR the stale envelope — otherwise a later flag-ON reopen would
    /// restore the stale Readium position that predates the legacy write.
    @Test func legacySavePosition_clearsStaleReadiumEnvelope() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)
        let (envelope, legacy) = makeEnvelope(fp)

        try await persistence.saveVReaderLocator(
            bookFingerprintKey: fp.canonicalKey,
            vreaderLocator: envelope, legacyLocator: legacy, deviceId: "dev-1"
        )
        #expect(try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey) != nil)

        // Legacy engine writes a newer position.
        let newer = vreader.Locator(
            bookFingerprint: fp, href: "ch7.xhtml", progression: 0.7,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        try await persistence.savePosition(
            bookFingerprintKey: fp.canonicalKey, locator: newer, deviceId: "dev-1"
        )

        // Envelope cleared → flag-ON restore won't resurrect the stale position.
        #expect(try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey) == nil)
        // The legacy position is the newer one.
        let legacyLoaded = try await persistence.loadPosition(bookFingerprintKey: fp.canonicalKey)
        #expect(legacyLoaded?.href == "ch7.xhtml")
    }

    /// Gate-4 round-1 Medium: a fingerprint mismatch (book X's envelope written
    /// to book Y) is rejected, mirroring `savePosition`'s guard.
    @Test func saveVReaderLocator_mismatchedFingerprint_throws() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)
        let (envelope, legacy) = makeEnvelope(fp)

        await #expect(throws: (any Error).self) {
            try await persistence.saveVReaderLocator(
                bookFingerprintKey: "epub:\(String(repeating: "f", count: 64)):99",
                vreaderLocator: envelope, legacyLocator: legacy, deviceId: "dev-1"
            )
        }
    }

    /// Gate-4 round-1 High (fix 1): `closeAndFlush()` persists a still-pending
    /// debounced save WITHOUT waiting out the debounce — a dismiss before the
    /// timer fires must not lose the final position. Drives the VM's real
    /// save→pending→flush path through a real PersistenceActor.
    @MainActor
    @Test func closeAndFlush_persistsPendingDebouncedSave() async throws {
        let persistence = PersistenceActor(modelContainer: try makeContainer())
        let fp = fingerprint()
        try await insertBook(persistence, fp: fp)

        let vm = ReadiumEPUBReaderViewModel(
            fileURL: URL(fileURLWithPath: "/dev/null/x.epub"),
            fingerprint: fp,
            persistence: persistence,
            deviceId: "dev-1",
            positionSaveDebounceNs: 60_000_000_000  // 60s — far longer than the test
        )
        let loc = ReadiumShared.Locator(
            href: RelativeURL(path: "ch3.xhtml")!,
            mediaType: .xhtml,
            locations: ReadiumShared.Locator.Locations(progression: 0.33)
        )
        vm.save(readiumLocator: loc)  // schedules the (60s) debounce; pending set
        await vm.closeAndFlush()      // must flush the pending save immediately

        let loaded = try await persistence.loadVReaderLocator(bookFingerprintKey: fp.canonicalKey)
        #expect(loaded?.engine == .readium)
        #expect(loaded?.legacyLocator?.progression == 0.33)
    }
}
