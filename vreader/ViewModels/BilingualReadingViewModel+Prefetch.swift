// Purpose: Feature #56 WI-7b — the behavioral layer of
// `BilingualReadingViewModel`, split out of the main file to keep each under
// the ~300-line budget (rule 50 §9).
//
// This extension owns the unit-aware prefetch trigger: `handlePositionChange`
// derives the current `TranslationUnitID` from a position `Locator` via the
// injected `ChapterTextProviding`, dedupes against `lastTriggerUnit`, and on a
// real unit change bumps the epoch, cancels the prior epoch's in-flight
// prefetches, and prefetches the current + next unit through the
// `ChapterPrefetching` seam. A prefetch `Task` captures its epoch; a result
// from a superseded epoch is discarded. An offline cache-miss is recorded in
// `unavailableUnits` (the silent-source-fallback — plan Decision 2).
//
// Key decisions (Codex audit round 1):
// - `handlePositionChange` resolves the current + next unit **before**
//   mutating `epoch` / `lastTriggerUnit`, so a disable / unit-change during
//   the `unit(after:)` suspension cannot let a stale invocation start
//   superseded-epoch prefetches.
// - In-flight prefetch `Task`s are tracked in a `[TranslationUnitID: Task]`
//   dictionary so `finishPrefetch` removes the completed entry (no unbounded
//   growth) and `awaitPrefetchForTesting` awaits a stable snapshot.
// - A transient provider failure clears `lastTriggerUnit` when it names the
//   failed unit, so a later position change inside the same unit retries.
//
// @coordinates-with: BilingualReadingViewModel.swift, ChapterTextProviding.swift,
//   ChapterPrefetching.swift, ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7b)

import Foundation

extension BilingualReadingViewModel {

    // MARK: - Collaborators

    /// Attaches the format adapter that resolves `Locator → TranslationUnitID`.
    /// The format host calls this once after constructing the view model.
    func attachProvider(_ provider: any ChapterTextProviding) {
        textProvider = provider
    }

    /// Attaches the translation-prefetch seam. The format host calls this once
    /// after constructing the view model.
    func attachPrefetcher(_ prefetcher: any ChapterPrefetching) {
        self.prefetcher = prefetcher
    }

    // MARK: - Prefetch trigger

    /// Whether a unit's translation is unavailable (offline cache-miss).
    func isUnavailable(_ unit: TranslationUnitID) -> Bool {
        unavailableUnits.contains(unit)
    }

    /// Driven by `.readerPositionDidChange`. Derives the current unit from the
    /// position `Locator`; if the unit changed since the last trigger, bumps
    /// the epoch, cancels any in-flight prefetch, and prefetches the current +
    /// next unit. Repeated calls inside the same unit are no-ops.
    func handlePositionChange(_ locator: Locator) async {
        guard isEnabled, let provider = textProvider, prefetcher != nil else { return }
        // Claim a monotonic request token — only the latest request proceeds.
        triggerRequestSeq += 1
        let requestToken = triggerRequestSeq

        guard let currentUnit = await provider.unit(containing: locator) else { return }
        // After the `unit(containing:)` suspension: bail if a newer request
        // has been claimed, or the VM was disabled.
        guard isEnabled, requestToken == triggerRequestSeq else { return }
        // Dedupe: the position is still inside the unit the trigger last
        // acted on — nothing to do.
        guard currentUnit != lastTriggerUnit else { return }

        // Resolve the next unit BEFORE mutating any trigger state — this call
        // suspends, and a disable / another `handlePositionChange` during the
        // suspension must not let this (now stale) invocation start prefetches.
        let nextUnit = await provider.unit(after: currentUnit)

        // Re-validate after the suspension: the VM must still be enabled AND
        // this must still be the latest request. The request-token check
        // (not just `currentUnit != lastTriggerUnit`) is what defeats the
        // interleaving race — a newer request for a *different* unit bumped
        // `triggerRequestSeq`, so the older invocation stops here even though
        // its `currentUnit` differs from the newer `lastTriggerUnit`.
        guard isEnabled, requestToken == triggerRequestSeq else { return }

        // A real unit change — bump the epoch and cancel the prior epoch's
        // in-flight prefetches before starting the new ones.
        epoch += 1
        cancelInFlightPrefetches()
        lastTriggerUnit = currentUnit

        let currentEpoch = epoch
        var targets: [TranslationUnitID] = [currentUnit]
        if let nextUnit { targets.append(nextUnit) }
        for unit in targets {
            startPrefetch(unit: unit, epoch: currentEpoch)
        }
    }

    /// Test-only: awaits every prefetch `Task` — both still-registered and
    /// already-cancelled — so a test can assert deterministically after
    /// `handlePositionChange`.
    func awaitPrefetchForTesting() async {
        while !prefetchTasks.isEmpty || !cancelledPrefetchTasks.isEmpty {
            let active = Array(prefetchTasks.values)
            let cancelled = cancelledPrefetchTasks
            cancelledPrefetchTasks.removeAll()
            for task in cancelled { await task.value }
            for task in active { await task.value }
            // Drop finished+accounted active entries; loop if a new task
            // appeared (or a new cancellation occurred) while awaiting.
            for unit in prefetchTasks.keys where !inFlightUnits.contains(unit) {
                prefetchTasks.removeValue(forKey: unit)
            }
        }
    }

    // MARK: - Unit-scoped retry (Feature #56 WI-13)

