// Purpose: Defines the source from which a book was imported.

/// Source of a book import operation.
enum ImportSource: String, Codable, Hashable, Sendable, CaseIterable {
    case filesApp
    case shareSheet
    case icloudDrive
    case localCopy
    /// Materialized from a WebDAV backup blob (feature #46). Distinguished from
    /// user-driven imports so the materializer can suppress "added" UX signals
    /// when a fresh device restores 100 books at once.
    case restore
}
