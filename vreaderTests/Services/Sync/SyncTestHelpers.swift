// Purpose: Shared test fixtures and helpers for sync tests.
// Provides factory methods for creating test data consistently across all sync test suites.

import Foundation
@testable import vreader

/// Shared test fixtures for sync-related tests.
enum SyncTestHelpers {

    // MARK: - Fingerprints

    static let fingerprintA = DocumentFingerprint(
        contentSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        fileByteCount: 1024,
        format: .epub
    )

    static let fingerprintB = DocumentFingerprint(
        contentSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        fileByteCount: 2048,
        format: .txt
    )

    // MARK: - Dates

    /// A fixed reference date for deterministic tests.
    static let refDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// Returns refDate offset by the given number of seconds.
    static func date(offsetBy seconds: TimeInterval) -> Date {
        refDate.addingTimeInterval(seconds)
    }

    // MARK: - Locators

    static func makeLocator(
        fingerprint: DocumentFingerprint = fingerprintA,
        charOffset: Int = 0
    ) -> Locator {
        Locator(
            bookFingerprint: fingerprint,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: charOffset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Device IDs

    static let deviceA = "device-aaa"
    static let deviceB = "device-bbb"
    static let deviceC = "device-ccc"
}