    /// Retry one unit's translation fetch. Designed for the PDF
    /// offline-state CTA — and reusable by any future per-format
    /// retry affordance — when the user wants a single offline unit
    /// re-fetched without nuking the rest of the book's cache.
    ///
    /// Removes the unit from `unavailableUnits`, clears
    /// `lastTriggerUnit` only if it equals the retried unit (so the
    /// next position change is not deduped), bumps the epoch, then
    /// schedules a fresh prefetch via the same `startPrefetch` seam
    /// `handlePositionChange` uses. Other units' translations and
    /// other unavailable entries are untouched.
    ///
    /// Belt-and-braces: if an in-flight task already exists for the
    /// retried unit (a rare race between the prefetch starting and
    /// the user tapping Retry), cancel it before launching the
    /// fresh one — Gate-2 v5 round-2 M2.
    ///
    /// No-op when bilingual is disabled or no prefetcher is attached.
    func retryUnit(_ unit: TranslationUnitID) {
        guard isEnabled, prefetcher != nil else { return }
        if let priorTask = prefetchTasks.removeValue(forKey: unit) {
            priorTask.cancel()
            cancelledPrefetchTasks.append(priorTask)
        }
        inFlightUnits.remove(unit)
        unavailableUnits.remove(unit)
        if lastTriggerUnit == unit { lastTriggerUnit = nil }
        epoch += 1
        startPrefetch(unit: unit, epoch: epoch)
    }

    // MARK: - Reset + notification (called from the main file's toggle setters)

    /// Clears the per-unit translation cache + the unavailable set + the
    /// prefetch trigger state, and bumps the epoch so any in-flight result is
    /// discarded. Called on disable / language / granularity change.
    func resetTriggerState() {
        epoch += 1
        cancelInFlightPrefetches()
        translationsByUnit.removeAll()
        unavailableUnits.removeAll()
        lastTriggerUnit = nil
    }

    /// Posts `.readerBilingualDidChange` for this book so each format renderer
    /// re-injects / clears its interlinear translation. The userInfo
    /// carries the book's fingerprintKey (observers filter by it),
    /// the current `isEnabled`, and the current `targetLanguage` so
    /// chrome-layer observers (the parent reader's pill mirror, More-
    /// menu row state) can paint without crossing the host boundary.
    /// The renderer-side observers use `isEnabled` to decide between
    /// inject and clear.
    func postDidChange() {
        NotificationCenter.default.post(
            name: .readerBilingualDidChange, object: nil,
            userInfo: [
                "fingerprintKey": bookFingerprintKey,
                "isEnabled": isEnabled,
                "targetLanguage": targetLanguage
            ])
    }

    // MARK: - Private — prefetch internals

    /// The outcome of one prefetch task, applied back on the main actor.
    private enum PrefetchOutcome {
        case success([String])
        case offline
        case cancelled
        case failed
    }

    /// Launches a prefetch for one unit unless it is already cached or already
    /// in flight. The task captures `epoch`; a stale result is discarded.
    private func startPrefetch(unit: TranslationUnitID, epoch launchEpoch: Int) {
        guard translationsByUnit[unit] == nil else { return }
        guard !inFlightUnits.contains(unit) else { return }
        guard let prefetcher else { return }
        inFlightUnits.insert(unit)
        isFetching = true
        let language = targetLanguage
        let unitGranularity = granularity
        let task = Task { [weak self] in
            let outcome: PrefetchOutcome
            do {
                let segments = try await prefetcher.translatedSegments(
                    for: unit, targetLanguage: language, granularity: unitGranularity)
                outcome = .success(segments)
            } catch ChapterTranslationError.offline {
                outcome = .offline
            } catch is CancellationError {
                outcome = .cancelled
            } catch ChapterTranslationError.cancelled {
                outcome = .cancelled
            } catch {
                outcome = .failed
            }
            await self?.finishPrefetch(unit: unit, epoch: launchEpoch, outcome: outcome)
        }
        prefetchTasks[unit] = task
    }

    /// Applies a prefetch result. A result whose epoch no longer matches the
    /// current epoch is discarded (the unit changed / the VM was disabled).
    private func finishPrefetch(
        unit: TranslationUnitID, epoch resultEpoch: Int, outcome: PrefetchOutcome
    ) {
        inFlightUnits.remove(unit)
        // Only clear the task entry if it is still THIS task's — a newer
        // prefetch for the same unit (a later epoch) may have replaced it.
        if resultEpoch == epoch {
            prefetchTasks.removeValue(forKey: unit)
        }
        if inFlightUnits.isEmpty { isFetching = false }
        // Stale-epoch guard: discard a result from a superseded epoch.
        guard resultEpoch == epoch, isEnabled else { return }
        switch outcome {
        case .success(let segments):
            translationsByUnit[unit] = segments
            unavailableUnits.remove(unit)
            postDidChange()
        case .offline:
            // Silent-source-fallback — record the miss, no synthetic block.
            unavailableUnits.insert(unit)
            postDidChange()
        case .cancelled, .failed:
            // Transient: leave the unit unfetched so a later position change
            // can retry. Clearing `lastTriggerUnit` when it names this unit
            // means a subsequent position change *inside the same unit* is no
            // longer deduped away — without this the unit would only retry
            // after the reader leaves and re-enters it.
            if lastTriggerUnit == unit {
                lastTriggerUnit = nil
            }
        }
    }

    /// Cancels every in-flight prefetch `Task` and clears the in-flight set.
    /// Cancelled tasks move to `cancelledPrefetchTasks` so the test-only
    /// `awaitPrefetchForTesting` can still drain them as they unwind.
    private func cancelInFlightPrefetches() {
        for task in prefetchTasks.values {
            task.cancel()
            cancelledPrefetchTasks.append(task)
        }
        prefetchTasks.removeAll()
        inFlightUnits.removeAll()
        isFetching = false
    }
}
