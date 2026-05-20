// Purpose: Owns bilingual-reading state for the open book (feature #56).
//
// WI-7a — the persistence/state CORE: the per-book on/off toggle backed by
// `PerBookSettings`, the target language + granularity, the per-unit
// translation dictionary, the first-enable setup-sheet flag.
//
// WI-7b — the behavioral layer: an injected `ChapterTextProviding` (the
// format adapter resolving `Locator → TranslationUnitID`) and a
// `ChapterPrefetching` seam (the translation fetch). `handlePositionChange`
// derives the current unit from a position `Locator`, dedupes against
// `lastTriggerUnit`, and on an actual unit change prefetches the current +
// next unit. Epoch-guarded — a counter increments on disable / book-change /
// unit-change; every prefetch `Task` captures its epoch and discards a
// stale-epoch result. An offline cache-miss is recorded in `unavailableUnits`
// (the silent-source-fallback — plan Decision 2, no invented affordance).
// `.readerBilingualDidChange` is posted whenever a renderer must react.
//
// Key decisions:
// - `@Observable @MainActor` like every reader view model.
// - The toggle / language / granularity persist through `PerBookSettingsStore`
//   — a read-modify-write that PRESERVES the file's typography fields (the
//   bilingual fields are additive — WI-3).
// - The setup sheet (design §2.2) is raised the FIRST time the user enables
//   bilingual mode for a book; a book already enabled from a prior session
//   (persistence loaded `isEnabled == true` at init) does NOT re-raise it.
// - Disabling clears `translationsByUnit` + `unavailableUnits` and resets the
//   trigger state (a re-enable re-fetches fresh).
// - A transient provider failure (not offline) leaves the unit unfetched —
//   NOT marked unavailable — so a later position change retries it.
//
// @coordinates-with: PerBookSettings.swift, TranslationUnitID.swift,
//   ChapterTextProviding.swift, ChapterPrefetching.swift, ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7a, WI-7b)

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
    var translationsByUnit: [TranslationUnitID: [String]] = [:]

    /// `true` when the first-enable setup sheet should be presented.
    private(set) var needsSetupSheet: Bool = false

    /// `true` while at least one prefetch `Task` is in flight.
    var isFetching: Bool = false

    /// Units whose translation could not be fetched because the device is
    /// offline and the unit is not cached — the silent-source-fallback set
    /// (plan Decision 2). A renderer shows source-only for these; a later
    /// online prefetch clears the entry.
    var unavailableUnits: Set<TranslationUnitID> = []

    /// Default bilingual target language (design §2.2).
    static let defaultTargetLanguage = "Chinese"

    // MARK: - WI-7b behavioral state
    //
    // These are written by the prefetch trigger in the
    // `BilingualReadingViewModel+Prefetch.swift` extension, so they cannot be
    // `private` (Swift `private` is file-scoped). They are not part of the
    // public surface — only the extension and this file touch them.

    /// Resolves `Locator → TranslationUnitID` + supplies reading order. The
    /// format host attaches the concrete adapter (Decision 2.6).
    var textProvider: (any ChapterTextProviding)?

    /// Translates a unit — the prefetch seam. Attached by the host.
    var prefetcher: (any ChapterPrefetching)?

    /// The unit the trigger last acted on — repeated position changes inside
    /// the same unit are deduped against this.
    var lastTriggerUnit: TranslationUnitID?

    /// Units with a prefetch currently in flight — guards a double-fetch.
    var inFlightUnits: Set<TranslationUnitID> = []

    /// Monotonic guard; bumps on disable / book-change / unit-change. A
    /// prefetch `Task` captures the epoch at launch and discards its result
    /// if the epoch has since moved.
    var epoch: Int = 0

    /// Monotonic per-`handlePositionChange`-call counter. The trigger captures
    /// it at entry and re-checks it after the `unit(after:)` suspension — only
    /// the LATEST request proceeds, so two position changes interleaving
    /// across the suspension cannot let the older one win.
    var triggerRequestSeq: Int = 0

    /// In-flight prefetch tasks keyed by unit, so a reset can cancel them, a
    /// completed task removes its own entry (no unbounded growth), and a test
    /// can await quiescence.
    var prefetchTasks: [TranslationUnitID: Task<Void, Never>] = [:]

    /// Cancelled-but-still-unwinding prefetch tasks, kept only so the
    /// test-only `awaitPrefetchForTesting` can fully drain them after a
    /// disable / unit-change cancels them out of `prefetchTasks`.
    var cancelledPrefetchTasks: [Task<Void, Never>] = []

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
    /// the per-unit translation cache and resets the prefetch trigger state.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled && !hasBeenConfigured {
            needsSetupSheet = true
        }
        isEnabled = enabled
        if !enabled {
            resetTriggerState()
        }
        persist()
        postDidChange()
    }

    /// Sets the target language and persists it.
    func setTargetLanguage(_ language: String) {
        guard language != targetLanguage else { return }
        targetLanguage = language
        // A language change invalidates the cached translations + the
        // prefetch trigger state — re-fetch fresh for the new language.
        resetTriggerState()
        persist()
        postDidChange()
    }

    /// Sets the segmentation granularity and persists it.
    func setGranularity(_ newGranularity: TranslationGranularity) {
        guard newGranularity != granularity else { return }
        granularity = newGranularity
        resetTriggerState()
        persist()
        postDidChange()
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

    // The WI-7b behavioral layer — `attachProvider`/`attachPrefetcher`, the
    // `handlePositionChange` prefetch trigger, epoch/cancellation, and the
    // `.readerBilingualDidChange` posting — lives in
    // `BilingualReadingViewModel+Prefetch.swift` (keeps this file under the
    // ~300-line budget, rule 50 §9).

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
