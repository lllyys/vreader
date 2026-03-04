// Purpose: Baseline schema migration tests — verifies SchemaV1 model list and
// migration plan structure. Future schema versions will add migration stage tests.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("SchemaV1")
struct SchemaV1Tests {

    // MARK: - Version Identifier

    @Test func versionIsOneZeroZero() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    // MARK: - Model Registration

    @Test func allModelsAreRegistered() {
        let models = SchemaV1.models
        #expect(models.count == 7)
    }

    @Test func modelsContainBook() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("Book"))
    }

    @Test func modelsContainReadingPosition() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("ReadingPosition"))
    }

    @Test func modelsContainBookmark() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("Bookmark"))
    }

    @Test func modelsContainHighlight() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("Highlight"))
    }

    @Test func modelsContainAnnotationNote() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("AnnotationNote"))
    }

    @Test func modelsContainReadingSession() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("ReadingSession"))
    }

    @Test func modelsContainReadingStats() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        #expect(modelTypes.contains("ReadingStats"))
    }

    // MARK: - Migration Plan

    @Test func migrationPlanHasSchemaV1() {
        let schemas = VReaderMigrationPlan.schemas
        #expect(schemas.count == 1)
    }

    @Test func migrationPlanHasNoStagesYet() {
        let stages = VReaderMigrationPlan.stages
        #expect(stages.isEmpty)
    }
}
