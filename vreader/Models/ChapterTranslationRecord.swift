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
// - **The key is `book|unit|lang|prompt` — providerProfileID is provenance
//   METADATA, not identity (Bug #342).** One canonical translation per
//   (book, unit, language, prompt): re-translate and bilingual reading share
//   it regardless of which provider produced it, so an override re-translation
//   survives reopen and a profile re-creation doesn't orphan rows. A
//   prompt-version bump still produces a different key (stale rows bypassed
//   by a cache miss). Pre-#342 rows used a 5-field key with the profile UUID
//   baked in — `ChapterTranslationStore` lazily migrates them.
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

    /// Builds the canonical `lookupKey` from the four identity fields
    /// (Bug #342: the provider profile is provenance metadata, NOT identity —
    /// one canonical translation per book|unit|lang|prompt, shared by the
    /// bilingual prefetcher and the re-translate flow). The single source of
    /// truth — the store and the translation service both route key
    /// construction through here so they never diverge.
    ///
    /// `|` is the field separator; none of the components legitimately
    /// contains it (`unitStorageKey` uses `:`, language tags and prompt
    /// versions are alphanumeric).
    static func lookupKey(
        bookFingerprintKey: String,
        unitStorageKey: String,
        targetLanguage: String,
        promptVersion: String
    ) -> String {
        [
            bookFingerprintKey,
            unitStorageKey,
            targetLanguage,
            promptVersion,
        ].joined(separator: "|")
    }
}
