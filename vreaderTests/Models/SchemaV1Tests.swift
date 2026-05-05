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

    @Test func migrationPlanHasSchemas() {
        // Pin V1's presence; the count grows over time as new schema versions
        // ship (V3, V4, V5, V6, …), so a hardcoded literal would drift.
        let schemaNames = VReaderMigrationPlan.schemas.map { String(describing: $0) }
        #expect(!schemaNames.isEmpty)
        #expect(schemaNames.contains("SchemaV1"))
    }

    @Test func migrationPlanHasNoExplicitStages() {
        // V1→V2 is inferred by SwiftData (additive optional field).
        let stages = VReaderMigrationPlan.stages
        #expect(stages.isEmpty)
    }
}
