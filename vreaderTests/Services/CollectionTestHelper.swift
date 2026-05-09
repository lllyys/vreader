// Purpose: Shared test helpers for collection/tag/series persistence tests.

import CryptoKit
import Foundation
import SwiftData
@testable import vreader

/// Shared test helpers for collection persistence tests.
enum CollectionTestHelper {

    /// Creates an in-memory ModelContainer with the latest schema for testing.
    /// Bumped to SchemaV6 in feature #47 WI-1 (added Book.fileState + Book.blobPath).
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV6.models)
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

    /// Deterministic well-formed `DocumentFingerprint` derived from an arbitrary
    /// seed string. The returned fingerprint's `canonicalKey` will not equal
    /// `seed` (since `seed` typically isn't a parseable canonical key — that's
    /// the point), but it is otherwise an ordinary valid fingerprint and could
    /// in principle collide with a real book's. Used as a fallback inside
    /// `makeLocator(...)` so the rejection-path tests can run without trapping.
    static func makeBogusFingerprint(seed: String) -> DocumentFingerprint {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let sha = digest.map { String(format: "%02x", $0) }.joined()
        return DocumentFingerprint(contentSHA256: sha, fileByteCount: 0, format: .epub)
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
