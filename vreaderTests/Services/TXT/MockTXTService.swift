// Purpose: Mock TXT service for unit testing TXTReaderViewModel.
//
// @coordinates-with: TXTServiceProtocol.swift, TXTReaderViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of TXTServiceProtocol for unit tests.
actor MockTXTService: TXTServiceProtocol {
    /// Metadata to return on open. Nil triggers an error.
    var metadataToReturn: TXTFileMetadata?

    /// Error to throw on open.
    var openError: TXTServiceError?

    /// Whether a file is currently open.
    private(set) var _isOpen = false

    /// Count of open calls (for verifying lifecycle).
    private(set) var openCallCount = 0

    /// Count of close calls.
    private(set) var closeCallCount = 0

    var isOpen: Bool { _isOpen }

    func open(url: URL) async throws -> TXTFileMetadata {
        openCallCount += 1
        if let error = openError { throw error }
        guard let metadata = metadataToReturn else {
            throw TXTServiceError.decodingFailed("No metadata configured in mock")
        }
        _isOpen = true
        return metadata
    }

    func close() async {
        closeCallCount += 1
        _isOpen = false
    }

    // MARK: - Test Helpers

    func setMetadata(_ metadata: TXTFileMetadata?) {
        metadataToReturn = metadata
    }

    func setOpenError(_ error: TXTServiceError?) {
        openError = error
    }
}
