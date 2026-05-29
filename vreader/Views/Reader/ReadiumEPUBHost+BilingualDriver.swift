// Purpose: Feature #42 WI-11b (Gate-4 audit fixes) — the bilingual
// enumerate→prefetch→inject DRIVER for the Readium EPUB host, split out of
// `ReadiumEPUBHost+Bilingual.swift` for the 300-line budget. Owns the
// location-change enumerate trigger, the forced toggle/confirm enumerate, the
// shared enumerate→prefetch loop, the cached-translation inject, and the
// prefetch-landed re-inject. PAGED path only — continuous-scroll bilingual is
// WI-12.
//
// Gate-4 correctness fixes applied here:
//   - HIGH-1: the forced toggle/confirm enumerate passes the host's
//     `lastKnownReadiumLocator` (NOT nil), so a first-enable on the chapter the
//     user is reading resolves the visible unit instead of nil.
//   - HIGH-2 / MED-6: `ensureBilingualViewModel()` is called on open (in the
//     host `.task`), so a persisted-bilingual-on book publishes the text provider
//     and the FIRST `locationDidChange` (lastEnumeratedHref == nil) enumerates.
//   - MED-3: same-chapter duplicate enumerates are gated SYNCHRONOUSLY via
//     `ReadiumBilingualChapterTracker.shouldEnumerate(forHref:force:)` before the
//     Task launches; a forced enumerate bypasses the dedupe.
//   - MED-4: the enumerate path no-ops (after clearing) when the layout is not
//     `.paged`.
//   - MED-5: the in-flight enumerate rechecks `vm.isEnabled` after the async
//     `enumerate()` returns, before mutating the orchestrator / prefetching, so a
//     disable mid-flight does not paint stale decorations.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+Bilingual.swift,
//   ReadiumBilingualCommander.swift, EPUBBilingualOrchestrator.swift,
//   BilingualReadingViewModel.swift, EPUBBilingualPipeline.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import SwiftUI
import ReadiumShared

extension ReadiumEPUBHost {

    // MARK: - Enumerate / inject driver

