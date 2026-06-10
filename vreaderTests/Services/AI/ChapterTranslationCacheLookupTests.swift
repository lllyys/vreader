// Bug #306: ChapterTranslationService.cachedTranslation — a config-free cache
// lookup so the prefetcher can serve an already-translated chapter BEFORE the
// provider gate (AI disabled / unconfigured / key-less). Previously the gate
// threw first and the disk cache (inside translate) was never reached.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("ChapterTranslationService.cachedTranslation (Bug #306)")
struct ChapterTranslationCacheLookupTests {

    private func makeStore() throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ChapterTranslationStore(modelContainer: container)
    }

    private func makeService(_ store: ChapterTranslationStore) -> ChapterTranslationService {
        ChapterTranslationService(
            sender: MockTranslationSender(responses: []), store: store, promptVersion: "v1")
    }

    private let book = "epub:abc123:42"
    private let lang = "zh-Hans"
    private let profile = UUID()
    private var unit: TranslationUnitID { TranslationUnitID(kind: .epubHref, value: "ch1.xhtml") }

    private func upsertCached(
        _ store: ChapterTranslationStore, source: String, segments: [String],
        profileID: UUID? = nil
    ) async throws {
        let count = ChapterSegmenter.paragraphs(in: source).count
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: book, unitStorageKey: unit.storageKey, targetLanguage: lang,
            providerProfileID: profileID ?? profile, promptVersion: "v1",
            translatedSegments: segments, sourceParagraphCount: count))
    }

    @Test("a fresh cached row is returned WITHOUT any provider config")
    func cacheHitNeedsNoConfig() async throws {
        let store = try makeStore()
        let service = makeService(store)
        let source = "Para one.\n\nPara two."
        try await upsertCached(store, source: source, segments: ["一", "二"])

        let result = await service.cachedTranslation(
            bookFingerprintKey: book, unit: unit, sourceText: source,
            targetLanguage: lang)
        #expect(result?.fromCache == true)
        #expect(result?.segments == ["一", "二"])
    }

    @Test("no cached row → nil (caller falls through to the provider gate)")
    func cacheMiss() async throws {
        let store = try makeStore()
        let service = makeService(store)
        let result = await service.cachedTranslation(
            bookFingerprintKey: book, unit: unit, sourceText: "x",
            targetLanguage: lang)
        #expect(result == nil)
    }

    @Test("a stale row (source paragraph count changed) → nil, not a wrong render")
    func staleCacheReturnsNil() async throws {
        let store = try makeStore()
        let service = makeService(store)
        try await upsertCached(store, source: "Only one.", segments: ["一"])
        // Live source now has two paragraphs → count mismatch → stale.
        let result = await service.cachedTranslation(
            bookFingerprintKey: book, unit: unit, sourceText: "A.\n\nB.",
            targetLanguage: lang)
        #expect(result == nil)
    }

    @Test("a row written under ANY profile is served — the key is profile-agnostic (Bug #342)")
    func differentProfileStillHits() async throws {
        // Bug #342 INVERTED the old contract ("the key includes the profile"):
        // one canonical translation per book|unit|lang|prompt, shared by the
        // bilingual prefetcher and re-translate regardless of provider.
        let store = try makeStore()
        let service = makeService(store)
        let source = "One.\n\nTwo."
        try await upsertCached(store, source: source, segments: ["一", "二"], profileID: UUID())
        let result = await service.cachedTranslation(
            bookFingerprintKey: book, unit: unit, sourceText: source,
            targetLanguage: lang)
        #expect(result?.fromCache == true)
        #expect(result?.segments == ["一", "二"])
    }
}
