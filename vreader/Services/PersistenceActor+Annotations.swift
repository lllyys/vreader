// Purpose: Extension adding AnnotationPersisting conformance to PersistenceActor.
// Provides annotation CRUD for the reader views.
//
// @coordinates-with: PersistenceActor.swift, AnnotationPersisting.swift,
//   AnnotationNote.swift, AnnotationRecord.swift

import Foundation
import SwiftData

extension PersistenceActor: AnnotationPersisting {

    func addAnnotation(
        locator: Locator,
        content: String,
        toBookWithKey key: String
    ) async throws -> AnnotationRecord {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PersistenceError.recordNotFound("Annotation content cannot be empty")
        }

        let annotation = AnnotationNote(locator: locator, content: trimmed)
        annotation.book = book
        book.annotations.append(annotation)
        context.insert(annotation)
        try context.save()

        return annotationToRecord(annotation)
    }

    func removeAnnotation(annotationId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let id = annotationId
        let predicate = #Predicate<AnnotationNote> { $0.annotationId == id }
        var descriptor = FetchDescriptor<AnnotationNote>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let annotation = try context.fetch(descriptor).first else {
            return
        }

        context.delete(annotation)
        try context.save()
    }

    func updateAnnotation(annotationId: UUID, content: String) async throws {
        let context = ModelContext(modelContainer)
        let id = annotationId
        let predicate = #Predicate<AnnotationNote> { $0.annotationId == id }
        var descriptor = FetchDescriptor<AnnotationNote>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let annotation = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound("Annotation \(annotationId)")
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw PersistenceError.recordNotFound("Annotation content cannot be empty")
        }

        annotation.content = trimmedContent
        annotation.updatedAt = Date()
        try context.save()
    }

    func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord] {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            return []
        }

        return book.annotations
            .sorted { $0.createdAt > $1.createdAt }
            .map { annotationToRecord($0) }
    }

    // MARK: - Private

    private func annotationToRecord(_ annotation: AnnotationNote) -> AnnotationRecord {
        AnnotationRecord(
            annotationId: annotation.annotationId,
            locator: annotation.locator,
            profileKey: annotation.profileKey,
            content: annotation.content,
            createdAt: annotation.createdAt,
            updatedAt: annotation.updatedAt
        )
    }
}
