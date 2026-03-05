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

    /// Mutate via `updateBookFingerprint(_:)` — SwiftData `didSet` is unreliable.
    var bookFingerprint: DocumentFingerprint

    var startedAt: Date
    var endedAt: Date?

    /// Duration in seconds. Always >= 0. Mutate via `updateDuration(_:)`.
    var durationSeconds: Int

    /// Pages read during this session. Always >= 0 when set.
    var pagesRead: Int?

    /// Words read during this session. Always >= 0 when set.
    var wordsRead: Int?

    /// Updates the book fingerprint and syncs the derived bookFingerprintKey.
    /// Use this instead of setting `bookFingerprint` directly, because
    /// SwiftData @Model classes do not reliably fire `didSet` observers.
    func updateBookFingerprint(_ newFingerprint: DocumentFingerprint) {
        bookFingerprint = newFingerprint
        bookFingerprintKey = newFingerprint.canonicalKey
    }

    /// Updates duration with non-negative clamping.
    /// Use this instead of setting `durationSeconds` directly, because
    /// SwiftData @Model classes do not reliably fire `didSet` observers.
    func updateDuration(_ newDuration: Int) {
        durationSeconds = max(0, newDuration)
    }

    /// Updates pages read with non-negative clamping.
    func updatePagesRead(_ newPages: Int?) {
        pagesRead = newPages.map { max(0, $0) }
    }

    /// Updates words read with non-negative clamping.
    func updateWordsRead(_ newWords: Int?) {
        wordsRead = newWords.map { max(0, $0) }
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
        // Clamp invalid timeline: endedAt must not precede startedAt.
        if let end = endedAt, end < startedAt {
            self.endedAt = startedAt
        } else {
            self.endedAt = endedAt
        }
        self.durationSeconds = max(0, durationSeconds)
        self.pagesRead = pagesRead.map { max(0, $0) }
        self.wordsRead = wordsRead.map { max(0, $0) }
        self.startLocator = startLocator
        self.endLocator = endLocator
        self.deviceId = deviceId
        self.isRecovered = isRecovered
    }
}
