// Purpose: The read-only persistence boundary the Settings profile
// header depends on (feature #67). Narrow by design — only the two
// reads the profile card needs: a library book count and a windowed
// reading-seconds sum.
//
// Key decisions:
// - A protocol (not the concrete `PersistenceActor`) so
//   `SettingsHeaderViewModel` tests can mock the boundary without a
//   SwiftData store — the project pattern (`BookPersisting`,
//   `LibraryPersisting`, etc.).
// - `Sendable` so a conforming actor can be passed across the
//   `@MainActor` view-model boundary. `PersistenceActor` is an `actor`
//   and therefore already `Sendable`; its conformance is declared in
//   `PersistenceActor+ReadingWindow.swift`.
// - The protocol leaks nothing — both members are domain reads
//   (`Int` in, `Int`/`DateInterval` out). No `ModelContext`, no
//   SwiftData type appears in either signature.
//
// @coordinates-with: PersistenceActor+ReadingWindow.swift,
//   SettingsHeaderViewModel.swift

import Foundation

/// Read-only reads behind the Settings profile-header card.
protocol LibraryStatsReading: Sendable {

    /// The number of books in the library.
    func countLibraryBooks() async throws -> Int

    /// The sum of `durationSeconds` over every reading session whose
    /// `startedAt` falls within `interval` (`end` exclusive).
    func sumReadingSeconds(in interval: DateInterval) async throws -> Int
}
