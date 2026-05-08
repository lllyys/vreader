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
enum TestSeeder {

    /// Seeds the database with fixture books for UI test scenarios.
    ///
    /// - Parameter persistence: The persistence actor to insert books into.
    static func seedBooks(persistence: PersistenceActor) async {
        for fixture in Self.fixtures {
            do {
                _ = try await persistence.insertBook(fixture)
            } catch {
                AppLogger.general.warning("failed to seed '\(fixture.title)': \(error)")
            }
        }
    }

    /// Seeds a single TXT book with a real file for position persistence testing.
    /// Creates a 5000-character text file in ImportedBooks/ and a matching Book record.
    static func seedPositionTest(persistence: PersistenceActor) async {
        // Clear existing data for clean state
        await clearAllBooks(persistence: persistence)

        let text = generateTestText()
        let data = Data(text.utf8)
        let hash = "0000000000000000000000000000000000000000000000000000000000f1ca5e"
        let byteCount = Int64(data.count)

        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: byteCount,
            format: .txt
        )

        // Create the file in ImportedBooks
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("txt")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )

        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Position Test Book",
            author: nil,
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed position test book: \(error)")
        }
    }

    /// Generates ~5000 characters of scrollable test content with numbered paragraphs.
    private static func generateTestText() -> String {
        var lines: [String] = []
        lines.append("Position Persistence Test Document")
        lines.append("")
        for i in 1...100 {
            lines.append("Paragraph \(i): This is test content for verifying reading position persistence. The reader should remember where you stopped reading and restore the scroll position when reopened.")
            lines.append("")
        }
        return lines.joined(separator: "\n")
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
            AppLogger.general.warning("failed to clear books: \(error)")
        }
    }

    /// UserDefaults keys that production code persists app-state to.
    /// Bug #152 (GH #426): `--uitesting` swaps the SwiftData store for
    /// in-memory but UserDefaults survives across `XCUIApplication.launch()`
    /// cycles, so empty-state UI assertions flake based on residual
    /// state from prior simulator sessions. The `--reset-preferences`
    /// launch arg invokes `clearKnownPreferences(in:)` to wipe this list.
    ///
    /// Keep this list aligned with where each subsystem persists. New
    /// UserDefaults keys added to production code should be reflected
    /// here so empty-state tests stay deterministic.
    static let knownPreferenceKeys: [String] = [
        // Library
        "library.sortOrder",
        "library.viewMode",
        // Reader (mirrors BackupSettingsKeys.all + tap zones)
        "readerTheme",
        "readerTypography",
        "readerReadingMode",
        "readerUseCustomBackground",
        "readerBackgroundOpacity",
        "readerEPUBLayout",
        "readerAutoPageTurn",
        "readerAutoPageTurnInterval",
        "readerPageTurnAnimation",
        "readerChineseConversion",
        "readerTapZoneConfig",
        // OPDS
        "opds.savedCatalogs",
        // HTTP TTS
        "httpTTSConfig",
        // AI
        "com.vreader.ai.configuration",
        "com.vreader.ai.consentGranted",
        "com.vreader.ai.consentDate",
        // WebDAV
        "com.vreader.webdav.wifiOnly",
    ]

    /// Removes every key in `knownPreferenceKeys` from the supplied
    /// `UserDefaults`. Idempotent — keys that don't exist are skipped.
    /// Bug #152 / GH #426 fix.
    ///
    /// - Parameter defaults: The store to wipe. Defaults to
    ///   `UserDefaults.standard` so production callers don't need to
    ///   know which store the app reads from. Tests can pass a
    ///   purpose-built `UserDefaults(suiteName:)` to avoid touching
    ///   the host's real preferences.
    static func clearKnownPreferences(in defaults: UserDefaults = .standard) {
        for key in knownPreferenceKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Fixture Data

    /// All fixture book records for seeding.
    ///
    /// SHA-256 suffixes use only valid hex chars (0-9, a-f) to pass
    /// DocumentFingerprint validation.
    /// Fixed dates ensure deterministic ordering across test runs.
    static let fixtures: [BookRecord] = {
        // Base date: 2024-03-01 00:00:00 UTC (700_000_000 seconds since reference date)
        let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let increment: TimeInterval = 3600 // 1 hour between fixtures

        return [
            // Standard format fixtures
            makeRecord(
                format: .epub,
                sha256Suffix: "e00b0001",
                title: "Test EPUB Book",
                author: "Test Author",
                byteCount: 102_400,
                date: baseDate
            ),
            makeRecord(
                format: .pdf,
                sha256Suffix: "0df00001",
                title: "Test PDF Document",
                author: "PDF Author",
                byteCount: 204_800,
                date: baseDate.addingTimeInterval(increment)
            ),
            makeRecord(
                format: .txt,
                sha256Suffix: "00a00001",
                title: "Test Plain Text",
                author: nil,
                byteCount: 1_024,
                date: baseDate.addingTimeInterval(increment * 2)
            ),
            makeRecord(
                format: .md,
                sha256Suffix: "0d000001",
                title: "Test Markdown",
                author: "MD Author",
                byteCount: 2_048,
                date: baseDate.addingTimeInterval(increment * 3)
            ),

            // Edge case: long title
            makeRecord(
                format: .txt,
                sha256Suffix: "10face01",
                title: "A Very Long Book Title That Should Definitely Trigger Truncation in Both Grid and List Modes",
                author: "Author Name",
                byteCount: 512,
                date: baseDate.addingTimeInterval(increment * 4)
            ),

            // Edge case: CJK title
            makeRecord(
                format: .txt,
                sha256Suffix: "c0a00001",
                title: "中文日本語한국어",
                author: nil,
                byteCount: 768,
                date: baseDate.addingTimeInterval(increment * 5)
            ),

            // Edge case: zero reading time (unread book)
            makeRecord(
                format: .epub,
                sha256Suffix: "00dead01",
                title: "Unread Book",
                author: "Author",
                byteCount: 51_200,
                date: baseDate.addingTimeInterval(increment * 6)
            ),

            // Edge case: password-protected PDF placeholder
            makeRecord(
                format: .pdf,
                sha256Suffix: "0bead001",
                title: "Protected PDF",
                author: nil,
                byteCount: 307_200,
                date: baseDate.addingTimeInterval(increment * 7)
            ),
        ]
    }()

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
        byteCount: Int64,
        date: Date
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
            importedAt: date,
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
            addedAt: date
        )
    }
}

#endif
