// Purpose: DEBUG-only test data seeder for UI tests.
// Creates fixture BookRecord entries via the persistence layer.
//
// Key decisions:
// - Guarded by #if DEBUG — no effect in release builds.
// - Uses PersistenceActor.insertBook() for proper SwiftData integration.
// - Fixture fingerprints use deterministic SHA-256 hashes (not real file hashes).
// - File URLs use placeholder paths since readers are placeholders anyway.
// - Covers all 4 formats plus edge cases (long title, nil author, CJK, zero reading time).
//
// @coordinates-with: VReaderApp.swift, PersistenceActor.swift, BookRecord.swift

#if DEBUG

import Foundation

/// Creates fixture book entries for UI testing.
@MainActor
enum TestSeeder {

    /// Seeds the database with fixture books for UI test scenarios.
    ///
    /// - Parameter persistence: The persistence actor to insert books into.
    static func seedBooks(persistence: PersistenceActor) async {
        for fixture in Self.fixtures {
            do {
                _ = try await persistence.insertBook(fixture)
            } catch {
                print("[TestSeeder] Warning: failed to seed '\(fixture.title)': \(error)")
            }
        }
    }

    /// Deletes all books from the database for a clean test state.
    ///
    /// - Parameter persistence: The persistence actor to clear.
    static func clearAllBooks(persistence: PersistenceActor) async {
        do {
            let books = try await persistence.fetchAllLibraryBooks()
            for book in books {
                try await persistence.deleteBook(fingerprintKey: book.fingerprintKey)
            }
        } catch {
            print("[TestSeeder] Warning: failed to clear books: \(error)")
        }
    }

    // MARK: - Fixture Data

    /// All fixture book records for seeding.
    ///
    /// SHA-256 suffixes use only valid hex chars (0-9, a-f) to pass
    /// DocumentFingerprint validation.
    static let fixtures: [BookRecord] = [
        // Standard format fixtures
        makeRecord(
            format: .epub,
            sha256Suffix: "e00b0001",
            title: "Test EPUB Book",
            author: "Test Author",
            byteCount: 102_400
        ),
        makeRecord(
            format: .pdf,
            sha256Suffix: "0df00001",
            title: "Test PDF Document",
            author: "PDF Author",
            byteCount: 204_800
        ),
        makeRecord(
            format: .txt,
            sha256Suffix: "00a00001",
            title: "Test Plain Text",
            author: nil,
            byteCount: 1_024
        ),
        makeRecord(
            format: .md,
            sha256Suffix: "0d000001",
            title: "Test Markdown",
            author: "MD Author",
            byteCount: 2_048
        ),

        // Edge case: long title
        makeRecord(
            format: .txt,
            sha256Suffix: "10face01",
            title: "A Very Long Book Title That Should Definitely Trigger Truncation in Both Grid and List Modes",
            author: "Author Name",
            byteCount: 512
        ),

        // Edge case: CJK title
        makeRecord(
            format: .txt,
            sha256Suffix: "c0a00001",
            title: "中文日本語한국어",
            author: nil,
            byteCount: 768
        ),

        // Edge case: zero reading time (unread book)
        makeRecord(
            format: .epub,
            sha256Suffix: "00dead01",
            title: "Unread Book",
            author: "Author",
            byteCount: 51_200
        ),

        // Edge case: password-protected PDF placeholder
        makeRecord(
            format: .pdf,
            sha256Suffix: "0bead001",
            title: "Protected PDF",
            author: nil,
            byteCount: 307_200
        ),
    ]

    // MARK: - Private Helpers

    /// Creates a deterministic BookRecord for testing.
    ///
    /// SHA-256 is faked: 56 zeros + the suffix, padded to 64 hex chars.
    /// This is not a real hash but satisfies DocumentFingerprint validation.
    private static func makeRecord(
        format: BookFormat,
        sha256Suffix: String,
        title: String,
        author: String?,
        byteCount: Int64
    ) -> BookRecord {
        // Pad suffix to create a valid 64-char lowercase hex string
        let paddedHash = String(repeating: "0", count: max(0, 64 - sha256Suffix.count))
            + sha256Suffix.lowercased()
        let hash = String(paddedHash.suffix(64))

        // DocumentFingerprint.validated returns nil if hash is invalid
        // For test fixtures, we construct directly since we control the hash format
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: byteCount,
            format: format
        )

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )

        return BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: title,
            author: author,
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: format == .txt ? "utf-8" : nil,
            addedAt: Date()
        )
    }
}

#endif
