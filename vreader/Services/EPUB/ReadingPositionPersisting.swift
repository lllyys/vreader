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
