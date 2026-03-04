// Purpose: Defines the source from which a book was imported.

/// Source of a book import operation.
enum ImportSource: String, Codable, Hashable, Sendable, CaseIterable {
    case filesApp
    case shareSheet
    case icloudDrive
    case localCopy
}
