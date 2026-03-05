// Purpose: Structured domain errors for the book import pipeline.
// Each case maps to a user-facing message via the `userMessage` computed property.
//
// @coordinates-with: BookImporter.swift, ImportJobQueue.swift

import Foundation

/// Structured errors for the import pipeline.
enum ImportError: Error, Equatable, Sendable {
    /// File format is not supported for import.
    case unsupportedFormat(String)

    /// TXT file appears to be a binary file masquerading as text.
    case binaryMasquerade

    /// File could not be read (missing, permissions, etc.).
    case fileNotReadable(String)

    /// SHA-256 hash computation failed.
    case hashComputationFailed(String)

    /// A book with the same fingerprint already exists in the library.
    case duplicateBook(fingerprintKey: String)

    /// Atomic copy to sandbox failed.
    case sandboxCopyFailed(String)

    /// TXT encoding could not be detected.
    case encodingDetectionFailed

    /// Import was cancelled by the user.
    case cancelled

    /// Security-scoped resource access was denied.
    case securityScopeAccessDenied

    /// Book not found in persistence for the given key.
    case bookNotFound(String)

    /// User-facing error message suitable for display in UI.
    /// Keeps messages generic to avoid leaking system/path details.
    var userMessage: String {
        switch self {
        case .unsupportedFormat(let ext):
            return "The file format \"\(ext)\" is not supported."
        case .binaryMasquerade:
            return "This file appears to be a binary file, not a text document."
        case .fileNotReadable:
            return "The file could not be read. It may be missing or inaccessible."
        case .hashComputationFailed:
            return "Could not verify file integrity."
        case .duplicateBook:
            return "This book is already in your library."
        case .sandboxCopyFailed:
            return "Could not save the file to the library."
        case .encodingDetectionFailed:
            return "Could not detect the text file encoding."
        case .cancelled:
            return "Import was cancelled."
        case .securityScopeAccessDenied:
            return "Permission to access this file was denied."
        case .bookNotFound:
            return "The book could not be found in the library."
        }
    }

    /// Diagnostic message with technical details for internal logging.
    var diagnosticMessage: String {
        switch self {
        case .fileNotReadable(let reason):
            return "fileNotReadable: \(reason)"
        case .hashComputationFailed(let reason):
            return "hashComputationFailed: \(reason)"
        case .sandboxCopyFailed(let reason):
            return "sandboxCopyFailed: \(reason)"
        case .bookNotFound(let key):
            return "bookNotFound: \(key)"
        default:
            return userMessage
        }
    }
}
