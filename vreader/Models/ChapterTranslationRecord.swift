// Purpose: Value-type DTO crossing the ChapterTranslationStore actor boundary
// for feature #56 bilingual reading. The store never returns the @Model
// ChapterTranslation (context-bound) — it returns this Sendable record, the
// same pattern as BookRecord / HighlightRecord / BookmarkRecord.
//
// Key decisions:
// - `translatedSegments: [String]` is the decoded form of the @Model's
//   `translatedJSON` — consumers interleave segments without re-parsing JSON.
// - `lookupKey(...)` is the single source of truth for the canonical dedupe
//   key (`@Attribute(.unique)` on the @Model). Both the store and the
//   translation service build keys through it so they always agree.
// - The key includes ALL FIVE identity fields — a provider change (edge case
//   d) or a prompt-version bump produces a different key, so a stale row is
//   naturally bypassed by a cache miss rather than silently served.
//
// @coordinates-with: ChapterTranslation.swift, ChapterTranslationStore.swift,
//   TranslationUnitID.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-2)

import Foundation

/// Sendable DTO for one cached chapter translation.
struct ChapterTranslationRecord: Sendable, Equatable {

    /// The persisted unique dedupe key — built by `lookupKey(...)`.
    let lookupKey: String

    /// The book this translation belongs to (`DocumentFingerprint.canonicalKey`).
    let bookFingerprintKey: String

    /// The translation unit — `TranslationUnitID.storageKey`.
    let unitStorageKey: String

    /// BCP-47-ish target language tag (e.g. `"zh-Hans"`).
    let targetLanguage: String

    /// The provider profile used — matches `ProviderProfile.id`.
    let providerProfileID: UUID

    /// The translation prompt version — bumping it invalidates cached rows.
    let promptVersion: String

    /// One translated segment per source segment, in order.
    let translatedSegments: [String]

    /// The source segment count when this translation was produced.
    let sourceParagraphCount: Int

    /// When this translation was produced.
    let createdAt: Date

    init(
        bookFingerprintKey: String,
        unitStorageKey: String,
        targetLanguage: String,
        providerProfileID: UUID,
        promptVersion: String,
        translatedSegments: [String],
        sourceParagraphCount: Int,
        createdAt: Date = Date()
    ) {
        self.lookupKey = Self.lookupKey(
            bookFingerprintKey: bookFingerprintKey,
            unitStorageKey: unitStorageKey,
            targetLanguage: targetLanguage,
            providerProfileID: providerProfileID,
            promptVersion: promptVersion
        )
        self.bookFingerprintKey = bookFingerprintKey
        self.unitStorageKey = unitStorageKey
        self.targetLanguage = targetLanguage
        self.providerProfileID = providerProfileID
        self.promptVersion = promptVersion
        self.translatedSegments = translatedSegments
        self.sourceParagraphCount = sourceParagraphCount
        self.createdAt = createdAt
    }

    /// Builds the canonical `lookupKey` from the five identity fields. The
    /// single source of truth — the store and the translation service both
    /// route key construction through here so they never diverge.
    ///
    /// `|` is the field separator; none of the components legitimately
    /// contains it (`unitStorageKey` uses `:`, the UUID is hex+`-`,
    /// language tags and prompt versions are alphanumeric).
    static func lookupKey(
        bookFingerprintKey: String,
        unitStorageKey: String,
        targetLanguage: String,
        providerProfileID: UUID,
        promptVersion: String
    ) -> String {
        [
            bookFingerprintKey,
            unitStorageKey,
            targetLanguage,
            providerProfileID.uuidString,
            promptVersion,
        ].joined(separator: "|")
    }
}
