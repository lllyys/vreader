// Purpose: Tests for DocumentFingerprint SHA validation and the validated() factory.

import Testing
import Foundation
@testable import vreader

@Suite("DocumentFingerprint Validation")
struct DocumentFingerprintValidationTests {

    static let validSHA = "abc123def456789012345678901234567890123456789012345678901234abcd"

    // MARK: - SHA-256 Format Validation

    @Test func validSHA256IsAccepted() {
        #expect(DocumentFingerprint.isValidSHA256(Self.validSHA))
    }

    @Test func emptySHAIsRejected() {
        #expect(!DocumentFingerprint.isValidSHA256(""))
    }

    @Test func shortSHAIsRejected() {
        #expect(!DocumentFingerprint.isValidSHA256("abc123"))
    }

    @Test func nonHexSHAIsRejected() {
        let nonHex = "zzzz23def456789012345678901234567890123456789012345678901234abcd"
        #expect(!DocumentFingerprint.isValidSHA256(nonHex))
    }

    @Test func uppercaseHexIsRejected() {
        let upper = "ABC123DEF456789012345678901234567890123456789012345678901234ABCD"
        #expect(!DocumentFingerprint.isValidSHA256(upper))
    }

    @Test func tooLongSHAIsRejected() {
        let tooLong = Self.validSHA + "0"
        #expect(!DocumentFingerprint.isValidSHA256(tooLong))
    }

    // MARK: - Validated Factory

    @Test func validatedReturnsNilForInvalidSHA() {
        let result = DocumentFingerprint.validated(
            contentSHA256: "",
            fileByteCount: 1024,
            format: .epub
        )
        #expect(result == nil)
    }

    @Test func validatedReturnsNilForNegativeByteCount() {
        let result = DocumentFingerprint.validated(
            contentSHA256: Self.validSHA,
            fileByteCount: -1,
            format: .epub
        )
        #expect(result == nil)
    }

    @Test func validatedReturnsFingerprint() {
        let result = DocumentFingerprint.validated(
            contentSHA256: Self.validSHA,
            fileByteCount: 1024,
            format: .epub
        )
        #expect(result != nil)
        #expect(result?.contentSHA256 == Self.validSHA)
    }

    @Test func validatedAcceptsZeroByteCount() {
        let result = DocumentFingerprint.validated(
            contentSHA256: Self.validSHA,
            fileByteCount: 0,
            format: .txt
        )
        #expect(result != nil)
    }
}
