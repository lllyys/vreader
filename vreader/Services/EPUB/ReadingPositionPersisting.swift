// Purpose: Protocol for reading position save/load operations.
// Decouples position persistence from SwiftData for testability.
//
// Key decisions:
// - Separate from LibraryPersisting and BookPersisting for single responsibility.
// - Methods are async throws for actor-isolated persistence.
// - Uses Locator as the canonical position type.
//
// @coordinates-with: ReadingPosition.swift, Locator.swift

import Foundation

/// Protocol for reading position persistence, enabling mock injection in tests.
/// Conformers must ensure serialized access (e.g., via actor isolation).
protocol ReadingPositionPersisting: Sendable {
    /// Loads the saved reading position for a book.
    func loadPosition(bookFingerprintKey: String) async throws -> Locator?

    /// Saves the current reading position for a book.
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws

    /// Updates the lastOpenedAt timestamp for a book.
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws

    // MARK: - Engine-agnostic envelope (Feature #42 WI-6)

    /// Saves the engine-agnostic `VReaderLocator` envelope AND the back-compat
    /// legacy `Locator` in one transaction (dual-write). Used by the Readium
    /// engine so a flag-OFF reopen still finds an approximate legacy position.
    func saveVReaderLocator(
        bookFingerprintKey: String,
        vreaderLocator: VReaderLocator,
        legacyLocator: Locator,
        deviceId: String
    ) async throws

    /// Loads the engine-agnostic `VReaderLocator` envelope for a book, or nil
    /// when none exists / the row predates the column / the blob fails to decode.
    func loadVReaderLocator(bookFingerprintKey: String) async throws -> VReaderLocator?
}

// MARK: - Default envelope implementations (Feature #42 WI-6)

/// Default no-op / nil envelope behavior so existing conformers (the legacy
/// reader VMs' test stubs, mocks) compile unchanged — only the Readium engine
/// needs envelope persistence, and only `PersistenceActor` provides the real
/// dual-write. A render-only / mock conformer that does not override these has
/// no engine-agnostic store, which is the correct posture for those contexts.
extension ReadingPositionPersisting {
    func saveVReaderLocator(
        bookFingerprintKey: String,
        vreaderLocator: VReaderLocator,
        legacyLocator: Locator,
        deviceId: String
    ) async throws {}

    func loadVReaderLocator(bookFingerprintKey: String) async throws -> VReaderLocator? {
        nil
    }
}
