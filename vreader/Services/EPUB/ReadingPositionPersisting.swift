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
}

// MARK: - Engine-agnostic envelope (Feature #42 WI-6)

/// Persistence boundary for the engine-agnostic `VReaderLocator` envelope.
/// Kept SEPARATE from `ReadingPositionPersisting` (Gate-4 round-1 Medium): a
/// default no-op/nil on the broad protocol would let a non-`PersistenceActor`
/// conformer silently drop Readium position writes — a hidden data-loss mode.
/// A dedicated protocol makes envelope persistence a hard requirement, so the
/// only thing that can be injected into `ReadiumEPUBReaderViewModel` is a real
/// envelope store (`PersistenceActor`), and the compiler enforces it.
protocol VReaderLocatorPersisting: Sendable {
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
