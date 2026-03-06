// Purpose: Lightweight value type for bookmark cross-actor transfer.
// Avoids passing @Model objects across actor boundaries.

import Foundation

/// Lightweight value type representing a bookmark for cross-boundary transfer.
struct BookmarkRecord: Sendable, Equatable, Identifiable {
    var id: UUID { bookmarkId }

    let bookmarkId: UUID
    let locator: Locator
    let profileKey: String
    let title: String?
    let createdAt: Date
    let updatedAt: Date
}
