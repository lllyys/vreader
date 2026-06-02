// Purpose: Defines supported book formats for the reader.
// .md is importable as of WI-6B.
//
// @coordinates-with: FormatCapabilities.swift — `capabilities` convenience property

import Foundation

/// Supported document formats for the reader.
enum BookFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case epub
    case pdf
    case txt
    case md
    case azw3

    /// Formats that can be imported.
    static var importableFormats: [BookFormat] {
        [.epub, .pdf, .txt, .md, .azw3]
    }

    /// Whether this format is importable.
    var isImportableV1: Bool {
        true
    }

    /// Feature #42 Phase 2: whether this format is a Kindle format eligible for
    /// convert-on-import to EPUB. `.azw3` is the canonical Kindle format (it
    /// subsumes azw/mobi/prc — see `fileExtensions`).
    var isKindleConvertible: Bool {
        self == .azw3
    }

    /// Common file extensions for this format.
    var fileExtensions: [String] {
        switch self {
        case .epub: return ["epub"]
        case .pdf: return ["pdf"]
        case .txt: return ["txt", "text"]
        case .md: return ["md", "markdown"]
        case .azw3: return ["azw3", "azw", "mobi", "prc"]
        }
    }

    /// Default capabilities for this format (assumes simple EPUB).
    var capabilities: FormatCapabilities {
        FormatCapabilities.capabilities(for: self)
    }

    /// Whether the given file extension belongs to any importable BookFormat.
    /// Case-insensitive. Leading dots are stripped (so both "epub" and ".epub"
    /// match). Returns false for empty input or any extension we don't handle.
    ///
    /// Used by `FileURLImportRouter` (Feature #59 WI-2) to decide whether an
    /// incoming `file://` URL from the system Share Sheet / "Open in vreader"
    /// flow corresponds to a format vreader can import.
    static func isSupportedExtension(_ ext: String) -> Bool {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty else { return false }
        for format in BookFormat.allCases {
            if format.fileExtensions.contains(normalized) {
                return true
            }
        }
        return false
    }
}
