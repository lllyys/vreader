// Purpose: Sort options for the library view.

/// Available sort orders for the library book list.
enum LibrarySortOrder: String, Sendable, CaseIterable, Identifiable {
    case title
    case addedAt
    case lastReadAt
    case totalReadingTime

    var id: String { rawValue }

    /// Human-readable label for display in sort picker.
    var label: String {
        switch self {
        case .title: return "Title"
        case .addedAt: return "Date Added"
        case .lastReadAt: return "Last Read"
        case .totalReadingTime: return "Reading Time"
        }
    }
}
