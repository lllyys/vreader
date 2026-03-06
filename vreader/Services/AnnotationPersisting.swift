// Purpose: Protocol for annotation persistence operations.
// Enables mock injection in tests.
//
// @coordinates-with: PersistenceActor+Annotations.swift, AnnotationRecord.swift

import Foundation

/// Protocol for annotation persistence operations, enabling mock injection in tests.
protocol AnnotationPersisting: Sendable {
    /// Adds an annotation to a book. Returns the created record.
    func addAnnotation(
        locator: Locator,
        content: String,
        toBookWithKey key: String
    ) async throws -> AnnotationRecord

    /// Removes an annotation by its ID.
    func removeAnnotation(annotationId: UUID) async throws

    /// Updates the content of an annotation.
    func updateAnnotation(annotationId: UUID, content: String) async throws

    /// Fetches all annotations for a book, ordered by creation date (newest first).
    func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord]
}
