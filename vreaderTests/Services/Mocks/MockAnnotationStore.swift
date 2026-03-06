// Purpose: Mock annotation persistence for unit testing.
//
// @coordinates-with: AnnotationPersisting.swift, AnnotationListViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of AnnotationPersisting for unit tests.
actor MockAnnotationStore: AnnotationPersisting {
    private var annotations: [UUID: AnnotationRecord] = [:]
    private var bookIndex: [String: [UUID]] = [:]

    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var fetchCallCount = 0

    var addError: (any Error & Sendable)?
    var removeError: (any Error & Sendable)?
    var fetchError: (any Error & Sendable)?

    func addAnnotation(
        locator: Locator,
        content: String,
        toBookWithKey key: String
    ) async throws -> AnnotationRecord {
        addCallCount += 1
        if let error = addError { throw error }

        let record = AnnotationRecord(
            annotationId: UUID(),
            locator: locator,
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            content: content,
            createdAt: Date(),
            updatedAt: Date()
        )
        annotations[record.annotationId] = record
        bookIndex[key, default: []].append(record.annotationId)
        return record
    }

    func removeAnnotation(annotationId: UUID) async throws {
        removeCallCount += 1
        if let error = removeError { throw error }

        annotations.removeValue(forKey: annotationId)
        for (bookKey, ids) in bookIndex {
            bookIndex[bookKey] = ids.filter { $0 != annotationId }
        }
    }

    func updateAnnotation(annotationId: UUID, content: String) async throws {
        updateCallCount += 1
        guard let record = annotations[annotationId] else { return }
        let updated = AnnotationRecord(
            annotationId: record.annotationId,
            locator: record.locator,
            profileKey: record.profileKey,
            content: content,
            createdAt: record.createdAt,
            updatedAt: Date()
        )
        annotations[annotationId] = updated
    }

    func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord] {
        fetchCallCount += 1
        if let error = fetchError { throw error }

        let ids = bookIndex[key] ?? []
        return ids.compactMap { annotations[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Test Helpers

    func setFetchError(_ error: (any Error & Sendable)?) {
        fetchError = error
    }

    func setAddError(_ error: (any Error & Sendable)?) {
        addError = error
    }

    func seed(_ record: AnnotationRecord, forBookWithKey key: String) {
        annotations[record.annotationId] = record
        bookIndex[key, default: []].append(record.annotationId)
    }

    func allAnnotations() -> [AnnotationRecord] {
        Array(annotations.values)
    }

    func reset() {
        annotations = [:]
        bookIndex = [:]
        addCallCount = 0
        removeCallCount = 0
        updateCallCount = 0
        fetchCallCount = 0
        addError = nil
        removeError = nil
        fetchError = nil
    }
}
