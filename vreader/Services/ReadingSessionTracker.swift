// Purpose: Shared reading session tracker with idempotent lifecycle APIs.
// One canonical session behavior for EPUB/TXT/PDF.
//
// Key decisions:
// - State machine: idle → active → pausedGrace → idle
// - MonotonicClockProtocol abstraction for testability (inject mock in tests).
// - SessionPersisting protocol decouples from SwiftData for unit testing.
// - Duration measured via monotonic uptime, not Date subtraction.
// - Pause time excluded from active duration via uptimeAtPause tracking.
// - 30s grace window for resuming after background.
// - <5s sessions discarded. >24h sessions capped at 86400s.
// - Crash recovery closes sessions with endedAt == nil, marks isRecovered.
//
// @coordinates-with: ReadingSession.swift, ReadingStats.swift

import Foundation
import os

private let logger = Logger(subsystem: "com.vreader", category: "ReadingSessionTracker")

// MARK: - Protocols

/// Abstraction over monotonic system clock for deterministic testing.
protocol MonotonicClockProtocol: Sendable {
    /// Returns the monotonic system uptime in seconds (not affected by clock changes).
    func uptime() -> TimeInterval
    /// Returns the current wall-clock date (for startedAt/endedAt display).
    func now() -> Date
}

/// Persistence boundary for session save/discard/flush operations.
@MainActor
protocol SessionPersisting {
    /// Persists a session (create or update).
    func saveSession(_ session: ReadingSession) throws
    /// Discards a session that did not meet minimum duration.
    func discardSession(id: UUID) throws
    /// Flushes the current accumulated duration for crash recovery.
    func flushDuration(sessionId: UUID, durationSeconds: Int) throws
    /// Fetches sessions that have nil endedAt (stale from crash/force-quit).
    func fetchUnclosedSessions() throws -> [ReadingSession]
}

// MARK: - Production Clock

/// Production clock using ProcessInfo.systemUptime for monotonic time.
struct SystemClock: MonotonicClockProtocol {
    func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
    func now() -> Date {
        Date()
    }
}

// MARK: - Session State

/// State machine for reading session tracking.
enum SessionState: Sendable {
    case idle
    case active(sessionId: UUID)
    case pausedGrace(sessionId: UUID, pausedAtUptime: TimeInterval)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isPausedGrace: Bool {
        if case .pausedGrace = self { return true }
        return false
    }

    var sessionId: UUID? {
        switch self {
        case .idle: return nil
        case .active(let id): return id
        case .pausedGrace(let id, _): return id
        }
    }
}

// MARK: - Tracker

/// Tracks reading sessions with idempotent start/end APIs.
///
/// Thread safety: @MainActor-isolated (UI-driven lifecycle).
@MainActor
final class ReadingSessionTracker {

    // MARK: - Constants

    /// Sessions shorter than this are discarded.
    static let minimumDurationSeconds: TimeInterval = 5

    /// Maximum session duration before capping (24 hours).
    static let maximumDurationSeconds: TimeInterval = 86400

    /// Grace period for resuming a paused session (30 seconds).
    static let gracePeriodSeconds: TimeInterval = 30

    // MARK: - Dependencies

    private var clock: MonotonicClockProtocol
    private let store: SessionPersisting
    private let deviceId: String

    // MARK: - Internal State

    private(set) var state: SessionState = .idle

    /// The current in-progress session (only valid while active/paused).
    private var currentSession: ReadingSession?

    /// The book fingerprint for the current/paused session.
    private var currentBookFingerprint: DocumentFingerprint?

    /// Accumulated active duration before any pauses (not counting pause time).
    private var accumulatedDuration: TimeInterval = 0

    /// Monotonic uptime when the current active segment started
    /// (reset on each resume from pause).
    private var segmentStartUptime: TimeInterval = 0

    /// The latest end locator recorded by recordProgress.
    private(set) var currentEndLocator: Locator?

    // MARK: - Public Accessors

    /// The session ID of the current or paused session, or nil if idle.
    var currentSessionId: UUID? { state.sessionId }

    // MARK: - Init

    init(clock: MonotonicClockProtocol, store: SessionPersisting, deviceId: String) {
        self.clock = clock
        self.store = store
        self.deviceId = deviceId
    }

    /// Updates the clock reference. Testing only.
    #if DEBUG
    func updateClock(_ newClock: MonotonicClockProtocol) {
        self.clock = newClock
    }
    #endif

    // MARK: - Lifecycle

