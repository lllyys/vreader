// Purpose: Mock reading position store for unit testing.
//
// @coordinates-with: ReadingPositionPersisting.swift, EPUBReaderViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of ReadingPositionPersisting for unit tests.
actor MockPositionStore: ReadingPositionPersisting {
    /// Saved positions keyed by book fingerprint key.
    private var positions: [String: Locator] = [:]

    /// Last opened timestamps keyed by book fingerprint key.
    private var lastOpened: [String: Date] = [:]

    /// Count of save calls.
    private(set) var saveCallCount = 0

    /// Count of load calls.
    private(set) var loadCallCount = 0

    /// Count of updateLastOpened calls.
    private(set) var updateLastOpenedCallCount = 0

    /// Error to throw on save.
    var saveError: (any Error & Sendable)?

    /// Error to throw on load.
    var loadError: (any Error & Sendable)?

    /// Error to throw on updateLastOpened.
    var updateLastOpenedError: (any Error & Sendable)?

    func loadPosition(bookFingerprintKey: String) async throws -> Locator? {
        loadCallCount += 1
        if let error = loadError { throw error }
        return positions[bookFingerprintKey]
    }

    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws {
        saveCallCount += 1
        if let error = saveError { throw error }
        positions[bookFingerprintKey] = locator
    }

    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {
        updateLastOpenedCallCount += 1
        if let error = updateLastOpenedError { throw error }
        lastOpened[bookFingerprintKey] = date
    }

    // MARK: - Test Helpers

    /// Seeds a position for testing restore behavior.
    func seed(bookFingerprintKey: String, locator: Locator) {
        positions[bookFingerprintKey] = locator
    }

    /// Returns the saved position for a key.
    func position(forKey key: String) -> Locator? {
        positions[key]
    }

    /// Returns the last opened date for a key.
    func lastOpenedDate(forKey key: String) -> Date? {
        lastOpened[key]
    }
}
