// Purpose: Shared test helpers for collection/tag/series persistence tests.

import Foundation
import SwiftData
@testable import vreader

/// Shared test helpers for collection persistence tests.
enum CollectionTestHelper {

    /// Creates an in-memory ModelContainer with the latest schema for testing.
    /// Bumped to SchemaV5 in feature #46 WI-0a (added Book.originalExtension).
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV5.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makePersistence() throws -> PersistenceActor {
        PersistenceActor(modelContainer: try makeContainer())
    }

    static func makeFingerprint(
        sha: String = String(repeating: "a", count: 64),
        byteCount: Int64 = 1024,
        format: BookFormat = .epub
    ) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: sha, fileByteCount: byteCount, format: format
        )
    }

    static func makeProvenance() -> ImportProvenance {
        ImportProvenance(
            source: .filesApp,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalURLBookmarkData: nil
        )
    }

    /// Inserts a book via PersistenceActor and returns its fingerprint key.
    static func insertBook(
        persistence: PersistenceActor,
        title: String = "Test Book",
        sha: String = String(repeating: "a", count: 64),
        byteCount: Int64 = 1024
    ) async throws -> String {
        let fp = makeFingerprint(sha: sha, byteCount: byteCount)
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: title,
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        let result = try await persistence.insertBook(record)
        return result.fingerprintKey
    }
}