    /// Runs a fresh enumerate for whatever spine is currently visible, forcing a
    /// re-enumerate even within the same chapter (the toggle/confirm path where
    /// the user just enabled on an already-rendered chapter). HIGH-1: passes the
    /// host's last-known Readium locator so the visible unit resolves — it does
    /// NOT reset the only href source to nil before using it.
    func runBilingualEnumerateForCurrentChapter() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard ReadiumBilingualChapterTracker.isBilingualSupported(
            forLayout: settingsStore.epubLayout
        ) else { return }
        // Finding B (defense in depth): NEVER enumerate while the first-enable
        // setup sheet is still pending — that would prefetch/inject under the
        // default language/granularity, skipping confirmation. The sheet is
        // already showing; enumerate runs from `confirmBilingualSetup`.
        guard ReadiumBilingualChapterTracker.reEnumerateAllowed(
            needsSetupSheet: vm.needsSetupSheet
        ) else { return }
        let locator = lastKnownReadiumLocator
        // MED-3: force the enumerate (bypass dedupe) and record the in-flight href
        // synchronously, before the Task launches.
        bilingualChapterTracker.shouldEnumerate(
            forHref: locator?.href.string, force: true
        )
        Task { await runBilingualEnumerate(currentReadiumLocator: locator) }
    }

    /// Drive the bilingual chapter-change enumerate off the navigator's
    /// `locationDidChange`. A fresh enumerate runs only when the resolved spine
    /// href changes AND bilingual is enabled; an intra-chapter scroll is deduped
    /// SYNCHRONOUSLY (MED-3) so repeated callbacks for the same href before the
    /// async enumerate completes do not schedule multiple runs. HIGH-2: for a
    /// persisted-on book this fires on the FIRST locator (lastEnumeratedHref is
    /// nil → the href differs → it enumerates).
    func handleBilingualLocationChange(_ readiumLocator: ReadiumShared.Locator) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard ReadiumBilingualChapterTracker.isBilingualSupported(
            forLayout: settingsStore.epubLayout
        ) else { return }
        guard bilingualChapterTracker.shouldEnumerate(
            forHref: readiumLocator.href.string, force: false
        ) else { return }
        Task { await runBilingualEnumerate(currentReadiumLocator: readiumLocator) }
    }

    /// The shared enumerate→prefetch driver. Enumerates the live spine via the
    /// commander, replaces the orchestrator's PAGED block bucket, marks the
    /// chapter as enumerated, and asks the VM to prefetch the current unit
    /// (resolving the unit through the seam-#3 normalized locator). The actual
    /// inject runs later, off `.readerBilingualDidChange`, once the prefetch
    /// lands.
    func runBilingualEnumerate(
        currentReadiumLocator: ReadiumShared.Locator?
    ) async {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        // Finding B (defense in depth): never enumerate while first-enable setup is
        // pending — that would prefetch under the default language/granularity.
        guard ReadiumBilingualChapterTracker.reEnumerateAllowed(
            needsSetupSheet: vm.needsSetupSheet
        ) else { return }
        let href = currentReadiumLocator?.href.string
        let result = await bilingualCommander.enumerate()
        // Gate-4 round-3 MED-2: distinguish eval FAILURE (nil) from a
        // successful-but-empty enumerate ([]). On FAILURE revert the in-flight
        // dedupe mark for this href so a later `locationDidChange` for the same
        // chapter retries — otherwise a transient eval failure / too-early eval
        // leaves the visible chapter blank forever. A genuinely-empty chapter ([])
        // is a success: COMMIT so we do not retry-loop on it.
        guard let blocks = result else {
            bilingualChapterTracker.clearInFlight(href: href)
            return
        }
        // MED-5: the user may have disabled bilingual while the async enumerate
        // was in flight. Recheck before mutating the orchestrator / prefetching —
        // the disable path's `clear()` already removed any decorations.
        guard vm.isEnabled else { return }
        bilingualOrchestrator.updateBlocks(blocks)
        // Mark the chapter enumerated so an intra-chapter scroll is deduped (commit
        // on success, including a real empty chapter).
        bilingualChapterTracker.markEnumerated(href: href)
        guard !blocks.isEmpty else { return }
        await drivePrefetchAndInject(for: currentReadiumLocator)
    }

    /// Resolves the current unit (via the normalized locator) and asks the VM to
    /// prefetch + inject if a translation is already cached.
    private func drivePrefetchAndInject(
        for readiumLocator: ReadiumShared.Locator?
    ) async {
        guard let vm = bilingualViewModel, vm.isEnabled,
              let locator = currentVReaderLocator(from: readiumLocator) else { return }
        await vm.handlePositionChange(locator)
        await injectBilingualIfCached(for: locator)
    }

    /// Build + push inject JS for the current unit's cached translations.
    /// Honors the Bug #268 mismatch fallback (translate the enumerate's OWN block
    /// texts when the prefetch segment count diverges from the block count).
    func injectBilingualIfCached(for locator: Locator) async {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let unit = await vm.textProvider?.unit(containing: locator),
              let segments = vm.translations(for: unit) else { return }
        let blocks = bilingualOrchestrator.currentBlocks
        if !blocks.isEmpty, segments.count != blocks.count {
            await vm.translateBlocksDirectly(blocks.map(\.text), for: unit)
            return
        }
        // Pair segments → bids via the shared 1:1 contract (Bug #266 — a count
        // mismatch yields an empty map → source-only). The commander builds +
        // evaluates the escaped inject JS itself from the map.
        let pairs = EPUBBilingualPipeline.translationsByBid(
            blocks: blocks, translatedSegments: segments
        )
        guard !pairs.isEmpty else { return }
        await bilingualCommander.inject(pairs)
    }

    /// Gate-4 round-3 MED-3: `epubLayout` change handler. WI-11 gates enumerate to
    /// paged, so if bilingual is ALREADY enabled and the user switches paged→scroll
    /// the injected decorations would linger (enumerate just no-ops in scroll) and
    /// the tracker would stay primed. Clear + reset on leaving paged; re-enumerate
    /// the current chapter on returning to paged so translation reappears.
    func handleEPUBLayoutChange() {
        guard let vm = bilingualViewModel else { return }
        switch ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: settingsStore.epubLayout, isEnabled: vm.isEnabled
        ) {
        case .clearAndReset:
            bilingualChapterTracker.reset()
            Task { await bilingualCommander.clear() }
        case .reEnumerate:
            // Re-run the enumerate for the current chapter (via the host's
            // last-known locator). Force past the dedupe — the tracker was reset
            // when we left paged, but force keeps this robust if it was not.
            runBilingualEnumerateForCurrentChapter()
        case .none:
            break
        }
    }

    /// `.readerBilingualDidChange` handler — the VM's prefetch landed (or it
    /// disabled). On disable, clear decorations; otherwise inject the now-cached
    /// translation for the current chapter.
    func handleBilingualDidChange() {
        guard let vm = bilingualViewModel else { return }
        if !vm.isEnabled {
            bilingualChapterTracker.reset()
            Task { await bilingualCommander.clear() }
            return
        }
        Task {
            guard let locator = currentVReaderLocator(from: nil) else { return }
            await injectBilingualIfCached(for: locator)
        }
    }

    /// Builds the seam-#3-normalized vreader `Locator` for the current chapter.
    /// HIGH-1: resolves the href via `selectedHref` — supplied Readium locator →
    /// the host's last-known locator → the chapter tracker's last-enumerated href
    /// — so an inject driven by a prefetch-landed notification (no locator) AND a
    /// first-enable toggle (no chapter change yet) both resolve the unit.
    func currentVReaderLocator(
        from readiumLocator: ReadiumShared.Locator?
    ) -> Locator? {
        let href = ReadiumBilingualChapterTracker.selectedHref(
            supplied: readiumLocator?.href.string,
            lastKnown: lastKnownReadiumLocator?.href.string,
            lastEnumerated: bilingualChapterTracker.lastEnumeratedHref
        )
        guard let href else { return nil }
        let progression = readiumLocator?.locations.progression
            ?? lastKnownReadiumLocator?.locations.progression
        let raw = Locator(
            bookFingerprint: fingerprint,
            href: href,
            progression: progression,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return ReadiumBilingualCommander.normalizedLocator(
            raw, toSpineHrefs: bilingualSpineHrefs
        )
    }
}
#endif
