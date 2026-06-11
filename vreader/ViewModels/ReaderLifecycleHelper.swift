// Purpose: Shared lifecycle logic for reader ViewModels (Phase R6).
// Extracts duplicated session tracking, position save, stats recompute,
// and periodic flush from TXT/MD/EPUB/PDF ViewModels.
//
// Key decisions:
// - Composition (has-a) rather than inheritance — each VM owns a helper instance.
// - Format-specific details (locator construction, content-loaded check) are NOT
//   in the helper. The VM passes the locator to close/onBackground/recordProgress.
// - Owns the shared state: flushTask, segmentStartDate, accumulatedActiveSeconds,
//   sessionTimeDisplay.
// - Adding a new lifecycle hook (e.g., iCloud sync on close) touches this file only.
//
// @coordinates-with: TXTReaderViewModel.swift, MDReaderViewModel.swift,
//   EPUBReaderViewModel.swift, PDFReaderViewModel.swift,
//   ReaderPositionService.swift, ReadingSessionTracker.swift

import Foundation
import Observation

/// Shared lifecycle helper for reader ViewModels.
/// Manages session tracking, position save/restore, stats recomputation,
/// and periodic flush. Each format ViewModel composes one instance.
/// Feature #101 (Gate-2 High): `@Observable` so the ticking displays are a
/// reliable SwiftUI invalidation seam through the VMs' passthroughs.
@MainActor
@Observable
final class ReaderLifecycleHelper {

    // MARK: - Constants

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Observable State

    /// Formatted session reading time (e.g., "5m"). VMs expose this to the UI.
    private(set) var sessionTimeDisplay: String?

    /// Feature #101: the combined trailing time readout
    /// ("12m read · 6h 40m total" / "4m read · first session"). nil until
    /// session time accrues AND the book totals attach — the chrome pins
    /// the pages readout meanwhile.
    private(set) var timeReadoutDisplay: String?

    // MARK: - Dependencies

    let bookFingerprintKey: String
    let bookFingerprint: DocumentFingerprint
    let positionService: ReaderPositionService
    let sessionTracker: ReadingSessionTracker
    private let positionStore: any ReadingPositionPersisting

    // MARK: - Private State

