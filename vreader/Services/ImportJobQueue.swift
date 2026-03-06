// Purpose: In-memory import job queue with retry, cancel, and resume support.
// Jobs are tracked in memory only; durability across app launches is out of scope
// for V1 (will be backed by a persistent store in V2).
//
// Key decisions:
// - Actor-isolated for thread safety.
// - Each job has a unique UUID for tracking.
// - State machine: pending -> running -> completed/failed/cancelled.
// - Retry count is tracked; max retries is configurable.
// - Cancelled jobs are marked terminal; callers handle cleanup externally.
//
// @coordinates-with: BookImporter.swift, ImportError.swift

import Foundation

/// State of an import job.
enum ImportJobState: Equatable, Sendable {
    case pending
    case running
    case completed(fingerprintKey: String)
    case failed(ImportError)
    case cancelled
}

/// A single import job in the queue.
struct ImportJob: Sendable, Identifiable {
    let id: UUID
    let fileURL: URL
    let source: ImportSource
    let enqueuedAt: Date
    var state: ImportJobState
    var attemptCount: Int

    init(
        id: UUID = UUID(),
        fileURL: URL,
        source: ImportSource,
        enqueuedAt: Date = Date(),
        state: ImportJobState = .pending,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.fileURL = fileURL
        self.source = source
        self.enqueuedAt = enqueuedAt
        self.state = state
        self.attemptCount = attemptCount
    }
}

/// Actor-isolated import job queue with retry and cancel support.
actor ImportJobQueue {

    /// Maximum number of retry attempts per job.
    let maxRetries: Int

    /// All jobs in the queue, keyed by ID.
    private var jobs: [UUID: ImportJob] = [:]

    /// Active task handles for cancellation support.
    private var taskHandles: [UUID: Task<Void, Never>] = [:]

    init(maxRetries: Int = 3) {
        self.maxRetries = max(0, maxRetries)
    }

    // MARK: - Queue Operations

    /// Enqueues a new import job. Returns the job ID for tracking.
    @discardableResult
    func enqueue(fileURL: URL, source: ImportSource) -> UUID {
        let job = ImportJob(fileURL: fileURL, source: source)
        jobs[job.id] = job
        return job.id
    }

    /// Cancels a job by ID. If running, cancels the underlying task.
    /// Only valid from `.pending` or `.running` state. Terminal states are immutable.
    func cancel(jobId: UUID) {
        guard var job = jobs[jobId] else { return }

        // Terminal states (.completed, .failed) are immutable
        switch job.state {
        case .completed, .failed, .cancelled:
            return
        case .pending, .running:
            break
        }

        // Cancel the running task if any
        taskHandles[jobId]?.cancel()
        taskHandles[jobId] = nil

        job.state = .cancelled
        jobs[jobId] = job
    }

    /// Returns a job by ID, or nil if not found.
    func job(byId id: UUID) -> ImportJob? {
        jobs[id]
    }

    /// Returns all jobs in the queue.
    func allJobs() -> [ImportJob] {
        Array(jobs.values).sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    /// Returns only pending jobs, sorted by enqueue time.
    func pendingJobs() -> [ImportJob] {
        jobs.values
            .filter { $0.state == .pending }
            .sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    // MARK: - State Transitions

    /// Marks a job as running. Only valid from `.pending` state.
    /// - Returns: `true` if the transition succeeded.
    @discardableResult
    func markRunning(jobId: UUID) -> Bool {
        guard var job = jobs[jobId], job.state == .pending else { return false }
        job.state = .running
        jobs[jobId] = job
        return true
    }

    /// Marks a job as completed with the given fingerprint key. Only valid from `.running` state.
    /// - Returns: `true` if the transition succeeded.
    @discardableResult
    func markCompleted(jobId: UUID, fingerprintKey: String) -> Bool {
        guard var job = jobs[jobId], job.state == .running else { return false }
        job.state = .completed(fingerprintKey: fingerprintKey)
        jobs[jobId] = job
        taskHandles[jobId] = nil
        return true
    }

    /// Marks a job as failed with the given error. Only valid from `.running` state.
    /// - Returns: `true` if the transition succeeded.
    @discardableResult
    func markFailed(jobId: UUID, error: ImportError) -> Bool {
        guard var job = jobs[jobId], job.state == .running else { return false }
        job.state = .failed(error)
        jobs[jobId] = job
        taskHandles[jobId] = nil
        return true
    }

    /// Increments the attempt count for a job. Only valid for non-terminal states.
    func incrementAttempt(jobId: UUID) {
        guard var job = jobs[jobId] else { return }
        switch job.state {
        case .completed, .failed, .cancelled:
            return
        case .pending, .running:
            break
        }
        job.attemptCount += 1
        jobs[jobId] = job
    }

    /// Returns whether the job can be retried (must be failed and under max retries).
    func canRetry(jobId: UUID) -> Bool {
        guard let job = jobs[jobId], case .failed = job.state else { return false }
        return job.attemptCount < maxRetries
    }

    /// Resets a failed job back to pending for retry.
    func resetForRetry(jobId: UUID) {
        guard var job = jobs[jobId], case .failed = job.state else { return }
        job.state = .pending
        jobs[jobId] = job
    }

    // MARK: - Cleanup

    /// Removes all completed jobs from the queue.
    func removeCompleted() {
        jobs = jobs.filter { _, job in
            if case .completed = job.state { return false }
            return true
        }
    }

    /// Removes all terminal-state jobs (completed, failed, cancelled) from the queue.
    /// Call periodically to prevent unbounded growth over long sessions.
    func removeTerminal() {
        jobs = jobs.filter { _, job in
            switch job.state {
            case .completed, .failed, .cancelled: return false
            case .pending, .running: return true
            }
        }
    }

    /// Removes all jobs from the queue.
    func removeAll() {
        for (id, _) in taskHandles {
            taskHandles[id]?.cancel()
        }
        taskHandles.removeAll()
        jobs.removeAll()
    }

    // MARK: - Task Management

    /// Associates a task handle with a job for cancellation support.
    /// If the job does not exist, the handle is cancelled immediately.
    /// If a previous handle exists for this job, it is cancelled before replacement.
    func setTaskHandle(_ handle: Task<Void, Never>, forJobId id: UUID) {
        guard let job = jobs[id] else {
            handle.cancel()
            return
        }
        // Only accept handles for non-terminal states
        switch job.state {
        case .completed, .failed, .cancelled:
            handle.cancel()
            return
        case .pending, .running:
            break
        }
        taskHandles[id]?.cancel()
        taskHandles[id] = handle
    }
}
