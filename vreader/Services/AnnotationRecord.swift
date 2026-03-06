// Purpose: Lightweight value type for annotation cross-actor transfer.
// Avoids passing @Model objects across actor boundaries.

import Foundation

/// Lightweight value type representing an annotation for cross-boundary transfer.
struct AnnotationRecord: Sendable, Equatable, Identifiable {
    var id: UUID { annotationId }

    let annotationId: UUID
    let locator: Locator
    let profileKey: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
}
