// Purpose: Feature #56 WI-14 — actor driving the "translate entire book"
// flow. Iterates the open book's translation units via
// `ChapterTextProviding`, skips units already covered in the disk cache,
// hands the rest to `ChapterTranslationService`, and emits monotonic
// `BookTranslationProgress` snapshots through an `AsyncStream` so the UI
// (badge / banner / status sheet) can re-render whenever a unit finishes.
//
// Key decisions:
// - **Actor isolation.** Internal job-map (`bookFingerprintKey -> Task`)
//   and per-book progress snapshots must serialize against concurrent
//   `start` / `cancel` / `progressUpdates` calls — actor is the simplest
//   isolation for that. The job's `Task.detached` body re-enters via
//   `await self.handleUnitCompleted(...)` so every state mutation happens
//   on the actor's serial executor.
// - **Pinned config.** The caller hands in a fully-resolved
//   `ResolvedAIProviderConfig` (WI-5 seam). The coordinator never re-resolves
//   the active profile mid-run — a profile swap or deletion after `start`
//   does not strand the in-flight job (plan acceptance + plan test
//   "active provider deleted mid-job").
// - **One job per book.** A second `start(forBook:)` while the first is
//   still running is a silent no-op. Different books run in parallel
//   without contention.
// - **Progress is monotonic.** Each unit-completion ticks `completed` by 1
//   regardless of whether the unit was a cache hit or a fresh translation
//   — the user sees one tick per unit. A zero-unit book transitions
//   straight to `.completed` with `0/0`.
// - **Cache-row clean-up on book delete** lives behind `cancelAndPurge(...)`
//   so the library card's delete affordance can cancel + wipe the cache in
//   one round-trip (plan edge case (g)).
// - **`.readerBookTranslationProgressDidChange` posted on every snapshot**
//   (declared in WI-8 / ReaderNotifications.swift) so a reader open on the
//   book can drive its `ReaderTranslateBanner` without holding a direct
//   reference to the coordinator.
//
// @coordinates-with: BookTranslationProgress.swift, ChapterTextProviding.swift,
//   ChapterTranslationService.swift, ChapterTranslationStore.swift,
//   ResolvedAIProviderConfig.swift, ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-14)

import Foundation
import OSLog

