// Purpose: SwiftData @Model for the feature #56 bilingual-reading persistent
// translation cache. One row per (book, translation-unit, target language,
// provider profile, prompt version). Translations are cached to disk so they
// survive app restarts and cost no repeat API calls (scope item 2).
//
// Key decisions:
// - `lookupKey` is the @Attribute(.unique) dedupe key — a STORED primitive
//   joined at insert time from the five identity fields (a Codable struct
//   cannot be @Attribute(.unique); SchemaV1's spike documents this).
// - `unitStorageKey` is `TranslationUnitID.storageKey` — replaces the old
//   `chapterHref` since 3 of 5 reader formats have no stable href
//   (Decision 2.5).
// - `providerProfileID: UUID` matches `ProviderProfile.id`'s native type;
//   SwiftData stores UUID directly.
// - `translatedJSON` is a JSON-encoded `[String]` (one segment per source
//   paragraph/sentence, ordered) — storing the array lets the renderer
//   interleave without re-segmenting.
// - `sourceParagraphCount` lets a consumer detect a stale entry whose source
//   has since changed.
// - No @Relationship to Book — independent entity (ContentReplacementRule
//   precedent). Stored in the main container so it participates in SchemaV7.
//
// @coordinates-with: SchemaV7.swift, TranslationUnitID.swift,
//   ChapterTranslationRecord.swift, ChapterTranslationStore.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-1)

import Foundation
import SwiftData

@Model
final class ChapterTranslation {

    /// The persisted, indexed dedupe key — a stored primitive joined from the
    /// five identity fields by `ChapterTranslationRecord.lookupKey(...)`.
    @Attribute(.unique) var lookupKey: String

    /// The book this translation belongs to (`DocumentFingerprint.canonicalKey`).
    var bookFingerprintKey: String

    /// The translation unit — `TranslationUnitID.storageKey`.
    var unitStorageKey: String

    /// BCP-47-ish target language tag (e.g. `"zh-Hans"`).
    var targetLanguage: String

    /// The provider profile used — matches `ProviderProfile.id`.
    var providerProfileID: UUID

    /// The translation prompt version — bumping it invalidates cached rows.
    var promptVersion: String

    /// JSON-encoded `[String]`: one translated segment per source segment, ordered.
    var translatedJSON: String

    /// The source segment count when this row was written — detects staleness.
    var sourceParagraphCount: Int

    /// When this row was cached.
    var createdAt: Date

    init(
        lookupKey: String,
        bookFingerprintKey: String,
        unitStorageKey: String,
        targetLanguage: String,
        providerProfileID: UUID,
        promptVersion: String,
        translatedJSON: String,
        sourceParagraphCount: Int,
        createdAt: Date = Date()
    ) {
        self.lookupKey = lookupKey
        self.bookFingerprintKey = bookFingerprintKey
        self.unitStorageKey = unitStorageKey
        self.targetLanguage = targetLanguage
        self.providerProfileID = providerProfileID
        self.promptVersion = promptVersion
        self.translatedJSON = translatedJSON
        self.sourceParagraphCount = sourceParagraphCount
        self.createdAt = createdAt
    }
}