    private var flushTask: Task<Void, Never>?
    /// Feature #101: the book's total reading seconds at open (queried ONCE
    /// from the stats store — never per tick) + whether this is the book's
    /// first-ever session. The live total = this + the ticking session.
    @ObservationIgnored private var totalSecondsAtOpen: Int?
    @ObservationIgnored private var isFirstSession = false
    /// Feature #101: the once-at-open stats fetch seam (production:
    /// `PersistenceActor`; tests inject a stub). nil = totals never attach
    /// (the time readout stays nil — pages pinned).
    @ObservationIgnored private let statsStore: (any BookReadingStatsProviding)?
    /// Feature #101 (Gate-4 r1 High): the in-flight stats fetch + a session
    /// generation stamp. A slow fetch must not outlive `close()` or land on
    /// a LATER session's state — the task is cancelled on close and its
    /// result is dropped unless the generation still matches.
    @ObservationIgnored private var statsFetchTask: Task<Void, Never>?
    @ObservationIgnored private var sessionGeneration = 0
    /// Date when the current active segment started (reset on background/resume).
    private var segmentStartDate: Date?
    /// Accumulated active reading seconds (excluding paused time).
    private var accumulatedActiveSeconds: TimeInterval = 0

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        positionService: ReaderPositionService,
        sessionTracker: ReadingSessionTracker,
        positionStore: any ReadingPositionPersisting,
        statsStore: (any BookReadingStatsProviding)? = nil
    ) {
        self.statsStore = statsStore
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.positionService = positionService
        self.sessionTracker = sessionTracker
        self.positionStore = positionStore
    }

    // MARK: - Session Begin

    /// Starts a reading session and initializes timing.
    /// Throws if session tracking fails (caller should handle rollback).
    func beginSession() throws {
        try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        // Feature #101: query the book totals ONCE at session start. Until
        // it lands, `timeReadoutDisplay` stays nil and the chrome pins the
        // pages readout. The generation stamp drops a slow fetch that lands
        // after close() or after a subsequent session began (Gate-4 r1 High).
        sessionGeneration += 1
        let generation = sessionGeneration
        if totalSecondsAtOpen == nil, let statsStore {
            statsFetchTask?.cancel()
            statsFetchTask = Task { [weak self, bookFingerprintKey] in
                let record = try? await statsStore.readingStats(forBookWithKey: bookFingerprintKey)
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else {
                    return
                }
                self.attachBookTotals(
                    totalSecondsAtOpen: record?.totalReadingSeconds ?? 0,
                    isFirstSession: (record?.sessionCount ?? 0) == 0
                )
            }
        }
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0
        startPeriodicFlush()
    }

    /// Updates the lastOpenedAt timestamp for this book (non-fatal on failure).
    func updateLastOpened() async {
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )
    }

    // MARK: - Close

    /// Performs the shared close sequence.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    /// - Parameter locator: The current position locator (format-specific, built by the VM).
    ///   Pass nil if no content was loaded (skips position save).
    func close(locator: Locator?) async {
        cancelFlush()
        // Feature #101 (Gate-4 r1 High): a still-running stats fetch must not
        // re-attach totals after the reset below — cancel it and invalidate
        // its generation so a non-cancellable in-flight await drops its result.
        statsFetchTask?.cancel()
        statsFetchTask = nil
        sessionGeneration += 1

        if let locator {
            await positionService.saveNow(locator: locator)
            sessionTracker.recordProgress(locator: locator)
        }

        sessionTracker.endSessionIfNeeded()

        if let persistence = positionStore as? PersistenceActor {
            try? await persistence.recomputeStats(
                bookFingerprintKey: bookFingerprintKey,
                bookFingerprint: bookFingerprint
            )
        }

        NotificationCenter.default.post(name: .readerDidClose, object: bookFingerprintKey)

        // Reset shared state so stale values don't leak into a subsequent open()
        segmentStartDate = nil
        accumulatedActiveSeconds = 0
        sessionTimeDisplay = nil
        timeReadoutDisplay = nil
        totalSecondsAtOpen = nil
        isFirstSession = false
    }

    // MARK: - Background / Foreground

    /// Saves position and pauses the session when the app moves to background.
    /// - Parameter locator: The current position locator, or nil if no content loaded.
    func onBackground(locator: Locator?) async {
        if let locator {
            await positionService.saveNow(locator: locator)
        }

        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }

        sessionTracker.pause()
        cancelFlush()
    }

    /// Resumes the session when the app returns to foreground.
    /// - Parameter alwaysResetSegment: When true, unconditionally resets segmentStartDate
    ///   (PDF behavior). When false, only sets it if nil (TXT/MD/EPUB behavior).
    /// Returns an error message if session resume fails, or nil on success.
    @discardableResult
    func onForeground(alwaysResetSegment: Bool = false) -> String? {
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            return "Failed to resume reading session."
        }
        if alwaysResetSegment {
            segmentStartDate = Date()
        } else if segmentStartDate == nil {
            segmentStartDate = Date()
        }
        startPeriodicFlush()
        return nil
    }

    // MARK: - Progress Tracking

    /// Records progress and schedules a position save.
    func recordProgressAndScheduleSave(locator: Locator) {
        sessionTracker.recordProgress(locator: locator)
        updateTimeDisplays()
        positionService.scheduleSave(locator: locator)
    }

    // MARK: - Time Display

    /// Feature #101: attach the once-at-open book totals; refreshes the
    /// combined readout immediately so an already-ticking session picks it up.
    func attachBookTotals(totalSecondsAtOpen: Int, isFirstSession: Bool) {
        self.totalSecondsAtOpen = totalSecondsAtOpen
        self.isFirstSession = isFirstSession
        refreshTimeReadout(sessionSeconds: Int(totalActiveSeconds))
    }

    /// Updates sessionTimeDisplay from accumulated + current segment time.
    func updateTimeDisplays() {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        let sessionSeconds = Int(total)
        sessionTimeDisplay = ReadingTimeFormatter.formatReadingTime(totalSeconds: sessionSeconds)
        refreshTimeReadout(sessionSeconds: sessionSeconds)
        // Feature #101 (WI-2b seam): mirror the live session display onto the
        // bus so `ReaderContainerView` can feed the Book details "This
        // session" row without reaching into host-private state. ~1 post per
        // minute — negligible.
        NotificationCenter.default.post(
            name: .readerSessionTimeDidChange,
            object: nil,
            userInfo: [
                "fingerprintKey": bookFingerprintKey,
                "display": sessionTimeDisplay ?? "",
            ])
    }

    /// Feature #101: rebuilds the combined readout. The live total = the
    /// once-at-open total + the ticking session (pure arithmetic per tick —
    /// no store query).
    private func refreshTimeReadout(sessionSeconds: Int) {
        guard let totalSecondsAtOpen else {
            timeReadoutDisplay = nil
            return
        }
        timeReadoutDisplay = ReadingTimeFormatter.combinedReadout(
            sessionSeconds: sessionSeconds,
            liveTotalSeconds: totalSecondsAtOpen + sessionSeconds,
            isFirstSession: isFirstSession
        )
    }

    /// Returns the total active seconds (accumulated + current segment).
    var totalActiveSeconds: TimeInterval {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    // MARK: - Private

    private func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.sessionFlushInterval))
                    guard let self else { break }
                    try sessionTracker.periodicFlush()
                    updateTimeDisplays()
                } catch is CancellationError {
                    break
                } catch {
                    // Non-fatal
                }
            }
        }
    }

    private func cancelFlush() {
        flushTask?.cancel()
        flushTask = nil
    }
}
