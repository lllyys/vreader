// Purpose: ViewModel for annotation list — load, add, remove, edit.
// Manages annotations for a single book.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Protocol-based persistence for testability.
// - Newest-first ordering.
//
// @coordinates-with: AnnotationPersisting.swift, AnnotationRecord.swift, AnnotationListView.swift

import Foundation

/// ViewModel for annotation list display and management.
@Observable
@MainActor
final class AnnotationListViewModel {

    // MARK: - Published State

    /// All annotations for the current book, newest first.
    private(set) var annotations: [AnnotationRecord] = []

    /// Whether the annotation list is empty.
    var isEmpty: Bool { annotations.isEmpty }

    /// Error message from the last failed operation.
    var errorMessage: String?

    // MARK: - Dependencies

    private let bookFingerprintKey: String
    private let store: any AnnotationPersisting

    // MARK: - Init

    init(bookFingerprintKey: String, store: any AnnotationPersisting) {
        self.bookFingerprintKey = bookFingerprintKey
        self.store = store
    }

    // MARK: - Load

    /// Loads all annotations for the current book.
    func loadAnnotations() async {
        errorMessage = nil
        do {
            annotations = try await store.fetchAnnotations(forBookWithKey: bookFingerprintKey)
        } catch {
            annotations = []
            errorMessage = "Failed to load annotations."
        }
    }

    // MARK: - Add

    /// Adds an annotation at the given locator.
    func addAnnotation(locator: Locator, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Annotation content cannot be empty."
            return
        }
        errorMessage = nil
        do {
            let record = try await store.addAnnotation(
                locator: locator,
                content: trimmed,
                toBookWithKey: bookFingerprintKey
            )
            annotations.insert(record, at: 0)
        } catch {
            errorMessage = "Failed to add annotation."
        }
    }

    // MARK: - Remove

    /// Removes an annotation by its ID.
    func removeAnnotation(annotationId: UUID) async {
        errorMessage = nil
        do {
            try await store.removeAnnotation(annotationId: annotationId)
            annotations.removeAll { $0.annotationId == annotationId }
        } catch {
            errorMessage = "Failed to remove annotation."
        }
    }

    // MARK: - Edit

    /// Updates the content of an annotation.
    func updateAnnotation(annotationId: UUID, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Annotation content cannot be empty."
            return
        }
        errorMessage = nil
        do {
            try await store.updateAnnotation(annotationId: annotationId, content: trimmed)
            if let idx = annotations.firstIndex(where: { $0.annotationId == annotationId }) {
                let old = annotations[idx]
                annotations[idx] = AnnotationRecord(
                    annotationId: old.annotationId, locator: old.locator,
                    profileKey: old.profileKey, content: trimmed,
                    createdAt: old.createdAt, updatedAt: Date()
                )
            }
        } catch {
            errorMessage = "Failed to update annotation."
        }
    }
}
