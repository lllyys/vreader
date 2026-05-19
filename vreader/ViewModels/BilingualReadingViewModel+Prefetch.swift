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
        guard let currentUnit = await provider.unit(containing: locator) else { return }
        // Dedupe: the position is still inside the unit the trigger last
        // acted on — nothing to do.
        guard currentUnit != lastTriggerUnit else { return }

        // A real unit change — bump the epoch and cancel the prior epoch's
        // in-flight prefetches before starting the new ones.
        epoch += 1
        cancelInFlightPrefetches()
        lastTriggerUnit = currentUnit

        let currentEpoch = epoch
        var targets: [TranslationUnitID] = [currentUnit]
        if let next = await provider.unit(after: currentUnit) {
            targets.append(next)
        }
        for unit in targets {
            startPrefetch(unit: unit, epoch: currentEpoch)
        }
    }

    /// Test-only: awaits every in-flight prefetch `Task` so a test can assert
    /// deterministically after `handlePositionChange`.
    func awaitPrefetchForTesting() async {
        // Drain repeatedly — a prefetch could (in principle) spawn another.
        while let task = prefetchTasks.first {
            prefetchTasks.removeFirst()
            await task.value
        }
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
    /// re-injects / clears its interlinear translation.
    func postDidChange() {
        NotificationCenter.default.post(
            name: .readerBilingualDidChange, object: nil,
            userInfo: ["fingerprintKey": bookFingerprintKey])
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
        prefetchTasks.append(task)
    }

    /// Applies a prefetch result. A result whose epoch no longer matches the
    /// current epoch is discarded (the unit changed / the VM was disabled).
    private func finishPrefetch(
        unit: TranslationUnitID, epoch resultEpoch: Int, outcome: PrefetchOutcome
    ) {
        inFlightUnits.remove(unit)
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
            // is free to retry. Not marked unavailable.
            break
        }
    }

    /// Cancels every in-flight prefetch `Task` and clears the in-flight set.
    private func cancelInFlightPrefetches() {
        for task in prefetchTasks { task.cancel() }
        prefetchTasks.removeAll()
        inFlightUnits.removeAll()
        isFetching = false
    }
}