/// Actor driving the global "translate entire book" flow. At most one
/// running job per book; multiple books run in parallel.
actor BookTranslationCoordinator {

    /// App-scoped production singleton. Production callers (the Book
    /// Details + library-card UI, the `BookTranslationViewModel`) MUST
    /// use this exact instance — the singleton is what guarantees the
    /// one-job-per-book invariant. Tests inject a non-shared instance.
    static let shared = BookTranslationCoordinator(
        service: nil,
        store: .shared,
        promptVersion: "bilingual-v1")

    private let store: ChapterTranslationStore
    private let promptVersion: String
    // The service is optional so `.shared` can be created at app launch
    // before the production service is wired. `configure(service:)`
    // attaches it (idempotent — second call replaces).
    private var service: ChapterTranslationService?
    /// Feature #98: grace-window seam. Optional — nil (unwired) degrades to
    /// today's behavior: no background token, the job dies on suspension.
    private var backgroundTasks: (any BackgroundTaskRequesting)?
    /// Feature #98 WI-2: rebuilds a config from a PERSISTED profile id on
    /// resume. Optional — nil (unwired) makes `resumeInterruptedJob` a no-op.
    private var resolver: (any ProviderConfigResolving)?
    /// Feature #98 WI-2: descriptor persistence for expiry-interrupted jobs.
    private let interruptedJobs: InterruptedTranslationJobStore
    private var runningJobs: [String: Task<Void, Never>] = [:]
    private var snapshots: [String: BookTranslationProgress] = [:]
    private var continuations: [String: [UUID: AsyncStream<BookTranslationProgress>.Continuation]] = [:]
    private let log = Logger(subsystem: "com.vreader.app", category: "BookTranslationCoordinator")

    init(
        service: ChapterTranslationService?,
        store: ChapterTranslationStore,
        promptVersion: String,
        backgroundTasks: (any BackgroundTaskRequesting)? = nil,
        interruptedJobs: InterruptedTranslationJobStore = InterruptedTranslationJobStore()
    ) {
        self.service = service
        self.store = store
        self.promptVersion = promptVersion
        self.backgroundTasks = backgroundTasks
        self.interruptedJobs = interruptedJobs
    }

    /// Wires the production service onto the singleton once
    /// `VReaderApp.init()` has constructed it. Idempotent — a second
    /// call replaces the wired service (harmless; production calls once).
    /// Feature #98: also wires the background-task requester and the
    /// provider-config resolver (passing nil leaves a previously-wired
    /// value in place).
    func configure(
        service: ChapterTranslationService,
        backgroundTasks: (any BackgroundTaskRequesting)? = nil,
        resolver: (any ProviderConfigResolving)? = nil
    ) {
        self.service = service
        if let backgroundTasks { self.backgroundTasks = backgroundTasks }
        if let resolver { self.resolver = resolver }
    }

    // MARK: - Feature #98: background expiry

    /// Acquires one background token for a unit's translate, hopping to the
    /// main actor for the UIKit call. The expiration handler SETS the run's
    /// latch synchronously (Gate-4 round-2: an actor hop here can lose the
    /// race against the loop's next between-units check). Nil requester →
    /// nil token (no-op).
    private func beginUnitBackgroundToken(expiry: BackgroundExpiryLatch) async -> BackgroundExecutionToken? {
        guard let requester = backgroundTasks else { return nil }
        return await MainActor.run {
            BackgroundExecutionToken.acquire(
                name: "BookTranslation.unit", using: requester
            ) {
                expiry.set()
            }
        }
    }

    // MARK: - Estimate

    /// Returns the up-front estimate for the confirm-alert — translation
    /// unit count + a rough input-token estimate sampled from the first
    /// few units. Sampling avoids reading every unit's text on a 500-
    /// chapter book (which would defeat the up-front-estimate purpose).
    /// A book with zero units returns `unitCount: 0, approximateInputTokens: nil`.
    func estimate(
        bookFingerprintKey: String,
        textProvider: any ChapterTextProviding,
        targetLanguage: String
    ) async throws -> BookTranslationEstimate {
        let units = try await textProvider.translationUnits()
        guard !units.isEmpty else { return BookTranslationEstimate(unitCount: 0) }

        // Sample at most 5 units to estimate per-unit char count —
        // covers small books exactly and large books cheaply.
        let sampleSize = min(5, units.count)
        var sampledChars = 0
        var sampledUnits = 0
        for index in 0..<sampleSize {
            do {
                let text = try await textProvider.sourceText(for: units[index])
                sampledChars += text.count
                sampledUnits += 1
            } catch {
                // Drop this sample; a failed unit doesn't block the
                // estimate (the actual `start` will surface the error).
                continue
            }
        }
        let tokens: Int?
        if sampledUnits > 0 {
            let avgCharsPerUnit = Double(sampledChars) / Double(sampledUnits)
            let totalChars = Double(units.count) * avgCharsPerUnit
            // 4 chars/token is the standard public-facing rule of thumb
            // for English; CJK is a bit higher per token, but the 4:1
            // factor is the right ballpark for a user-facing alert.
            tokens = max(0, Int((totalChars / 4.0).rounded()))
        } else {
            tokens = nil
        }
        return BookTranslationEstimate(
            unitCount: units.count, approximateInputTokens: tokens)
    }

    // MARK: - Start

    /// Spawns the background translate-entire-book job. If a job for the
    /// same `bookFingerprintKey` is already running, this is a silent
    /// no-op (one job per book). A zero-unit book transitions straight
    /// to `.completed` at `0/0`.
    func start(
        bookFingerprintKey: String,
        textProvider: any ChapterTextProviding,
        targetLanguage: String,
        providerProfileID: UUID,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle
    ) async {
        // One job per book — silent no-op if already running.
        if runningJobs[bookFingerprintKey] != nil { return }

        // Feature #98: per-RUN expiry latch — a fresh run can never inherit
        // a stale expiry from a previous one by construction.
        let expiry = BackgroundExpiryLatch()
        // Feature #98 WI-2: the resume descriptor this run persists if its
        // background window expires. Pins the RESOLVED profile id — resume
        // must not silently switch providers.
        let resumeDescriptor = InterruptedTranslationJob(
            bookFingerprintKey: bookFingerprintKey,
            targetLanguage: targetLanguage,
            style: style,
            providerProfileID: providerProfileID)
        // Gate-4 (WI-2 round 1): a NEW run supersedes an old interrupted
        // one — refresh the retained descriptor so failure-retained resume
        // metadata tracks THIS run's provider/language/style, not the
        // expired run's (expired-with-A → manual restart with B → failure
        // must auto-resume B, not A). Runs with no prior descriptor don't
        // create one — only expiry does.
        if interruptedJobs.job(forBookWithKey: bookFingerprintKey) != nil {
            interruptedJobs.save(resumeDescriptor)
        }

        guard let service else {
            log.error("BookTranslationCoordinator: not configured with a service; ignoring start")
            return
        }

        // Resolve units + cache coverage on the coordinator's executor so
        // the initial snapshot reflects the correct `total` before the
        // first unit lands.
        let units: [TranslationUnitID]
        do { units = try await textProvider.translationUnits() }
        catch {
            updateProgress(
                forKey: bookFingerprintKey,
                phase: .failed, completed: 0, total: 0)
            return
        }

        let total = units.count
        if total == 0 {
            // Per plan: a zero-unit book completes immediately at 0/0
            // with no error and no API calls. Gate-4 (WI-2 round 1): this
            // is a COMPLETION — clear any retained descriptor like the
            // normal terminal path, or every later provider arrival would
            // re-resume an already-finished job.
            interruptedJobs.remove(forBookWithKey: bookFingerprintKey)
            updateProgress(
                forKey: bookFingerprintKey,
                phase: .completed, completed: 0, total: 0)
            return
        }

        let cachedKeys = await store.cachedUnits(
            forBookWithKey: bookFingerprintKey,
            targetLanguage: targetLanguage,
            promptVersion: promptVersion)

        // Emit a running 0/total snapshot before the first translate so the
        // banner/badge can appear immediately.
        updateProgress(
            forKey: bookFingerprintKey,
            phase: .running, completed: 0, total: total)

        let task = Task { [weak self, service] in
            var completed = 0
            for unit in units {
                if Task.isCancelled { break }
                // Feature #98: the background window expired — stop cleanly
                // BETWEEN units. Completed units are already cached (they're
                // the resume checkpoint); the `.failed` phase is the existing
                // designed "PAUSED" rendering, no new UI state. The latch
                // read is synchronous — no hop for the expiry to lose.
                if expiry.isSet {
                    await self?.recordExpiryStop(
                        forBookWithKey: bookFingerprintKey,
                        completed: completed, total: total,
                        descriptor: resumeDescriptor)
                    return
                }
                if cachedKeys.contains(unit.storageKey) {
                    completed += 1
                    await self?.recordTick(
                        forBookWithKey: bookFingerprintKey,
                        completed: completed, total: total)
                    continue
                }
                // Feature #98: renew the grace window per translated unit —
                // begin/end churn at unit cadence (seconds each) is cheap.
                let token = await self?.beginUnitBackgroundToken(expiry: expiry)
                do {
                    let sourceText = try await textProvider.sourceText(for: unit)
                    _ = try await service.translate(
                        bookFingerprintKey: bookFingerprintKey,
                        unit: unit,
                        sourceText: sourceText,
                        targetLanguage: targetLanguage,
                        providerProfileID: providerProfileID,
                        config: config,
                        style: style)
                    await token?.end()
                    completed += 1
                    await self?.recordTick(
                        forBookWithKey: bookFingerprintKey,
                        completed: completed, total: total)
                } catch is CancellationError {
                    await token?.end()
                    break
                } catch ChapterTranslationError.cancelled {
                    await token?.end()
                    break
                } catch {
                    // Provider / source-text failure stops the job. The
                    // partial progress is preserved so a later resume can
                    // pick up from cached units (idempotent).
                    await token?.end()
                    await self?.recordFailure(
                        forBookWithKey: bookFingerprintKey,
                        completed: completed, total: total)
                    return
                }
            }
            await self?.recordTerminalPhase(
                forBookWithKey: bookFingerprintKey,
                cancelled: Task.isCancelled,
                completed: completed,
                total: total)
        }
        runningJobs[bookFingerprintKey] = task
    }

    // MARK: - Cancel

    /// Cancels the running job for a book (if any). The job's
    /// `Task.checkCancellation()` between units stops the loop; the
    /// coordinator then records the `.cancelled` terminal phase.
    func cancel(bookFingerprintKey: String) {
        guard let task = runningJobs[bookFingerprintKey] else { return }
        task.cancel()
    }

    /// Cancels the running job AND removes every cached translation row
    /// for the book — used when the user deletes the book itself (plan
    /// edge case (g)).
    func cancelAndPurge(bookFingerprintKey: String) async throws {
        cancel(bookFingerprintKey: bookFingerprintKey)
        // Wait for the cancellation to land so we don't race the loop's
        // own cache write (the job's `await store.upsert(...)` would
        // otherwise resurrect a deleted row).
        if let task = runningJobs[bookFingerprintKey] {
            await task.value
        }
        // Feature #98 WI-2: a deleted book must not auto-resume either.
        interruptedJobs.remove(forBookWithKey: bookFingerprintKey)
        try await store.deleteTranslations(forBookWithKey: bookFingerprintKey)
    }

    // MARK: - Feature #98 WI-2: resume

    /// Resumes an expiry-interrupted whole-book job, called by the reader
    /// container when the book's text provider arrives (reader open — the
    /// only moment a `ChapterTextProviding` exists). Rebuilds the config
    /// from the PERSISTED `providerProfileID` through the resolver seam and
    /// re-enters `start` (the `cachedUnits` skip IS the resume). Returns
    /// whether a job was started so the caller knows to re-subscribe its VM.
    ///
    /// Deleted-profile behavior (plan-authoritative): a resolver throw logs,
    /// RETAINS the descriptor, and starts nothing — recovery is the user's
    /// normal manual re-start from Book Details. No descriptor, no resolver,
    /// or an already-running job → silent no-op (the one-job-per-book
    /// invariant absorbs duplicate calls from multiple containers).
    func resumeInterruptedJob(
        bookFingerprintKey: String,
        textProvider: any ChapterTextProviding
    ) async -> Bool {
        guard runningJobs[bookFingerprintKey] == nil else { return false }
        guard let descriptor = interruptedJobs.job(forBookWithKey: bookFingerprintKey) else {
            return false
        }
        guard let resolver else {
            log.error("resumeInterruptedJob: no resolver configured; keeping descriptor for \(bookFingerprintKey, privacy: .public)")
            return false
        }
        let config: ResolvedAIProviderConfig
        do {
            config = try await resolver.resolveProviderConfig(
                profileID: descriptor.providerProfileID, modelOverride: nil)
        } catch {
            // Deleted profile / missing key: keep the descriptor so a later
            // foreground (or a manual re-start) can retry.
            log.error("resumeInterruptedJob: resolve failed for \(bookFingerprintKey, privacy: .public): \(String(describing: error), privacy: .private)")
            return false
        }
        await start(
            bookFingerprintKey: bookFingerprintKey,
            textProvider: textProvider,
            targetLanguage: descriptor.targetLanguage,
            providerProfileID: descriptor.providerProfileID,
            config: config,
            style: descriptor.style)
        return runningJobs[bookFingerprintKey] != nil
    }

    // MARK: - Progress observation

    /// Returns the latest snapshot for a book (idle 0/0 if none has been
    /// seen).
    func currentProgress(forBookWithKey key: String) -> BookTranslationProgress {
        snapshots[key] ?? BookTranslationProgress.idle(total: 0)
    }

    /// Returns an `AsyncStream` of progress snapshots for a book. The
    /// stream replays the most recent snapshot to a late subscriber, so a
    /// view created after a job started still sees the latest state.
    func progressUpdates(forBookWithKey key: String) -> AsyncStream<BookTranslationProgress> {
        AsyncStream { continuation in
            let token = UUID()
            // Replay the latest snapshot to the new subscriber.
            if let latest = snapshots[key] {
                continuation.yield(latest)
            }
            self.registerContinuation(token: token, forKey: key, continuation: continuation)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.unregisterContinuation(token: token, forKey: key) }
            }
        }
    }

    // MARK: - Test support

    /// Waits for a book's running job (if any) to finish — test-only seam
    /// so tests don't have to poll. Throws on cancellation.
    func awaitJobForTesting(bookFingerprintKey: String) async throws {
        guard let task = runningJobs[bookFingerprintKey] else { return }
        try await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Private — state updates

    private func recordTick(forBookWithKey key: String, completed: Int, total: Int) {
        // Don't ratchet backwards: if a stray late tick lands after a
        // terminal phase was recorded, ignore it.
        if let existing = snapshots[key], !existing.isRunning && existing.phase != .idle {
            return
        }
        updateProgress(forKey: key, phase: .running, completed: completed, total: total)
    }

    private func recordTerminalPhase(
        forBookWithKey key: String,
        cancelled: Bool,
        completed: Int,
        total: Int
    ) {
        let phase: BookTranslationProgress.Phase =
            cancelled ? .cancelled : (completed >= total ? .completed : .cancelled)
        // Feature #98 WI-2: completion and user cancel both clear the resume
        // descriptor — no zombie resume. (A provider FAILURE goes through
        // `recordFailure`, which deliberately retains any descriptor so a
        // later foreground can retry.)
        interruptedJobs.remove(forBookWithKey: key)
        updateProgress(forKey: key, phase: phase, completed: completed, total: total)
        runningJobs[key] = nil
    }

    private func recordFailure(forBookWithKey key: String, completed: Int, total: Int) {
        updateProgress(forKey: key, phase: .failed, completed: completed, total: total)
        runningJobs[key] = nil
    }

    /// Feature #98: clean between-units stop after a background expiry.
    /// Reuses the `.failed` phase — the status sheet already renders it as
    /// the designed "PAUSED" state, and completed units stay cached as the
    /// resume checkpoint. WI-2: persists the resume descriptor consumed by
    /// `resumeInterruptedJob` at the next reader open.
    private func recordExpiryStop(
        forBookWithKey key: String,
        completed: Int,
        total: Int,
        descriptor: InterruptedTranslationJob
    ) {
        log.info("background window expired for \(key, privacy: .public); stopped at \(completed)/\(total) between units")
        interruptedJobs.save(descriptor)
        updateProgress(forKey: key, phase: .failed, completed: completed, total: total)
        runningJobs[key] = nil
    }

    private func updateProgress(
        forKey key: String,
        phase: BookTranslationProgress.Phase,
        completed: Int,
        total: Int
    ) {
        let snapshot = BookTranslationProgress(
            phase: phase, completed: completed, total: total)
        snapshots[key] = snapshot
        for cont in continuations[key]?.values ?? [:].values {
            cont.yield(snapshot)
        }
        // Cross-component notification — a reader open on this book uses
        // it to drive its `ReaderTranslateBanner`.
        NotificationCenter.default.post(
            name: .readerBookTranslationProgressDidChange,
            object: nil,
            userInfo: [
                "fingerprintKey": key,
                "completed": completed,
                "total": total,
                "phase": phase.rawValue,
            ])
        if phase == .completed || phase == .cancelled || phase == .failed {
            for cont in continuations[key]?.values ?? [:].values {
                cont.finish()
            }
            continuations[key] = nil
        }
    }

    private func registerContinuation(
        token: UUID,
        forKey key: String,
        continuation: AsyncStream<BookTranslationProgress>.Continuation
    ) {
        var entries = continuations[key] ?? [:]
        entries[token] = continuation
        continuations[key] = entries
    }

    private func unregisterContinuation(token: UUID, forKey key: String) {
        guard var entries = continuations[key] else { return }
        entries[token] = nil
        if entries.isEmpty {
            continuations[key] = nil
        } else {
            continuations[key] = entries
        }
    }
}
