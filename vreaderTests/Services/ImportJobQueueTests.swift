// Purpose: Tests for ImportJobQueue — durable job queue with retry, cancel, resume.

import Testing
import Foundation
@testable import vreader

@Suite("ImportJobQueue")
struct ImportJobQueueTests {

    // MARK: - Job State

    @Test func newJobStartsAsPending() {
        let job = ImportJob(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.txt"),
            source: .filesApp
        )
        #expect(job.state == .pending)
        #expect(job.attemptCount == 0)
    }

    @Test func jobTransitionsToRunning() {
        var job = ImportJob(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.txt"),
            source: .filesApp
        )
        job.state = .running
        #expect(job.state == .running)
    }

    @Test func jobTransitionsToCompleted() {
        var job = ImportJob(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.txt"),
            source: .filesApp
        )
        job.state = .completed(fingerprintKey: "txt:abc:100")
        if case .completed(let key) = job.state {
            #expect(key == "txt:abc:100")
        } else {
            Issue.record("Expected completed state")
        }
    }

    @Test func jobTransitionsToFailed() {
        var job = ImportJob(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.txt"),
            source: .filesApp
        )
        job.state = .failed(ImportError.fileNotReadable("test"))
        if case .failed = job.state {
            // OK
        } else {
            Issue.record("Expected failed state")
        }
    }

    @Test func jobTransitionsToCancelled() {
        var job = ImportJob(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.txt"),
            source: .filesApp
        )
        job.state = .cancelled
        #expect(job.state == .cancelled)
    }

    // MARK: - Queue Operations

    @Test func enqueueAddsJob() async {
        let queue = ImportJobQueue()
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let jobId = await queue.enqueue(fileURL: url, source: .filesApp)

        let job = await queue.job(byId: jobId)
        #expect(job != nil)
        #expect(job?.state == .pending)
    }

    @Test func cancelSetsJobCancelled() async {
        let queue = ImportJobQueue()
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let jobId = await queue.enqueue(fileURL: url, source: .filesApp)

        await queue.cancel(jobId: jobId)

        let job = await queue.job(byId: jobId)
        #expect(job?.state == .cancelled)
    }

    @Test func cancelNonexistentJobIsNoOp() async {
        let queue = ImportJobQueue()
        await queue.cancel(jobId: UUID())
        // Should not crash
    }

