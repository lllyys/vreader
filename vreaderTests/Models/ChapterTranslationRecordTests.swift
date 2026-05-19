// Purpose: Tests for ChapterTranslationRecord — the value-type DTO crossing the
// ChapterTranslationStore actor boundary, and its canonical lookupKey builder.
//
// @coordinates-with: ChapterTranslationRecord.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-2)

import Testing
import Foundation
@testable import vreader

@Suite("ChapterTranslationRecord")
struct ChapterTranslationRecordTests {

    private static let profileA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let profileB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - lookupKey builder

    @Test func lookupKeyIsDeterministic() {
        let k1 = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "epubHref:ch1",
            targetLanguage: "zh-Hans", providerProfileID: Self.profileA, promptVersion: "v1")
        let k2 = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "epubHref:ch1",
            targetLanguage: "zh-Hans", providerProfileID: Self.profileA, promptVersion: "v1")
        #expect(k1 == k2)
    }

    @Test func lookupKeyChangesWhenBookFingerprintChanges() {
        let base = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp1", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        let other = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp2", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        #expect(base != other)
    }

    @Test func lookupKeyChangesWhenUnitStorageKeyChanges() {
        let base = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "epubHref:ch1", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        let other = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "epubHref:ch2", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        #expect(base != other)
    }

    @Test func lookupKeyChangesWhenTargetLanguageChanges() {
        let base = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        let other = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "ja",
            providerProfileID: Self.profileA, promptVersion: "v1")
        #expect(base != other)
    }

    @Test func lookupKeyChangesWhenProviderChanges() {
        // Pins edge case (d): a provider change must produce a different key so
        // the old cache row is naturally bypassed as stale.
        let base = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        let other = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileB, promptVersion: "v1")
        #expect(base != other)
    }

    @Test func lookupKeyChangesWhenPromptVersionChanges() {
        let base = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        let other = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v2")
        #expect(base != other)
    }

    // MARK: - DTO

    @Test func recordCarriesTranslatedSegments() {
        let record = ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1",
            translatedSegments: ["你好", "世界"], sourceParagraphCount: 2)
        #expect(record.translatedSegments == ["你好", "世界"])
        #expect(record.sourceParagraphCount == 2)
    }

    @Test func recordLookupKeyMatchesBuilder() {
        let record = ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1",
            translatedSegments: [], sourceParagraphCount: 0)
        let expected = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1")
        #expect(record.lookupKey == expected)
    }

    @Test func recordEquatableHoldsForIdenticalValues() {
        // createdAt is pinned so equality reflects the identity + payload fields,
        // not the wall-clock instant of construction.
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        func make() -> ChapterTranslationRecord {
            ChapterTranslationRecord(
                bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
                providerProfileID: Self.profileA, promptVersion: "v1",
                translatedSegments: ["a"], sourceParagraphCount: 1, createdAt: fixed)
        }
        #expect(make() == make())
    }

    @Test func recordsDifferingOnlyInCreatedAtAreNotEqual() {
        // createdAt participates in Equatable — a re-translation with a newer
        // timestamp is a distinct record even with identical payload.
        let a = ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1",
            translatedSegments: ["a"], sourceParagraphCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let b = ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: "u", targetLanguage: "zh-Hans",
            providerProfileID: Self.profileA, promptVersion: "v1",
            translatedSegments: ["a"], sourceParagraphCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_999))
        #expect(a != b)
        #expect(a.lookupKey == b.lookupKey)  // but the identity key is the same
    }
}
