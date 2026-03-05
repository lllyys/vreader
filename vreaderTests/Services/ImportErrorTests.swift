// Purpose: Tests for ImportError — user messages, Equatable, all cases covered.

import Testing
import Foundation
@testable import vreader

@Suite("ImportError")
struct ImportErrorTests {

    // MARK: - User Messages

    @Test func unsupportedFormatMessage() {
        let error = ImportError.unsupportedFormat("docx")
        #expect(error.userMessage.contains("docx"))
        #expect(error.userMessage.contains("not supported"))
    }

    @Test func binaryMasqueradeMessage() {
        let error = ImportError.binaryMasquerade
        #expect(error.userMessage.contains("binary"))
    }

    @Test func fileNotReadableMessage() {
        let error = ImportError.fileNotReadable("permission denied")
        // userMessage is generic (no internal details leaked)
        #expect(error.userMessage.contains("could not be read"))
        // diagnosticMessage contains technical details
        #expect(error.diagnosticMessage.contains("permission denied"))
    }

    @Test func hashComputationFailedMessage() {
        let error = ImportError.hashComputationFailed("I/O error")
        #expect(error.userMessage.contains("file integrity"))
        #expect(error.diagnosticMessage.contains("I/O error"))
    }

    @Test func duplicateBookMessage() {
        let error = ImportError.duplicateBook(fingerprintKey: "epub:abc:1024")
        #expect(error.userMessage.contains("already in your library"))
    }

    @Test func sandboxCopyFailedMessage() {
        let error = ImportError.sandboxCopyFailed("disk full")
        #expect(error.userMessage.contains("save the file"))
        #expect(error.diagnosticMessage.contains("disk full"))
    }

    @Test func encodingDetectionFailedMessage() {
        let error = ImportError.encodingDetectionFailed
        #expect(error.userMessage.contains("encoding"))
    }

    @Test func cancelledMessage() {
        let error = ImportError.cancelled
        #expect(error.userMessage.contains("cancelled"))
    }

    @Test func securityScopeAccessDeniedMessage() {
        let error = ImportError.securityScopeAccessDenied
        #expect(error.userMessage.contains("denied"))
    }

    // MARK: - Equatable

    @Test func sameErrorsAreEqual() {
        #expect(ImportError.cancelled == ImportError.cancelled)
        #expect(ImportError.binaryMasquerade == ImportError.binaryMasquerade)
        #expect(ImportError.unsupportedFormat("docx") == ImportError.unsupportedFormat("docx"))
    }

    @Test func differentErrorsAreNotEqual() {
        #expect(ImportError.cancelled != ImportError.binaryMasquerade)
        #expect(ImportError.unsupportedFormat("docx") != ImportError.unsupportedFormat("rtf"))
    }

    // MARK: - Error Protocol Conformance

    @Test func conformsToError() {
        let error: any Error = ImportError.cancelled
        #expect(error is ImportError)
    }

    // MARK: - Edge Cases

    @Test func emptyExtensionFormat() {
        let error = ImportError.unsupportedFormat("")
        #expect(error.userMessage.contains("\"\""))
    }

    @Test func longReasonInDiagnosticMessage() {
        let longReason = String(repeating: "a", count: 1000)
        let error = ImportError.fileNotReadable(longReason)
        // userMessage is generic, diagnosticMessage has the details
        #expect(!error.userMessage.contains(longReason))
        #expect(error.diagnosticMessage.contains(longReason))
    }

    @Test func duplicateBookWithEmptyKey() {
        let error = ImportError.duplicateBook(fingerprintKey: "")
        #expect(error.userMessage.contains("already in your library"))
    }

    @Test func unicodeInErrorContext() {
        let error = ImportError.unsupportedFormat("文档.docx")
        #expect(error.userMessage.contains("文档.docx"))
    }
}
