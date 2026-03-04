// Purpose: Tracks a single reading session for reading statistics.
// Each session records duration, pages/words read, and start/end locators.
//
// Key decisions:
// - sessionId is @Attribute(.unique) for deduplication.
// - bookFingerprintKey is a primitive key for querying sessions by book.
// - isRecovered flags sessions that were reconstructed after a crash/force-quit.
// - Non-negative validation enforced for duration, pages, words.

import Foundation
import SwiftData

@Model
final class ReadingSession {
    @Attribute(.unique) var sessionId: UUID

    /// Primitive key for book association (matches Book.fingerprintKey).
    private(set) var bookFingerprintKey: String

    var bookFingerprint: DocumentFingerprint {
        didSet { bookFingerprintKey = bookFingerprint.canonicalKey }
    }

    var startedAt: Date
    var endedAt: Date?

    /// Duration in seconds. Always >= 0.
    var durationSeconds: Int {
        didSet { if durationSeconds < 0 { durationSeconds = 0 } }
    }

    /// Pages read during this session. Always >= 0 when set.
    var pagesRead: Int? {
        didSet { if let v = pagesRead, v < 0 { pagesRead = 0 } }
    }

    /// Words read during this session. Always >= 0 when set.
    var wordsRead: Int? {
        didSet { if let v = wordsRead, v < 0 { wordsRead = 0 } }
    }

    var startLocator: Locator?
    var endLocator: Locator?
    var deviceId: String
    var isRecovered: Bool

    /// Whether the session has valid temporal ordering.
    var hasValidTimeline: Bool {
        guard let endedAt else { return true }
        return endedAt >= startedAt
    }

    // MARK: - Init

    init(
        sessionId: UUID = UUID(),
        bookFingerprint: DocumentFingerprint,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        pagesRead: Int? = nil,
        wordsRead: Int? = nil,
        startLocator: Locator? = nil,
        endLocator: Locator? = nil,
        deviceId: String = "",
        isRecovered: Bool = false
    ) {
        self.sessionId = sessionId
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.bookFingerprint = bookFingerprint
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(0, durationSeconds)
        self.pagesRead = pagesRead.map { max(0, $0) }
        self.wordsRead = wordsRead.map { max(0, $0) }
        self.startLocator = startLocator
        self.endLocator = endLocator
        self.deviceId = deviceId
        self.isRecovered = isRecovered
    }
}
