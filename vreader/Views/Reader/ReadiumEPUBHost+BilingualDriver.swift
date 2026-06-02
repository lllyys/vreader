// Purpose: Feature #42 WI-11b/WI-12 — the bilingual enumerate→prefetch→inject
// DRIVER for the Readium EPUB host, split out of `ReadiumEPUBHost+Bilingual.swift`
// for the 300-line budget. Owns the location-change enumerate trigger, the forced
// toggle/confirm enumerate, the shared enumerate→prefetch loop, the
// cached-translation inject, the prefetch-landed re-inject, and the layout-change
// re-enumerate. WI-12: works in BOTH paged and scroll, PER-SPINE — Readium emits
// `locationDidChange` at spine boundaries in scroll mode, which drives the same
// `handleBilingualLocationChange` enumerate the paged path uses. It does NOT
// stitch translations across chapters the way legacy #71 does (see
// `ReadiumBilingualChapterTracker.swift` for the full behavior delta).
//
// Gate-4 correctness fixes applied here (see per-method docs + the tracker for
// the pure-logic detail):
//   - HIGH-1: the forced toggle/confirm enumerate passes `lastKnownReadiumLocator`
//     (NOT nil) so first-enable resolves the visible unit.
//   - HIGH-2 / MED-6: `ensureBilingualViewModel()` runs on open, so a persisted-on
//     book enumerates on its FIRST `locationDidChange`.
//   - MED-3: same-chapter duplicate enumerates are gated SYNCHRONOUSLY via
//     `shouldEnumerate(forHref:force:)`; a forced enumerate bypasses the dedupe.
//   - WI-12: enumerate runs in BOTH paged + scroll (per-spine); the
//     `isBilingualSupported` guard fails closed for a future layout.
//   - MED-5: the in-flight enumerate rechecks `vm.isEnabled` after `enumerate()`
//     before mutating the orchestrator / prefetching.
//   - Round-1/2 generation guards (defense in depth): each enumerate captures the
//     tracker GENERATION at schedule time and DISCARDS a result whose generation is
//     no longer current after `enumerate()` + each later inject-chain suspension.
//     Covers only the enumerate-scheduled entry.
//   - Round-4 ROOT CAUSE (block-ownership invariant): the shared orchestrator holds
//     ONE block set; the tracker records the href the CURRENT blocks belong to at
//     the `updateBlocks` commit, and `injectBilingualIfCached` BAILS unless the
//     blocks belong to the inject locator's chapter (`blocksMatch(locatorHref:)`).
//     One check closes BOTH inject entry points — the enumerate chain AND the
//     nil-generation `.readerBilingualDidChange` path — since an owner mismatch
//     always implies stale blocks. Lives on the Readium-side tracker, NOT the
//     shared orchestrator (legacy #71 untouched).
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
        // Finding 1: capture the generation SYNCHRONOUSLY (the forced schedule just
        // bumped it) so a later spine change supersedes this in-flight enumerate.
        let generation = bilingualChapterTracker.currentGeneration
        Task {
            await runBilingualEnumerate(
                currentReadiumLocator: locator, generation: generation
            )
        }
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
        // Finding 1: capture the generation SYNCHRONOUSLY (the schedule just bumped
        // it) so a newer spine's enumerate supersedes this one — chapter-1's result
        // completing after chapter-2 was scheduled is discarded, not injected.
        let generation = bilingualChapterTracker.currentGeneration
        Task {
            await runBilingualEnumerate(
                currentReadiumLocator: readiumLocator, generation: generation
            )
        }
    }

    /// The shared enumerate→prefetch driver. Enumerates the live spine via the
    /// commander, replaces the orchestrator's PAGED block bucket, marks the
    /// chapter as enumerated, and asks the VM to prefetch the current unit
    /// (resolving the unit through the seam-#3 normalized locator). The actual
    /// inject runs later, off `.readerBilingualDidChange`, once the prefetch
    /// lands.
    func runBilingualEnumerate(
        currentReadiumLocator: ReadiumShared.Locator?,
        generation: Int
    ) async {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        // Finding B (defense in depth): never enumerate while first-enable setup is
        // pending — that would prefetch under the default language/granularity.
        guard ReadiumBilingualChapterTracker.reEnumerateAllowed(
            needsSetupSheet: vm.needsSetupSheet
        ) else { return }
        let href = currentReadiumLocator?.href.string
        let result = await bilingualCommander.enumerate()
        // Finding 1: if a newer spine's enumerate was scheduled while this one was in
        // flight, this result's captured generation is no longer current → STALE.
        // Discard WITHOUT touching the in-flight href dedupe (the superseding schedule
        // owns the new href), the orchestrator, or the inject.
        guard bilingualChapterTracker.isCurrentGeneration(generation) else { return }
        // Gate-4 round-3 MED-2: distinguish eval FAILURE (nil) from a
        // successful-but-empty enumerate ([]). On FAILURE revert the in-flight dedupe
        // mark for this href so a later `locationDidChange` retries (else the chapter
        // stays blank forever). A genuinely-empty chapter ([]) is a success: COMMIT.
        guard let blocks = result else {
            bilingualChapterTracker.clearInFlight(href: href)
            return
        }
        // MED-5: the user may have disabled bilingual while the async enumerate
        // was in flight. Recheck before mutating the orchestrator / prefetching —
        // the disable path's `clear()` already removed any decorations.
        guard vm.isEnabled else { return }
        bilingualOrchestrator.updateBlocks(blocks)
        // Round-4 ROOT CAUSE: record WHICH chapter these just-committed blocks belong
        // to, in the SAME normalized (OPF-relative) href space the inject locator
        // carries, so the inject choke point (`blocksMatch`) can reject a spine-A-
        // blocks vs spine-B-locator mismatch. Set EXACTLY at the `updateBlocks`
        // commit, after the generation guard, so it tracks the live bucket.
        bilingualChapterTracker.setBlocksOwner(
            href: currentVReaderLocator(from: currentReadiumLocator)?.href
        )
        // Mark the chapter enumerated so an intra-chapter scroll is deduped (commit
        // on success, including a real empty chapter).
        bilingualChapterTracker.markEnumerated(href: href)
        guard !blocks.isEmpty else { return }
        // Gate-4 round-2 MED: thread the captured generation through the inject
        // chain so a newer spine scheduled during its later awaits supersedes this
        // task (see the chain's per-method docs).
        await drivePrefetchAndInject(for: currentReadiumLocator, generation: generation)
    }

    /// Resolves the current unit (via the normalized locator) and asks the VM to
    /// prefetch + inject if a translation is already cached. Round-2 defense in
    /// depth: the captured `generation` is re-checked after the `handlePositionChange`
    /// suspension (and again in `injectBilingualIfCached`) so a spine change mid-chain
    /// discards (the round-4 owner-href invariant is the primary stale-blocks gate).
    private func drivePrefetchAndInject(
        for readiumLocator: ReadiumShared.Locator?,
        generation: Int
    ) async {
        guard let vm = bilingualViewModel, vm.isEnabled,
              let locator = currentVReaderLocator(from: readiumLocator) else { return }
        await vm.handlePositionChange(locator)
        // A newer spine may have been scheduled while `handlePositionChange` was in
        // flight (scroll mode emits rapid spine changes). Re-check before injecting.
        guard bilingualChapterTracker.isCurrentGeneration(generation) else { return }
        await injectBilingualIfCached(for: locator, generation: generation)
    }

    /// Build + push inject JS for the current unit's cached translations. Honors the
    /// Bug #268 mismatch fallback (translate the enumerate's OWN block texts when the
    /// prefetch segment count diverges from the block count). The choke point BOTH
    /// inject entry points funnel through: the round-4 block-ownership invariant
    /// (`blocksMatch`) here closes the whole stale-blocks-vs-locator class.
    ///
    /// `generation` is the enumerate-chain's captured token (round-2 defense in
    /// depth), or `nil` for the `.readerBilingualDidChange` entry point (not
    /// enumerate-scheduled). When non-nil it is re-checked after the unit-resolve
    /// suspension; the owner-href invariant covers the nil-generation path.
    func injectBilingualIfCached(for locator: Locator, generation: Int? = nil) async {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let unit = await vm.textProvider?.unit(containing: locator) else { return }
        // After resolving the unit (a suspension point) re-check the enumerate-chain
        // generation: a newer spine scheduled during the lookup makes this stale.
        if let generation, !bilingualChapterTracker.isCurrentGeneration(generation) {
            return
        }
        // Round-4 ROOT CAUSE (block-ownership invariant — see file header): the
        // shared orchestrator holds ONE block set; bail unless it belongs to THIS
        // locator's chapter, so neither the pairing path nor the Bug #268
        // `translateBlocksDirectly` fallback pairs spine-B against spine-A's blocks.
        // Covers BOTH inject entry points (generation-guarded enumerate chain + the
        // nil-generation `.readerBilingualDidChange` path) with one check.
        guard bilingualChapterTracker.blocksMatch(locatorHref: locator.href) else { return }
        guard let segments = vm.translations(for: unit) else { return }
        let blocks = bilingualOrchestrator.currentBlocks
        if !blocks.isEmpty, segments.count != blocks.count {
            // Bug #268 fallback: re-check the generation before this path mutates
            // shared orchestrator/commander state via translateBlocksDirectly.
            if let generation, !bilingualChapterTracker.isCurrentGeneration(generation) {
                return
            }
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
        // Bug #304: ensure the interlinear `.vreader-bilingual` `<style>` is on
        // the spine BEFORE injecting the blocks, so they render with the designed
        // style (the Readium engine never threaded `epubOverrideCSS`). Idempotent;
        // uses the live theme so a theme switch updates the rule.
        await bilingualCommander.setStyle(settingsStore.theme.bilingualBlockCSSRule())
        // The pipeline build above is synchronous, so the unit re-check is the
        // inject-path's final generation gate (no await intervenes before here).
        await bilingualCommander.inject(pairs)
    }

    /// WI-12: `epubLayout` change handler. A paged↔scroll switch re-renders the
    /// spine in Readium — the old `data-vreader-bid` stamps + injected decorations
    /// are discarded with the DOM — so when bilingual is enabled we re-enumerate
    /// the current spine in BOTH directions. Reset the tracker + clear any stale
    /// decorations first (defensive: the new-layout DOM is fresh, but a clear keeps
    /// the orchestrator/commander state consistent), then re-enumerate so the
    /// translation reappears in the re-rendered layout.
    func handleEPUBLayoutChange() {
        guard let vm = bilingualViewModel else { return }
        switch ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: settingsStore.epubLayout, isEnabled: vm.isEnabled
        ) {
        case .reEnumerate:
            // Clear stale decorations + reset the tracker, then re-enumerate the
            // current spine. `runBilingualEnumerateForCurrentChapter` forces past
            // the dedupe, so the reset is belt-and-suspenders for the commander.
            bilingualChapterTracker.reset()
            Task {
                await bilingualCommander.clear()
                runBilingualEnumerateForCurrentChapter()
            }
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