    /// Starts a new reading session if idle, or resumes if in grace period for same book.
    /// No-op if already active for the same book.
    /// If active for a different book, ends the old session and starts a new one.
    func startSessionIfNeeded(bookFingerprint: DocumentFingerprint) throws {
        switch state {
        case .idle:
            try beginNewSession(bookFingerprint: bookFingerprint)

        case .active:
            // Already active — check if same book
            if currentBookFingerprint == bookFingerprint {
                // No-op: already tracking this book
                return
            }
            // Different book: end old, start new
            finalizeCurrentSession()
            try beginNewSession(bookFingerprint: bookFingerprint)

        case .pausedGrace(let sessionId, let pausedAtUptime):
            let elapsed = max(0, clock.uptime() - pausedAtUptime)
            if bookFingerprint == currentBookFingerprint && elapsed <= Self.gracePeriodSeconds {
                // Resume: transition back to active, don't count pause time
                state = .active(sessionId: sessionId)
                segmentStartUptime = clock.uptime()
            } else {
                // Grace expired or different book: finalize old, start new
                finalizeCurrentSession()
                try beginNewSession(bookFingerprint: bookFingerprint)
            }
        }
    }

    /// Records progress (locator update) for the current session.
    /// No-op if idle or if locator belongs to a different book.
    func recordProgress(locator: Locator) {
        guard state.sessionId != nil else { return }
        // Guard against cross-book locator updates
        guard let bookFP = currentBookFingerprint,
              locator.bookFingerprint == bookFP else { return }
        currentEndLocator = locator
    }

    /// Ends the current session. No-op if idle.
    func endSessionIfNeeded() {
        switch state {
        case .idle:
            return // no-op

        case .active, .pausedGrace:
            finalizeCurrentSession()
        }
    }

    /// Pauses the current session (e.g., app backgrounded).
    /// Transitions active → pausedGrace. No-op if not active.
    func pause() {
        guard case .active(let sessionId) = state else { return }
        // Accumulate the active segment duration before pausing
        let segmentDuration = clock.uptime() - segmentStartUptime
        accumulatedDuration += segmentDuration
        state = .pausedGrace(sessionId: sessionId, pausedAtUptime: clock.uptime())
    }

    /// Triggers a periodic flush of the current duration to the store.
    /// No-op if idle.
    func periodicFlush() throws {
        guard let sessionId = state.sessionId else { return }
        let duration = min(max(0, computeCurrentDuration()), Self.maximumDurationSeconds)
        try store.flushDuration(sessionId: sessionId, durationSeconds: Int(duration))
    }

    /// Recovers stale sessions from a previous app launch.
    /// Closes any sessions with endedAt == nil, marking them as recovered.
    /// Clamps corrupted durations to 0...86400.
    func recoverStaleSessions() throws {
        let staleSessions = try store.fetchUnclosedSessions()
        for session in staleSessions {
            let clampedDuration = min(max(0, session.durationSeconds), Int(Self.maximumDurationSeconds))
            session.updateDuration(clampedDuration)
            session.endedAt = session.startedAt.addingTimeInterval(TimeInterval(clampedDuration))
            session.isRecovered = true
            try store.saveSession(session)
        }
    }

    // MARK: - Private

    private func beginNewSession(bookFingerprint: DocumentFingerprint) throws {
        let sessionId = UUID()
        let session = ReadingSession(
            sessionId: sessionId,
            bookFingerprint: bookFingerprint,
            startedAt: clock.now(),
            deviceId: deviceId
        )

        // Save first — if this throws, state remains unchanged
        try store.saveSession(session)

        currentSession = session
        currentBookFingerprint = bookFingerprint
        segmentStartUptime = clock.uptime()
        accumulatedDuration = 0
        currentEndLocator = nil
        state = .active(sessionId: sessionId)
    }

    private func finalizeCurrentSession() {
        guard let session = currentSession else {
            resetState()
            return
        }

        var totalDuration = computeCurrentDuration()

        // Cap at 24h
        totalDuration = min(totalDuration, Self.maximumDurationSeconds)

        let durationInt = Int(totalDuration)

        // Check minimum duration
        if totalDuration < Self.minimumDurationSeconds {
            do {
                try store.discardSession(id: session.sessionId)
            } catch {
                logger.error("Failed to discard short session \(session.sessionId): \(error.localizedDescription)")
            }
            resetState()
            return
        }

        // Finalize the session
        session.endedAt = clock.now()
        session.updateDuration(durationInt)
        session.endLocator = currentEndLocator
        do {
            try store.saveSession(session)
        } catch {
            logger.error("Failed to save session \(session.sessionId): \(error.localizedDescription)")
        }

        resetState()
    }

    private func computeCurrentDuration() -> TimeInterval {
        switch state {
        case .idle:
            return 0

        case .active:
            // Accumulated from previous segments + current segment
            let currentSegment = clock.uptime() - segmentStartUptime
            return accumulatedDuration + currentSegment

        case .pausedGrace:
            // Only accumulated (current segment was added when pause() was called)
            return accumulatedDuration
        }
    }

    private func resetState() {
        state = .idle
        currentSession = nil
        currentBookFingerprint = nil
        segmentStartUptime = 0
        accumulatedDuration = 0
        currentEndLocator = nil
    }
}
