// Purpose: Mock EPUB parser for unit testing EPUBReaderViewModel.
//
// @coordinates-with: EPUBParserProtocol.swift, EPUBReaderViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of EPUBParserProtocol for unit tests.
actor MockEPUBParser: EPUBParserProtocol {
    /// Metadata to return on open. Nil triggers an error.
    var metadataToReturn: EPUBMetadata?

    /// Error to throw on open.
    var openError: EPUBParserError?

    /// Content to return for spine items, keyed by href.
    var spineContent: [String: String] = [:]

    /// Whether a publication is currently open.
    private(set) var _isOpen = false

    /// Count of open calls (for verifying lifecycle).
    private(set) var openCallCount = 0

    /// Count of close calls.
    private(set) var closeCallCount = 0

    var isOpen: Bool { _isOpen }

    func open(url: URL) async throws -> EPUBMetadata {
        openCallCount += 1
        if let error = openError { throw error }
        guard let metadata = metadataToReturn else {
            throw EPUBParserError.invalidFormat("No metadata configured in mock")
        }
        _isOpen = true
        return metadata
    }

    func close() async {
        closeCallCount += 1
        _isOpen = false
    }

    func contentForSpineItem(href: String) async throws -> String {
        guard _isOpen else { throw EPUBParserError.notOpen }
        guard let content = spineContent[href] else {
            throw EPUBParserError.resourceNotFound(href)
        }
        return content
    }

    func resourceBaseURL() async throws -> URL {
        guard _isOpen else { throw EPUBParserError.notOpen }
        return URL(fileURLWithPath: "/tmp/mock-epub/")
    }

    func extractedRootURL() async throws -> URL {
        guard _isOpen else { throw EPUBParserError.notOpen }
        return URL(fileURLWithPath: "/tmp/mock-epub/")
    }
}
