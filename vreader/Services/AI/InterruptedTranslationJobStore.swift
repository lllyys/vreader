// Purpose: Feature #98 WI-2 — the persisted resume descriptor for a
// whole-book translation whose background grace window expired. Written by
// `BookTranslationCoordinator` on an expiry stop, cleared on completion /
// user cancel / book delete, consumed by `resumeInterruptedJob` at the next
// reader open (the only moment a `ChapterTextProviding` exists).
//
// Key decisions:
// - **`providerProfileID` is part of the descriptor** (Gate-2: resuming on
//   "current active profile" would silently switch providers mid-book).
// - **Schema versioned per entry** (`v`); unknown versions and undecodable
//   blobs are ignored, never misread (forward compat).
// - Storage is one `[bookKey: Data]` plist dictionary in UserDefaults so a
//   corrupt entry can't take down its siblings.
//
// @coordinates-with: BookTranslationCoordinator.swift,
//   ProviderConfigResolving.swift,
//   dev-docs/plans/20260611-feature-98-background-resilient-translation.md

import Foundation

/// The minimal state needed to re-enter `BookTranslationCoordinator.start`
/// for an expiry-interrupted job (unit-level progress lives in the
/// translation cache itself — `cachedUnits` IS the checkpoint).
struct InterruptedTranslationJob: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var v: Int = InterruptedTranslationJob.currentVersion
    let bookFingerprintKey: String
    let targetLanguage: String
    let style: TranslationStyle
    let providerProfileID: UUID
}

/// UserDefaults-backed store for interrupted-job descriptors. `@unchecked`
/// because `UserDefaults` carries no Sendable annotation but is documented
/// thread-safe; all use sits inside the coordinator actor anyway.
struct InterruptedTranslationJobStore: @unchecked Sendable {
    static let defaultsKey = "vreader.bookTranslation.interruptedJobs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Persists (or replaces) the descriptor for its book.
    func save(_ job: InterruptedTranslationJob) {
        guard let data = try? JSONEncoder().encode(job) else { return }
        var entries = rawEntries()
        entries[job.bookFingerprintKey] = data
        defaults.set(entries, forKey: Self.defaultsKey)
    }

    /// The descriptor for a book, or nil when absent, undecodable, or from
    /// an unknown schema version.
    func job(forBookWithKey key: String) -> InterruptedTranslationJob? {
        guard let data = rawEntries()[key],
              let job = try? JSONDecoder().decode(InterruptedTranslationJob.self, from: data),
              job.v == InterruptedTranslationJob.currentVersion
        else { return nil }
        return job
    }

    /// Removes the descriptor for a book (idempotent).
    func remove(forBookWithKey key: String) {
        var entries = rawEntries()
        guard entries.removeValue(forKey: key) != nil else { return }
        defaults.set(entries, forKey: Self.defaultsKey)
    }

    private func rawEntries() -> [String: Data] {
        // Per-VALUE tolerance (Gate-4: a whole-dictionary `as? [String: Data]`
        // cast fails if ONE value has the wrong type, and the next save/remove
        // would then rewrite the store from `{}`, dropping valid siblings).
        guard let any = defaults.dictionary(forKey: Self.defaultsKey) else { return [:] }
        return any.compactMapValues { $0 as? Data }
    }
}
