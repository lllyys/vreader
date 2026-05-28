// Purpose: Tests for VReaderLocator — the durable, engine-agnostic position
// envelope introduced for Feature #42 (Readium reader engine). Covers Codable
// round-trip, canonicalHash determinism/stability, the legacy-Locator wrapping
// initializer, equality, and Unicode/CJK + nil-field edge cases.
//
// @coordinates-with: VReaderLocator.swift, Locator.swift, DocumentFingerprint.swift

import Testing
import Foundation
@testable import vreader

@Suite("VReaderLocator")
struct VReaderLocatorTests {

    // MARK: - Fixtures

    private func makeFingerprint(
        sha: String = String(repeating: "a", count: 64),
        bytes: Int64 = 1024,
        format: BookFormat = .epub
    ) -> DocumentFingerprint {
        DocumentFingerprint(contentSHA256: sha, fileByteCount: bytes, format: format)
    }

    private func makeLegacyLocator(
        _ fp: DocumentFingerprint,
        href: String = "chapter1.xhtml",
        progression: Double = 0.25
    ) -> Locator {
        Locator(
            bookFingerprint: fp, href: href,
            progression: progression, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Codable round-trip

    @Test func codableRoundTripWithAllFields() throws {
        let fp = makeFingerprint()
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey,
            originalFormat: .epub,
            engine: .readium,
            readiumLocatorJSON: #"{"href":"ch1.xhtml","locations":{"progression":0.5}}"#,
            legacyLocator: makeLegacyLocator(fp),
            schemaVersion: 1
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(VReaderLocator.self, from: data)
        #expect(decoded == envelope)
    }

    @Test func codableRoundTripWithNilOptionalFields() throws {
        let fp = makeFingerprint()
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey,
            originalFormat: .pdf,
            engine: .epubWKWebView,
            readiumLocatorJSON: nil,
            legacyLocator: nil,
            schemaVersion: 1
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(VReaderLocator.self, from: data)
        #expect(decoded == envelope)
        #expect(decoded.readiumLocatorJSON == nil)
        #expect(decoded.legacyLocator == nil)
    }

    // MARK: - canonicalHash

    @Test func canonicalHashIsDeterministic() {
        let fp = makeFingerprint()
        let a = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: "{}",
            legacyLocator: makeLegacyLocator(fp), schemaVersion: 1
        )
        let b = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: "{}",
            legacyLocator: makeLegacyLocator(fp), schemaVersion: 1
        )
        #expect(a.canonicalHash == b.canonicalHash)
    }

    @Test func canonicalHashIsSHA256Hex() {
        let fp = makeFingerprint()
        let env = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: nil,
            legacyLocator: nil, schemaVersion: 1
        )
        let hash = env.canonicalHash
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test func canonicalHashChangesWhenEngineChanges() {
        let fp = makeFingerprint()
        let readium = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: nil, legacyLocator: nil, schemaVersion: 1
        )
        let legacy = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .epubWKWebView, readiumLocatorJSON: nil, legacyLocator: nil, schemaVersion: 1
        )
        #expect(readium.canonicalHash != legacy.canonicalHash)
    }

    @Test func canonicalHashChangesWhenReadiumJSONChanges() {
        let fp = makeFingerprint()
        let a = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: #"{"progression":0.1}"#,
            legacyLocator: nil, schemaVersion: 1
        )
        let b = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: #"{"progression":0.9}"#,
            legacyLocator: nil, schemaVersion: 1
        )
        #expect(a.canonicalHash != b.canonicalHash)
    }

    // MARK: - Legacy Locator wrapping initializer

    @Test func wrappingLegacyLocatorPopulatesFields() {
        let fp = makeFingerprint(format: .epub)
        let legacy = makeLegacyLocator(fp, href: "intro.xhtml", progression: 0.4)
        let envelope = VReaderLocator(legacyLocator: legacy)

        #expect(envelope.engine == .epubWKWebView)
        #expect(envelope.legacyLocator == legacy)
        #expect(envelope.readiumLocatorJSON == nil)
        #expect(envelope.fingerprintKey == fp.canonicalKey)
        #expect(envelope.originalFormat == .epub)
    }

    @Test func wrappingLegacyLocatorPreservesFormat() {
        let fp = makeFingerprint(format: .txt)
        let legacy = Locator(
            bookFingerprint: fp, href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 42,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let envelope = VReaderLocator(legacyLocator: legacy)
        #expect(envelope.originalFormat == .txt)
        #expect(envelope.legacyLocator?.charOffsetUTF16 == 42)
    }

    // MARK: - Equality

    @Test func equalEnvelopesAreEqual() {
        let fp = makeFingerprint()
        let a = VReaderLocator(legacyLocator: makeLegacyLocator(fp))
        let b = VReaderLocator(legacyLocator: makeLegacyLocator(fp))
        #expect(a == b)
    }

    @Test func differentSchemaVersionsAreNotEqual() {
        let fp = makeFingerprint()
        let a = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: nil, legacyLocator: nil, schemaVersion: 1
        )
        let b = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: nil, legacyLocator: nil, schemaVersion: 2
        )
        #expect(a != b)
    }

    // MARK: - Edge cases

    @Test func emptyFingerprintKeyRoundTrips() throws {
        let envelope = VReaderLocator(
            fingerprintKey: "",
            originalFormat: .epub, engine: .readium,
            readiumLocatorJSON: nil, legacyLocator: nil, schemaVersion: 1
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(VReaderLocator.self, from: data)
        #expect(decoded == envelope)
        // canonicalHash still well-formed.
        #expect(envelope.canonicalHash.count == 64)
    }

    @Test func cjkAndUnicodeInReadiumJSONRoundTrips() throws {
        let fp = makeFingerprint()
        let json = "{\"text\":\"被讨厌的勇气 — émoji 🎉 \tcontrol\"}"
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium, readiumLocatorJSON: json,
            legacyLocator: nil, schemaVersion: 1
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(VReaderLocator.self, from: data)
        #expect(decoded.readiumLocatorJSON == json)
        #expect(decoded == envelope)
        // Hash stable across encode/decode round-trip.
        #expect(decoded.canonicalHash == envelope.canonicalHash)
    }

    @Test func cjkInFingerprintKeyDoesNotBreakHash() {
        let envelope = VReaderLocator(
            fingerprintKey: "epub:被讨厌的勇气:1024",
            originalFormat: .epub, engine: .readium,
            readiumLocatorJSON: nil, legacyLocator: nil, schemaVersion: 1
        )
        #expect(envelope.canonicalHash.count == 64)
    }
}
