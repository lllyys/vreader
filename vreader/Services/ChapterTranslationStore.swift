// Purpose: Actor-isolated disk cache for feature #56 bilingual reading
// (scope item 2 — "persistent translation cache"). Wraps a SwiftData
// ModelContext over the ChapterTranslation @Model. Translations cached here
// survive app restarts and cost no repeat API calls.
//
// Key decisions:
// - A SEPARATE actor, not a PersistenceActor extension — the cache is derived,
//   re-fetchable data (excluded from backup), and keeping bulk translation
//   writes off PersistenceActor's serialization queue avoids contending the
//   main library store during a global-translate run.
// - App-scoped single instance via `.shared` (the ProviderProfileStore.shared
//   precedent). Multiple instances over the same store would let same-lookupKey
//   inserts race SwiftData's unique constraint. Production callers MUST use
//   `.shared`; tests inject a non-shared instance over an in-memory container.
// - `upsert` is IDEMPOTENT — it fetches by `lookupKey` and updates the row in
//   place, never relying on the @Attribute(.unique) constraint to throw. This
//   is defense-in-depth on top of the single-instance guarantee.
// - Returns the value-type `ChapterTranslationRecord`, never the @Model
//   (context-bound) — the BookRecord / HighlightRecord pattern.
//
// @coordinates-with: ChapterTranslation.swift, ChapterTranslationRecord.swift,
//   SchemaV7.swift, dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-2)

import Foundation
import OSLog
import SwiftData

