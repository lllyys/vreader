// Purpose: Defines supported book formats for the reader.
// .md is importable as of WI-6B.

/// Supported document formats for the reader.
enum BookFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case epub
    case pdf
    case txt
    case md

    /// Formats that can be imported.
    static var importableFormats: [BookFormat] {
        [.epub, .pdf, .txt, .md]
    }

    /// Whether this format is importable.
    var isImportableV1: Bool {
        true
    }

    /// Common file extensions for this format.
    var fileExtensions: [String] {
        switch self {
        case .epub: return ["epub"]
        case .pdf: return ["pdf"]
        case .txt: return ["txt", "text"]
        case .md: return ["md", "markdown"]
        }
    }
}
