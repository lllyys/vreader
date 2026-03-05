// Purpose: Protocol abstracting EPUB parsing operations.
// Decouples the reader from Readium for testability.
//
// Key decisions:
// - Async throws for all I/O operations.
// - Sendable for safe cross-actor usage.
// - Returns value types (EPUBMetadata, etc.) not framework objects.
// - open/close lifecycle for resource management.
//
// @coordinates-with: EPUBTypes.swift, EPUBReaderViewModel.swift

import Foundation

/// Errors that can occur during EPUB parsing.
enum EPUBParserError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case invalidFormat(String)
    case parsingFailed(String)
    case notOpen
    case alreadyOpen
    case resourceNotFound(String)
}

/// Protocol for EPUB parsing operations.
/// In production, backed by Readium. In tests, backed by a mock.
/// Conformers must ensure serialized access (e.g., via actor isolation).
protocol EPUBParserProtocol: Sendable {
    /// Opens an EPUB file at the given URL. Must be called before other operations.
    func open(url: URL) async throws -> EPUBMetadata

    /// Closes the currently open publication and releases resources.
    func close() async

    /// Returns the HTML content for a given spine item href.
    func contentForSpineItem(href: String) async throws -> String

    /// Returns the base URL for resolving relative resources within the EPUB.
    func resourceBaseURL() async throws -> URL

    /// Whether a publication is currently open.
    var isOpen: Bool { get async }
}
