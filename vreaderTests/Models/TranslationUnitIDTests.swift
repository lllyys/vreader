// Purpose: Tests for TranslationUnitID — the format-agnostic translation-unit
// identity value type for feature #56 bilingual reading.
//
// @coordinates-with: TranslationUnitID.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-1)

import Testing
import Foundation
@testable import vreader

@Suite("TranslationUnitID")
struct TranslationUnitIDTests {

    @Test func storageKeyCombinesKindAndValue() {
        let unit = TranslationUnitID(kind: .epubHref, value: "OEBPS/ch1.xhtml")
        #expect(unit.storageKey == "epubHref:OEBPS/ch1.xhtml")
    }

    @Test(arguments: [
        TranslationUnitID.Kind.epubHref,
        .foliateHref,
        .txtChapterIndex,
        .mdChapterIndex,
        .pdfPageRange,
    ])
    func storageKeyIsDistinctPerKind(_ kind: TranslationUnitID.Kind) {
        let unit = TranslationUnitID(kind: kind, value: "7")
        #expect(unit.storageKey == "\(kind.rawValue):7")
    }

    @Test func sameKindDifferentValueProduceDistinctKeys() {
        let a = TranslationUnitID(kind: .txtChapterIndex, value: "1")
        let b = TranslationUnitID(kind: .txtChapterIndex, value: "2")
        #expect(a.storageKey != b.storageKey)
    }

    @Test func sameValueDifferentKindProduceDistinctKeys() {
        let a = TranslationUnitID(kind: .txtChapterIndex, value: "1")
        let b = TranslationUnitID(kind: .mdChapterIndex, value: "1")
        #expect(a != b)
        #expect(a.storageKey != b.storageKey)
    }

    @Test func equalityHoldsForIdenticalKindAndValue() {
        let a = TranslationUnitID(kind: .foliateHref, value: "section-3")
        let b = TranslationUnitID(kind: .foliateHref, value: "section-3")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func codableRoundTrips() throws {
        let original = TranslationUnitID(kind: .pdfPageRange, value: "10-20")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranslationUnitID.self, from: encoded)
        #expect(decoded == original)
    }

    @Test func canKeyADictionary() {
        let a = TranslationUnitID(kind: .epubHref, value: "a")
        let b = TranslationUnitID(kind: .epubHref, value: "b")
        var dict: [TranslationUnitID: [String]] = [:]
        dict[a] = ["alpha"]
        dict[b] = ["beta"]
        #expect(dict[a] == ["alpha"])
        #expect(dict[b] == ["beta"])
        #expect(dict.count == 2)
    }

    @Test func canPopulateASet() {
        let units: Set<TranslationUnitID> = [
            TranslationUnitID(kind: .mdChapterIndex, value: "0"),
            TranslationUnitID(kind: .mdChapterIndex, value: "0"),
            TranslationUnitID(kind: .mdChapterIndex, value: "1"),
        ]
        #expect(units.count == 2)
    }

    @Test func kindRawValuesAreStable() {
        // The raw values are persisted (storageKey -> ChapterTranslation.unitStorageKey),
        // so a rename is a data-format break. Pin them.
        #expect(TranslationUnitID.Kind.epubHref.rawValue == "epubHref")
        #expect(TranslationUnitID.Kind.foliateHref.rawValue == "foliateHref")
        #expect(TranslationUnitID.Kind.txtChapterIndex.rawValue == "txtChapterIndex")
        #expect(TranslationUnitID.Kind.mdChapterIndex.rawValue == "mdChapterIndex")
        #expect(TranslationUnitID.Kind.pdfPageRange.rawValue == "pdfPageRange")
    }
}