    @Test func allJobsReturnsAllEnqueued() async {
        let queue = ImportJobQueue()
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), source: .filesApp)
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/b.txt"), source: .filesApp)
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/c.txt"), source: .filesApp)

        let jobs = await queue.allJobs()
        #expect(jobs.count == 3)
    }

    @Test func pendingJobsFiltersCorrectly() async {
        let queue = ImportJobQueue()
        let id1 = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), source: .filesApp)
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/b.txt"), source: .filesApp)

        await queue.cancel(jobId: id1)

        let pending = await queue.pendingJobs()
        #expect(pending.count == 1)
    }

    // MARK: - Retry Tracking

    @Test func attemptCountIncrementsOnRetry() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        await queue.incrementAttempt(jobId: jobId)
        await queue.incrementAttempt(jobId: jobId)

        let job = await queue.job(byId: jobId)
        #expect(job?.attemptCount == 2)
    }

    @Test func maxRetriesRespected() async {
        let queue = ImportJobQueue(maxRetries: 3)
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Must be in .failed state for canRetry
        await queue.markRunning(jobId: jobId)
        await queue.markFailed(jobId: jobId, error: .fileNotReadable("test"))

        let canRetry1 = await queue.canRetry(jobId: jobId)
        #expect(canRetry1 == true)

        // Exhaust retries
        for _ in 0..<3 {
            await queue.incrementAttempt(jobId: jobId)
        }

        let canRetry2 = await queue.canRetry(jobId: jobId)
        #expect(canRetry2 == false)
    }

    @Test func canRetryRequiresFailedState() async {
        let queue = ImportJobQueue(maxRetries: 3)
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Pending job should not be retryable
        #expect(await queue.canRetry(jobId: jobId) == false)

        // Running job should not be retryable
        await queue.markRunning(jobId: jobId)
        #expect(await queue.canRetry(jobId: jobId) == false)
    }

    @Test func negativeMaxRetriesClampedToZero() async {
        let queue = ImportJobQueue(maxRetries: -5)
        #expect(await queue.maxRetries == 0)
    }

    // MARK: - Remove Completed

    @Test func removeCompletedClearsFinishedJobs() async {
        let queue = ImportJobQueue()
        let id1 = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), source: .filesApp)
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/b.txt"), source: .filesApp)

        // Must transition through running before completed
        await queue.markRunning(jobId: id1)
        await queue.markCompleted(jobId: id1, fingerprintKey: "txt:abc:100")
        await queue.removeCompleted()

        let jobs = await queue.allJobs()
        #expect(jobs.count == 1)
    }

    // MARK: - Edge Cases

    @Test func emptyQueueOperations() async {
        let queue = ImportJobQueue()
        #expect(await queue.allJobs().isEmpty)
        #expect(await queue.pendingJobs().isEmpty)
        await queue.removeCompleted()
        #expect(await queue.allJobs().isEmpty)
    }

    @Test func duplicateEnqueueCreatesNewJob() async {
        let queue = ImportJobQueue()
        let url = URL(fileURLWithPath: "/tmp/same.txt")
        let id1 = await queue.enqueue(fileURL: url, source: .filesApp)
        let id2 = await queue.enqueue(fileURL: url, source: .filesApp)

        #expect(id1 != id2)
        #expect(await queue.allJobs().count == 2)
    }

    @Test func markFailedRecordsError() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Must transition through running before failed
        await queue.markRunning(jobId: jobId)
        await queue.markFailed(jobId: jobId, error: ImportError.fileNotReadable("test"))

        let job = await queue.job(byId: jobId)
        if case .failed(let err) = job?.state {
            #expect(err == .fileNotReadable("test"))
        } else {
            Issue.record("Expected failed state")
        }
    }

    // MARK: - State Transition Guards

    @Test func markRunningOnlyFromPending() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Move to completed
        await queue.markRunning(jobId: jobId)
        await queue.markCompleted(jobId: jobId, fingerprintKey: "txt:abc:100")

        // Try to move completed -> running (should be no-op)
        await queue.markRunning(jobId: jobId)
        let job = await queue.job(byId: jobId)
        if case .completed = job?.state {
            // Still completed — guard worked
        } else {
            Issue.record("Expected state to remain completed")
        }
    }

    @Test func markCompletedOnlyFromRunning() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Try to complete a pending job (should be no-op)
        await queue.markCompleted(jobId: jobId, fingerprintKey: "txt:abc:100")
        let job = await queue.job(byId: jobId)
        #expect(job?.state == .pending)
    }

    @Test func markFailedOnlyFromRunning() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Try to fail a pending job (should be no-op)
        await queue.markFailed(jobId: jobId, error: .fileNotReadable("test"))
        let job = await queue.job(byId: jobId)
        #expect(job?.state == .pending)
    }

    // MARK: - Reset For Retry

    @Test func resetForRetryMovesFailedToPending() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        await queue.markRunning(jobId: jobId)
        await queue.markFailed(jobId: jobId, error: .fileNotReadable("test"))
        await queue.resetForRetry(jobId: jobId)

        let job = await queue.job(byId: jobId)
        #expect(job?.state == .pending)
    }

    @Test func resetForRetryNoOpForNonFailedJob() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        // Pending job should not be reset
        await queue.resetForRetry(jobId: jobId)
        let job = await queue.job(byId: jobId)
        #expect(job?.state == .pending)
    }

    // MARK: - Remove All

    @Test func removeAllClearsQueue() async {
        let queue = ImportJobQueue()
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), source: .filesApp)
        _ = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/b.txt"), source: .filesApp)

        await queue.removeAll()
        #expect(await queue.allJobs().isEmpty)
    }

    // MARK: - Task Handle

    @Test func setTaskHandleEnablesCancellation() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        let handle = Task<Void, Never> {
            // Long-running work that should be cancellable
            try? await Task.sleep(for: .seconds(60))
        }
        await queue.setTaskHandle(handle, forJobId: jobId)

        // Cancel should propagate through task handle
        await queue.cancel(jobId: jobId)
        let job = await queue.job(byId: jobId)
        #expect(job?.state == .cancelled)
        #expect(handle.isCancelled)
    }

    @Test func setTaskHandleForUnknownJobCancelsHandle() async {
        let queue = ImportJobQueue()
        let unknownId = UUID()

        let handle = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
        }
        await queue.setTaskHandle(handle, forJobId: unknownId)
        #expect(handle.isCancelled, "Handle for unknown job should be cancelled immediately")
    }

    // MARK: - Cancel Guards

    @Test func cancelCompletedJobIsNoOp() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        await queue.markRunning(jobId: jobId)
        await queue.markCompleted(jobId: jobId, fingerprintKey: "txt:abc:100")

        // Cancelling a completed job should be a no-op
        await queue.cancel(jobId: jobId)
        let job = await queue.job(byId: jobId)
        if case .completed = job?.state {
            // Still completed — guard worked
        } else {
            Issue.record("Expected state to remain completed after cancel attempt")
        }
    }

    @Test func cancelFailedJobIsNoOp() async {
        let queue = ImportJobQueue()
        let jobId = await queue.enqueue(fileURL: URL(fileURLWithPath: "/tmp/test.txt"), source: .filesApp)

        await queue.markRunning(jobId: jobId)
        await queue.markFailed(jobId: jobId, error: .fileNotReadable("test"))

        // Cancelling a failed job should be a no-op
        await queue.cancel(jobId: jobId)
        let job = await queue.job(byId: jobId)
        if case .failed = job?.state {
            // Still failed — guard worked
        } else {
            Issue.record("Expected state to remain failed after cancel attempt")
        }
    }
}
