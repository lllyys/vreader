// Purpose: Protocol for book import operations, enabling mock injection in tests.
// Separates the import interface from the concrete BookImporter implementation.
//
// @coordinates-with: BookImporter.swift, LibraryViewModel.swift

import Foundation

/// Protocol for book import operations.
protocol BookImporting: Sendable {
    /// Imports a file into the library.
    ///
    /// - Parameters:
    ///   - fileURL: URL to the file to import.
    ///   - source: How the file was provided (Files app, share sheet, etc.).
    /// - Returns: The import result with book identity and metadata.
    /// - Throws: `ImportError` for all failure modes.
    func importFile(at fileURL: URL, source: ImportSource) async throws -> ImportResult
}
