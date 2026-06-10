// Purpose: Tests for ChapterTranslationStore — the actor-isolated disk cache for
// feature #56 bilingual reading. In-memory ModelContainer; verifies fetch,
// idempotent upsert, batch ops, single + per-book delete, and cachedUnits.
//
// @coordinates-with: ChapterTranslationStore.swift, ChapterTranslation.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-2)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("ChapterTranslationStore")
struct ChapterTranslationStoreTests {

    private static let profileA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let profileB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    /// Builds a store backed by a fresh in-memory container (production callers
    /// use `.shared`; tests inject a non-shared instance per the plan).
    private func makeStore() throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ChapterTranslationStore(modelContainer: container)
    }

    private func record(
        book: String = "fp1",
        unit: String = "epubHref:ch1",
        lang: String = "zh-Hans",
        provider: UUID = ChapterTranslationStoreTests.profileA,
        prompt: String = "v1",
        segments: [String] = ["你好"],
        sourceCount: Int = 1
    ) -> ChapterTranslationRecord {
        ChapterTranslationRecord(
            bookFingerprintKey: book, unitStorageKey: unit, targetLanguage: lang,
            providerProfileID: provider, promptVersion: prompt,
            translatedSegments: segments, sourceParagraphCount: sourceCount)
    }

    // MARK: - Insert + fetch

    @Test func upsertThenFetchByKeyReturnsTheRecord() async throws {
        let store = try makeStore()
        let rec = record(segments: ["你好", "世界"], sourceCount: 2)
        try await store.upsert(rec)

        let fetched = await store.translation(forKey: rec.lookupKey)
        #expect(fetched != nil)
        #expect(fetched?.translatedSegments == ["你好", "世界"])
        #expect(fetched?.sourceParagraphCount == 2)
        #expect(fetched?.providerProfileID == Self.profileA)
    }

    @Test func fetchMissingKeyReturnsNil() async throws {
        let store = try makeStore()
        let fetched = await store.translation(forKey: "no-such-key")
        #expect(fetched == nil)
    }

    // MARK: - Idempotent upsert

    @Test func upsertSameKeyTwiceUpdatesInPlaceAndNeverThrows() async throws {
        let store = try makeStore()
        let first = record(segments: ["first"])
        try await store.upsert(first)
        // Same lookupKey, different payload — must update in place, not throw.
        let second = record(segments: ["second", "更新"], sourceCount: 2)
        try await store.upsert(second)  // would throw if it relied on the unique constraint

        let fetched = await store.translation(forKey: first.lookupKey)
        #expect(fetched?.translatedSegments == ["second", "更新"])
        #expect(fetched?.sourceParagraphCount == 2)
    }

    @Test func upsertSameKeyTwiceLeavesExactlyOneRow() async throws {
        let store = try makeStore()
        let rec = record()
        try await store.upsert(rec)
        try await store.upsert(rec)
        let count = await store.debugRowCount()
        #expect(count == 1)
    }

    // MARK: - Batch

    @Test func batchFetchReturnsOnlyTheRequestedSubset() async throws {
        let store = try makeStore()
        let a = record(unit: "epubHref:ch1")
        let b = record(unit: "epubHref:ch2")
        let c = record(unit: "epubHref:ch3")
        try await store.upsert([a, b, c])

        let result = await store.translations(forKeys: [a.lookupKey, c.lookupKey])
        #expect(Set(result.keys) == Set([a.lookupKey, c.lookupKey]))
        #expect(result[a.lookupKey]?.unitStorageKey == "epubHref:ch1")
        #expect(result[c.lookupKey]?.unitStorageKey == "epubHref:ch3")
    }

    @Test func batchFetchWithEmptyKeysReturnsEmpty() async throws {
        let store = try makeStore()
        try await store.upsert(record())
        let result = await store.translations(forKeys: [])
        #expect(result.isEmpty)
    }

    @Test func batchUpsertIsIdempotent() async throws {
        let store = try makeStore()
        let a = record(unit: "epubHref:ch1")
        let b = record(unit: "epubHref:ch2")
        try await store.upsert([a, b])
        try await store.upsert([a, b])  // re-upsert
        let count = await store.debugRowCount()
        #expect(count == 2)
    }

    // MARK: - Delete

    @Test func deleteTranslationForKeyRemovesOnlyThatRow() async throws {
        let store = try makeStore()
        let a = record(unit: "epubHref:ch1")
        let b = record(unit: "epubHref:ch2")
        try await store.upsert([a, b])

        try await store.deleteTranslation(forKey: a.lookupKey)
        #expect(await store.translation(forKey: a.lookupKey) == nil)
        #expect(await store.translation(forKey: b.lookupKey) != nil)
    }

    @Test func deleteTranslationForMissingKeyDoesNotThrow() async throws {
        let store = try makeStore()
        try await store.deleteTranslation(forKey: "ghost")  // no-op, no throw
        #expect(await store.debugRowCount() == 0)
    }

    @Test func deleteTranslationsForBookRemovesAllOfThatBook() async throws {
        let store = try makeStore()
        try await store.upsert([
            record(book: "fpA", unit: "epubHref:ch1"),
            record(book: "fpA", unit: "epubHref:ch2"),
            record(book: "fpB", unit: "epubHref:ch1"),
        ])
        try await store.deleteTranslations(forBookWithKey: "fpA")

        let count = await store.debugRowCount()
        #expect(count == 1)
        let surviving = await store.cachedUnits(
            forBookWithKey: "fpB", targetLanguage: "zh-Hans",
            promptVersion: "v1")
        #expect(surviving == ["epubHref:ch1"])
    }

    // MARK: - cachedUnits

    @Test func cachedUnitsReturnsCoveredUnitStorageKeys() async throws {
        let store = try makeStore()
        try await store.upsert([
            record(book: "fpA", unit: "epubHref:ch1"),
            record(book: "fpA", unit: "epubHref:ch2"),
        ])
        let units = await store.cachedUnits(
            forBookWithKey: "fpA", targetLanguage: "zh-Hans",
            promptVersion: "v1")
        #expect(units == Set(["epubHref:ch1", "epubHref:ch2"]))
    }

    @Test func cachedUnitsExcludesOtherLanguageAndPromptVersion_butNotProvider() async throws {
        // Bug #342: the provider profile is provenance, not identity — a row
        // written under ANY profile counts as covered. Language and prompt
        // version still partition coverage.
        let store = try makeStore()
        try await store.upsert([
            record(book: "fpA", unit: "epubHref:ch1", lang: "zh-Hans", provider: Self.profileA, prompt: "v1"),
            record(book: "fpA", unit: "epubHref:ch2", lang: "ja",      provider: Self.profileA, prompt: "v1"),
            record(book: "fpA", unit: "epubHref:ch3", lang: "zh-Hans", provider: Self.profileB, prompt: "v1"),
            record(book: "fpA", unit: "epubHref:ch4", lang: "zh-Hans", provider: Self.profileA, prompt: "v2"),
        ])
        let units = await store.cachedUnits(
            forBookWithKey: "fpA", targetLanguage: "zh-Hans",
            promptVersion: "v1")
        #expect(units == Set(["epubHref:ch1", "epubHref:ch3"]))
    }

    @Test func cachedUnitsEmptyWhenNothingCached() async throws {
        let store = try makeStore()
        let units = await store.cachedUnits(
            forBookWithKey: "fpA", targetLanguage: "zh-Hans",
            promptVersion: "v1")
        #expect(units.isEmpty)
    }

    // MARK: - Round-trips

    @Test func translatedSegmentsRoundTripThroughJSON() async throws {
        let store = try makeStore()
        // CJK + quotes + an empty segment — exercise JSON encoding edge cases.
        let segments = ["你好，世界", "\"quoted\"", "", "emoji 🌏"]
        try await store.upsert(record(segments: segments, sourceCount: 4))
        let fetched = await store.translation(
            forKey: record(segments: segments, sourceCount: 4).lookupKey)
        #expect(fetched?.translatedSegments == segments)
    }

    @Test func legitimateEmptySegmentArrayRoundTripsAsEmptyNotMiss() async throws {
        // An empty translated array is a valid value (an empty unit) — it must
        // round-trip as a hit with [], distinct from a corrupt-row miss.
        let store = try makeStore()
        let rec = record(segments: [], sourceCount: 0)
        try await store.upsert(rec)
        let fetched = await store.translation(forKey: rec.lookupKey)
        #expect(fetched != nil)
        #expect(fetched?.translatedSegments == [])
    }

    // MARK: - Corrupt rows

    @Test func corruptTranslatedJSONIsTreatedAsAMissNotEmpty() async throws {
        // A row whose translatedJSON cannot decode must surface as a cache MISS
        // — otherwise corruption masquerades as a legit empty translation and a
        // later caller skips re-translation forever.
        let store = try makeStore()
        let key = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fpC", unitStorageKey: "epubHref:bad",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        try await store.debugInsertRaw(
            lookupKey: key, bookFingerprintKey: "fpC", unitStorageKey: "epubHref:bad",
            targetLanguage: "zh-Hans", providerProfileID: Self.profileA, promptVersion: "v1",
            translatedJSON: "{not valid json", sourceParagraphCount: 3)

        #expect(await store.translation(forKey: key) == nil)         // miss
        #expect(await store.debugRowCount() == 1)                    // the row still physically exists
    }

    @Test func corruptRowIsExcludedFromBatchFetchAndCachedUnits() async throws {
        let store = try makeStore()
        let goodKey = record(book: "fpC", unit: "epubHref:good").lookupKey
        try await store.upsert(record(book: "fpC", unit: "epubHref:good"))
        let badKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fpC", unitStorageKey: "epubHref:bad",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        try await store.debugInsertRaw(
            lookupKey: badKey, bookFingerprintKey: "fpC", unitStorageKey: "epubHref:bad",
            targetLanguage: "zh-Hans", providerProfileID: Self.profileA, promptVersion: "v1",
            translatedJSON: "<<garbage>>", sourceParagraphCount: 1)

        let batch = await store.translations(forKeys: [goodKey, badKey])
        #expect(Set(batch.keys) == [goodKey])  // corrupt row absent

        // The corrupt unit is NOT counted as covered — global translate must redo it.
        let units = await store.cachedUnits(
            forBookWithKey: "fpC", targetLanguage: "zh-Hans",
            promptVersion: "v1")
        #expect(units == ["epubHref:good"])
    }

    @Test func reUpsertOverwritesACorruptRow() async throws {
        // The recovery path: after a corrupt-row miss, the caller re-translates
        // and upsert overwrites the bad row in place — the next fetch is a hit.
        let store = try makeStore()
        let key = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fpC", unitStorageKey: "epubHref:fix",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        try await store.debugInsertRaw(
            lookupKey: key, bookFingerprintKey: "fpC", unitStorageKey: "epubHref:fix",
            targetLanguage: "zh-Hans", providerProfileID: Self.profileA, promptVersion: "v1",
            translatedJSON: "broken", sourceParagraphCount: 2)
        #expect(await store.translation(forKey: key) == nil)

        try await store.upsert(record(
            book: "fpC", unit: "epubHref:fix", segments: ["修复", "了"], sourceCount: 2))
        let fixed = await store.translation(forKey: key)
        #expect(fixed?.translatedSegments == ["修复", "了"])
        #expect(await store.debugRowCount() == 1)  // overwrote in place, no duplicate
    }

    // MARK: - Unconfigured singleton

    @Test func unconfiguredStoreIsASafeNoOp() async throws {
        // `.shared` is unconfigured until VReaderApp.init wires the app
        // container. An unconfigured store must never crash — every op is a
        // safe empty result / no-op (bilingual mode is feature-flag-gated off,
        // so production never reaches an unconfigured store anyway).
        let unconfigured = ChapterTranslationStore.makeUnconfiguredForTesting()
        #expect(await unconfigured.translation(forKey: "k") == nil)
        #expect(await unconfigured.translations(forKeys: ["k"]).isEmpty)
        #expect(await unconfigured.debugRowCount() == 0)
        let units = await unconfigured.cachedUnits(
            forBookWithKey: "fp", targetLanguage: "zh-Hans",
            promptVersion: "v1")
        #expect(units.isEmpty)
        // upsert / delete must not throw on an unconfigured store.
        try await unconfigured.upsert(record())
        try await unconfigured.deleteTranslation(forKey: "k")
        try await unconfigured.deleteTranslations(forBookWithKey: "fp")
    }

    // MARK: - Bug #342: legacy 5-field lookupKey migration

    /// Builds a store + its container so a test can plant legacy-format rows
    /// directly via ModelContext (the public API only writes canonical keys).
    private func makeStoreAndContainer() throws -> (ChapterTranslationStore, ModelContainer) {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (ChapterTranslationStore(modelContainer: container), container)
    }

    /// Inserts a row with the PRE-#342 5-field key (`book|unit|lang|profileID|prompt`).
    @MainActor
    private func insertLegacyRow(
        _ container: ModelContainer,
        book: String = "fp1", unit: String = "epubHref:ch1", lang: String = "zh-Hans",
        profile: UUID, prompt: String = "v1",
        json: String, count: Int, createdAt: Date
    ) throws {
        let context = ModelContext(container)
        context.insert(ChapterTranslation(
            lookupKey: [book, unit, lang, profile.uuidString, prompt].joined(separator: "|"),
            bookFingerprintKey: book, unitStorageKey: unit, targetLanguage: lang,
            providerProfileID: profile, promptVersion: prompt,
            translatedJSON: json, sourceParagraphCount: count, createdAt: createdAt))
        try context.save()
    }

    /// Bug #342: legacy rows written under per-profile keys must become
    /// reachable via the canonical `book|unit|lang|prompt` key — deduped to
    /// the NEWEST row when several profiles cached the same unit.
    @Test func legacyRows_migrateToCanonicalKey_dedupedToNewest() async throws {
        let (store, container) = try makeStoreAndContainer()
        try await insertLegacyRow(
            container, profile: Self.profileA,
            json: #"["旧A"]"#, count: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await insertLegacyRow(
            container, profile: Self.profileB,
            json: #"["新B"]"#, count: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_999))

        let canonicalKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp1", unitStorageKey: "epubHref:ch1",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        let migrated = await store.translation(forKey: canonicalKey)
        #expect(migrated != nil, "legacy rows must be reachable via the canonical key")
        #expect(migrated?.translatedSegments == ["新B"], "dedupe keeps the newest row")
        #expect(await store.debugRowCount() == 1, "the older per-profile duplicate is removed")
    }

    /// Codex #342 round-1 High: `configure(modelContainer:)` swapping to a NEW
    /// container must re-arm the migration — the new container may hold legacy
    /// rows the previous container's pass never saw.
    @Test func containerSwap_reArmsLegacyMigration() async throws {
        // Container A: run the (empty) migration, setting the per-process flag.
        let (store, _) = try makeStoreAndContainer()
        _ = await store.translation(forKey: "warm-up")

        // Container B: holds an unmigrated legacy row.
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let containerB = try ModelContainer(for: schema, configurations: [config])
        try await insertLegacyRow(
            containerB, profile: Self.profileA,
            json: #"["旧"]"#, count: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        await store.configure(modelContainer: containerB)

        let canonicalKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp1", unitStorageKey: "epubHref:ch1",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        #expect(await store.translation(forKey: canonicalKey)?.translatedSegments == ["旧"],
                "the swapped-in container's legacy rows migrate too")
        let units = await store.cachedUnits(
            forBookWithKey: "fp1", targetLanguage: "zh-Hans", promptVersion: "v1")
        #expect(units == ["epubHref:ch1"])
    }

    /// Migration must be idempotent and must leave already-canonical rows alone.
    @Test func migration_isIdempotent_andLeavesCanonicalRowsAlone() async throws {
        let (store, container) = try makeStoreAndContainer()
        try await insertLegacyRow(
            container, profile: Self.profileA,
            json: #"["旧"]"#, count: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        // A canonical row for a DIFFERENT unit, written through the public API.
        try await store.upsert(record(unit: "epubHref:ch2", segments: ["canon"]))

        let key1 = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp1", unitStorageKey: "epubHref:ch1",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        let key2 = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp1", unitStorageKey: "epubHref:ch2",
            targetLanguage: "zh-Hans", promptVersion: "v1")
        #expect(await store.translation(forKey: key1)?.translatedSegments == ["旧"])
        #expect(await store.translation(forKey: key2)?.translatedSegments == ["canon"])
        // Run more ops (each re-enters the lazy migration guard) — still 2 rows.
        #expect(await store.translation(forKey: key1) != nil)
        #expect(await store.debugRowCount() == 2)
    }
}
