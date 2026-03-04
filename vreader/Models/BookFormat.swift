// Purpose: Defines supported book formats for the reader.
// .md is reserved and not importable in V1.

/// Supported document formats for the reader.
enum BookFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case epub
    case pdf
    case txt
    case md  // Reserved; not importable in V1

    /// Formats that can be imported in V1.
    static var importableFormats: [BookFormat] {
        [.epub, .pdf, .txt]
    }

    /// Whether this format is importable in V1.
    var isImportableV1: Bool {
        self != .md
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