/// Actor-isolated persistent cache of chapter translations.
actor ChapterTranslationStore {

    /// App-scoped production singleton. All production callers
    /// (`ChapterTranslationService`, `BookTranslationCoordinator`, the
    /// bilingual view models) MUST use this exact instance — otherwise the
    /// actor-isolation guarantee against racing same-`lookupKey` inserts does
    /// not hold. Tests inject a non-shared instance over an in-memory
    /// container via `init(modelContainer:)`.
    ///
    /// `.shared` starts unconfigured: `VReaderApp.init()` calls
    /// `configure(modelContainer:)` with the **app's own** `ModelContainer`
    /// (the one `ModelContainerFactory` built — same store file, same
    /// migration/config selection). Wiring the app container rather than
    /// self-building a second one avoids a split-brain cache when the app
    /// runs in-memory (UI tests). Until configured, every method is a safe
    /// no-op / empty result — bilingual mode is feature-flag-gated off by
    /// default, so production never reaches an unconfigured `.shared`.
    static let shared = ChapterTranslationStore()

    private var modelContainer: ModelContainer?
    private let log = Logger(subsystem: "com.vreader.app", category: "ChapterTranslationStore")

    /// Production singleton initializer — unconfigured until `configure(_:)`.
    private init() {
        self.modelContainer = nil
    }

    /// Test initializer — inject an in-memory container. Production callers
    /// MUST use `.shared` + `configure(modelContainer:)`.
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Wires the singleton to the app's `ModelContainer`. Called once from
    /// `VReaderApp.init()` after the container is built. Idempotent — a
    /// second call replaces the container (harmless; production calls once).
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    #if DEBUG
    /// Test-only factory for an unconfigured instance (the production `init()`
    /// is `private`). Used to verify the unconfigured store degrades to safe
    /// no-ops rather than crashing.
    static func makeUnconfiguredForTesting() -> ChapterTranslationStore {
        ChapterTranslationStore()
    }
    #endif

    // MARK: - Fetch

    /// Returns the cached translation for `lookupKey`, or `nil` on a miss.
    /// A row whose stored `translatedJSON` cannot be decoded is treated as a
    /// **miss** (not an empty translation) so corruption can never masquerade
    /// as a legitimate cache hit — the caller re-translates and the idempotent
    /// `upsert` overwrites the bad row.
    func translation(forKey lookupKey: String) async -> ChapterTranslationRecord? {
        guard let modelContainer else { return nil }
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<ChapterTranslation>(
            predicate: #Predicate { $0.lookupKey == lookupKey }
        )
        descriptor.fetchLimit = 1
        guard let model = try? context.fetch(descriptor).first else { return nil }
        return Self.record(from: model)
    }

    /// Batch fetch — returns a `lookupKey -> record` map for the keys present
    /// in the cache. Missing keys (and rows with undecodable `translatedJSON`)
    /// are simply absent from the result.
    func translations(forKeys keys: [String]) async -> [String: ChapterTranslationRecord] {
        guard !keys.isEmpty, let modelContainer else { return [:] }
        let context = ModelContext(modelContainer)
        let wanted = Set(keys)
        let descriptor = FetchDescriptor<ChapterTranslation>(
            predicate: #Predicate { wanted.contains($0.lookupKey) }
        )
        guard let models = try? context.fetch(descriptor) else { return [:] }
        var result: [String: ChapterTranslationRecord] = [:]
        for model in models {
            // Skip corrupt rows — a miss, not a fake hit.
            if let record = Self.record(from: model) {
                result[model.lookupKey] = record
            }
        }
        return result
    }

    /// Returns the set of `unitStorageKey`s already cached for a book under a
    /// given language / provider / prompt version — lets global translate
    /// skip units it has already covered.
    func cachedUnits(
        forBookWithKey bookFingerprintKey: String,
        targetLanguage: String,
        providerProfileID: UUID,
        promptVersion: String
    ) async -> Set<String> {
        guard let modelContainer else { return [] }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChapterTranslation>(
            predicate: #Predicate {
                $0.bookFingerprintKey == bookFingerprintKey
                    && $0.targetLanguage == targetLanguage
                    && $0.providerProfileID == providerProfileID
                    && $0.promptVersion == promptVersion
            }
        )
        guard let models = try? context.fetch(descriptor) else { return [] }
        // A corrupt row does not count as covered — it must be re-translated.
        return Set(models.filter { Self.record(from: $0) != nil }.map(\.unitStorageKey))
    }

    // MARK: - Upsert

    /// Idempotently inserts or updates one translation. Fetches the existing
    /// row by `lookupKey` and updates it in place; inserts only on a miss.
    /// Never relies on the unique constraint to throw. A no-op if the store
    /// is not yet configured.
    func upsert(_ record: ChapterTranslationRecord) async throws {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        try Self.applyUpsert(record, in: context)
        try context.save()
    }

    /// Batch idempotent upsert — one save for the whole batch.
    func upsert(_ records: [ChapterTranslationRecord]) async throws {
        guard !records.isEmpty, let modelContainer else { return }
        let context = ModelContext(modelContainer)
        for record in records {
            try Self.applyUpsert(record, in: context)
        }
        try context.save()
    }

    // MARK: - Delete

    /// Removes one translation by `lookupKey` (single-unit clear — scope item 4).
    /// A missing key is a silent no-op.
    func deleteTranslation(forKey lookupKey: String) async throws {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChapterTranslation>(
            predicate: #Predicate { $0.lookupKey == lookupKey }
        )
        for model in try context.fetch(descriptor) {
            context.delete(model)
        }
        try context.save()
    }

    /// Removes every translation for a book (book delete — edge case g).
    func deleteTranslations(forBookWithKey bookFingerprintKey: String) async throws {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChapterTranslation>(
            predicate: #Predicate { $0.bookFingerprintKey == bookFingerprintKey }
        )
        for model in try context.fetch(descriptor) {
            context.delete(model)
        }
        try context.save()
    }

    // MARK: - Test support

    /// Total number of cached rows (including any corrupt rows). Test-only —
    /// never used by production code.
    func debugRowCount() async -> Int {
        guard let modelContainer else { return 0 }
        let context = ModelContext(modelContainer)
        return (try? context.fetchCount(FetchDescriptor<ChapterTranslation>())) ?? 0
    }

    /// Inserts a raw `ChapterTranslation` row with arbitrary `translatedJSON`.
    /// Test-only — used to seed a corrupt row to pin the decode-as-miss path.
    func debugInsertRaw(
        lookupKey: String,
        bookFingerprintKey: String,
        unitStorageKey: String,
        targetLanguage: String,
        providerProfileID: UUID,
        promptVersion: String,
        translatedJSON: String,
        sourceParagraphCount: Int
    ) async throws {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        context.insert(ChapterTranslation(
            lookupKey: lookupKey,
            bookFingerprintKey: bookFingerprintKey,
            unitStorageKey: unitStorageKey,
            targetLanguage: targetLanguage,
            providerProfileID: providerProfileID,
            promptVersion: promptVersion,
            translatedJSON: translatedJSON,
            sourceParagraphCount: sourceParagraphCount
        ))
        try context.save()
    }

    // MARK: - Private

    /// Inserts-or-updates without saving — the shared upsert body.
    private static func applyUpsert(
        _ record: ChapterTranslationRecord,
        in context: ModelContext
    ) throws {
        let key = record.lookupKey
        var descriptor = FetchDescriptor<ChapterTranslation>(
            predicate: #Predicate { $0.lookupKey == key }
        )
        descriptor.fetchLimit = 1
        let json = encodeSegments(record.translatedSegments)

        if let existing = try context.fetch(descriptor).first {
            existing.bookFingerprintKey = record.bookFingerprintKey
            existing.unitStorageKey = record.unitStorageKey
            existing.targetLanguage = record.targetLanguage
            existing.providerProfileID = record.providerProfileID
            existing.promptVersion = record.promptVersion
            existing.translatedJSON = json
            existing.sourceParagraphCount = record.sourceParagraphCount
            existing.createdAt = record.createdAt
        } else {
            context.insert(ChapterTranslation(
                lookupKey: key,
                bookFingerprintKey: record.bookFingerprintKey,
                unitStorageKey: record.unitStorageKey,
                targetLanguage: record.targetLanguage,
                providerProfileID: record.providerProfileID,
                promptVersion: record.promptVersion,
                translatedJSON: json,
                sourceParagraphCount: record.sourceParagraphCount,
                createdAt: record.createdAt
            ))
        }
    }

    /// Decodes a stored `@Model` into the value-type DTO. Returns `nil` when
    /// the row's `translatedJSON` is undecodable — a corrupt row must surface
    /// as a cache **miss**, never as a fake empty-translation hit (otherwise a
    /// later caller skips re-translation and serves the broken row forever).
    private static func record(from model: ChapterTranslation) -> ChapterTranslationRecord? {
        guard let segments = decodeSegments(model.translatedJSON) else { return nil }
        return ChapterTranslationRecord(
            bookFingerprintKey: model.bookFingerprintKey,
            unitStorageKey: model.unitStorageKey,
            targetLanguage: model.targetLanguage,
            providerProfileID: model.providerProfileID,
            promptVersion: model.promptVersion,
            translatedSegments: segments,
            sourceParagraphCount: model.sourceParagraphCount,
            createdAt: model.createdAt
        )
    }

    /// JSON-encodes an ordered segment array. An encode failure (not expected
    /// for `[String]`) degrades to an empty array literal.
    private static func encodeSegments(_ segments: [String]) -> String {
        guard let data = try? JSONEncoder().encode(segments),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Strictly decodes the stored `translatedJSON` into a segment array.
    /// Returns `nil` on a malformed blob — the caller treats that as a miss.
    /// A well-formed empty array `"[]"` decodes to `[]` (a legitimate value),
    /// which is why `nil` (corruption) and `[]` (empty) must stay distinct.
    private static func decodeSegments(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}
