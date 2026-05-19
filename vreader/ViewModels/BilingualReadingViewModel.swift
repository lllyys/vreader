// Purpose: Owns bilingual-reading state for the open book (feature #56).
//
// WI-7a — the persistence/state CORE only: the per-book on/off toggle backed
// by `PerBookSettings`, the target language + granularity, the per-unit
// translation dictionary, and the first-enable setup-sheet flag. WI-7b adds
// the behavioral layer (the `.readerPositionDidChange`-driven prefetch
// trigger, epoch/cancellation, `.readerBilingualDidChange` posting, the
// injected `ChapterTextProviding`).
//
// Key decisions:
// - `@Observable @MainActor` like every reader view model.
// - The toggle / language / granularity persist through `PerBookSettingsStore`
//   — a read-modify-write that PRESERVES the file's typography fields (the
//   bilingual fields are additive — WI-3).
// - The setup sheet (design §2.2) is raised the FIRST time the user enables
//   bilingual mode for a book; a book already enabled from a prior session
//   (persistence loaded `isEnabled == true` at init) does NOT re-raise it.
// - Disabling clears `translationsByUnit` (a re-enable re-fetches fresh).
//
// @coordinates-with: PerBookSettings.swift, TranslationUnitID.swift,
//   ChapterTranslationService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7a)

import Foundation
import Observation

@Observable
@MainActor
final class BilingualReadingViewModel {

    /// The book this view model is bound to (`DocumentFingerprint.canonicalKey`).
    let bookFingerprintKey: String

    /// Where per-book override JSON files live.
    private let perBookBaseURL: URL

    /// Whether bilingual mode is on for this book.
    private(set) var isEnabled: Bool

    /// The bilingual target language (a `BILINGUAL_LANGS` value). Defaults to
    /// Chinese (design §2.2).
    private(set) var targetLanguage: String

    /// The segmentation granularity. Defaults to paragraph (design §2.2).
    private(set) var granularity: TranslationGranularity

    /// Per-unit cached translations — `unit → [translated segment]`.
    private(set) var translationsByUnit: [TranslationUnitID: [String]] = [:]

    /// `true` when the first-enable setup sheet should be presented.
    private(set) var needsSetupSheet: Bool = false

    /// Default bilingual target language (design §2.2).
    static let defaultTargetLanguage = "Chinese"

    init(bookFingerprintKey: String, perBookBaseURL: URL) {
        self.bookFingerprintKey = bookFingerprintKey
        self.perBookBaseURL = perBookBaseURL

        let override = PerBookSettingsStore.settings(
            for: bookFingerprintKey, baseURL: perBookBaseURL)
        self.isEnabled = override?.bilingualEnabled ?? false
        self.targetLanguage = override?.bilingualTargetLanguage ?? Self.defaultTargetLanguage
        self.granularity = TranslationGranularity(
            rawValue: override?.bilingualGranularity ?? "") ?? .paragraph
    }

    // MARK: - Toggle

    /// Enables / disables bilingual mode for this book and persists the change.
    /// The first time it is enabled the setup sheet is raised; disabling clears
    /// the per-unit translation cache.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled && !hasBeenConfigured {
            needsSetupSheet = true
        }
        isEnabled = enabled
        if !enabled {
            translationsByUnit.removeAll()
        }
        persist()
    }

    /// Sets the target language and persists it.
    func setTargetLanguage(_ language: String) {
        guard language != targetLanguage else { return }
        targetLanguage = language
        // A language change invalidates the cached translations.
        translationsByUnit.removeAll()
        persist()
    }

    /// Sets the segmentation granularity and persists it.
    func setGranularity(_ newGranularity: TranslationGranularity) {
        guard newGranularity != granularity else { return }
        granularity = newGranularity
        translationsByUnit.removeAll()
        persist()
    }

    // MARK: - Setup sheet

    /// Marks the first-enable setup sheet as dismissed.
    func dismissSetupSheet() {
        needsSetupSheet = false
    }

    // MARK: - Translations

    /// The cached translation segments for a unit, or `nil` if not yet fetched.
    func translations(for unit: TranslationUnitID) -> [String]? {
        translationsByUnit[unit]
    }

    /// Stores translation segments for a unit.
    func setTranslations(_ segments: [String], for unit: TranslationUnitID) {
        translationsByUnit[unit] = segments
    }

    // MARK: - Private

    /// Whether the book has ever been configured for bilingual mode — true if
    /// a per-book file already carries a bilingual key. Used to decide whether
    /// the first-enable setup sheet should appear.
    private var hasBeenConfigured: Bool {
        let override = PerBookSettingsStore.settings(
            for: bookFingerprintKey, baseURL: perBookBaseURL)
        return override?.bilingualEnabled != nil
            || override?.bilingualTargetLanguage != nil
            || override?.bilingualGranularity != nil
    }

    /// Read-modify-writes the per-book override file, preserving any
    /// typography fields already present (the bilingual fields are additive).
    private func persist() {
        var override = PerBookSettingsStore.settings(
            for: bookFingerprintKey, baseURL: perBookBaseURL) ?? PerBookSettingsOverride()
        override.bilingualEnabled = isEnabled
        override.bilingualTargetLanguage = targetLanguage
        override.bilingualGranularity = granularity.rawValue
        try? PerBookSettingsStore.save(
            override, for: bookFingerprintKey, baseURL: perBookBaseURL)
    }
}
