// Purpose: No-op implementation of SessionPersisting for reader wiring.
// Session data is not persisted but the reader still displays content.
// Will be replaced with a SwiftData-backed implementation when reading
// stats persistence is fully wired.
//
// @coordinates-with: ReadingSessionTracker.swift

import Foundation

/// Minimal SessionPersisting that discards all data.
/// Allows ReadingSessionTracker to function without persistence.
@MainActor
final class NoOpSessionStore: SessionPersisting {
    func saveSession(_ session: ReadingSession) throws {}
    func discardSession(id: UUID) throws {}
    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {}
    func fetchUnclosedSessions() throws -> [ReadingSession] { [] }
}
