// Purpose: Feature #77 WI-2 — the Readium bilingual LOADING-shimmer lifecycle,
// split out of `ReadiumEPUBHost+BilingualDriver.swift` for the ~300-line budget
// (Gate-4 Low). Owns the `.readerBilingualPrefetchDidChange` handler that shows
// an inline shimmer placeholder while the current chapter's translation unit is
// being fetched, and the combined block+shimmer `<style>` helper both the inject
// and loading paths feed to the spine.
//
// Lifecycle (mirrors the design #1024 §L "BilingualLoadingSlot"):
//   - A unit enters the in-flight set → `injectLoading` shimmers the current
//     spine's still-untranslated blocks.
//   - The translation lands → `.readerBilingualDidChange` → the inject path
//     replaces the shimmer IN PLACE (`classList.remove('vreader-bilingual-loading')`
//     + textContent), so a landed unit is NEVER cleared here (no flicker).
//   - A failed / cancelled prefetch (no cached translation) for the CURRENT unit
//     → `clearLoading` removes its leftover shimmer.
//   - Spine (re)entry clears any stale shimmer on the entered spine — see
//     `runBilingualEnumerate`'s leading `clearLoading()` (Gate-4 round-2 Medium:
//     a shimmer started on chapter A then scrolled away from is reconciled when A
//     is re-entered, since the Readium eval channel only reaches the visible
//     spine and cannot target an off-current one).
//
// @coordinates-with: ReadiumEPUBHost+BilingualDriver.swift,
//   ReadiumEPUBHost+Bilingual.swift, ReadiumBilingualCommander.swift,
//   BilingualReadingViewModel.swift, ReaderThemeV2+EPUBCSS.swift,
//   dev-docs/plans/20260603-feature-77-bilingual-loading.md (WI-2)

#if canImport(UIKit)
import SwiftUI

extension ReadiumEPUBHost {

    /// Feature #77 WI-2: `.readerBilingualPrefetchDidChange` handler — show or
    /// remove the inline LOADING shimmer for the current chapter as the in-flight
    /// unit set changes (the FULL set is carried in the notification, so the
    /// handler is authoritative for the visible spine). When the current chapter's
    /// unit is fetching, inject a shimmer after each undecorated block of the
    /// current section (`injectLoading` skips blocks that already carry a
    /// translation, so it never downgrades a landed row). When the unit leaves the
    /// set, the translation arrives via `.readerBilingualDidChange` and the inject
    /// replaces the shimmer IN PLACE — so a landed unit must NOT be cleared here;
    /// only a failed / cancelled prefetch (no cached translation) has its leftover
    /// shimmer removed. A shimmer started on a spine the user has since scrolled
    /// away from is reconciled on spine re-entry (`runBilingualEnumerate` clears
    /// stale loading), because the eval channel only reaches the visible spine.
    func handleBilingualPrefetchChange(inFlightUnits: Set<TranslationUnitID>) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard ReadiumBilingualChapterTracker.isBilingualSupported(
            forLayout: settingsStore.epubLayout
        ) else { return }
        Task {
            guard let locator = currentVReaderLocator(from: nil),
                  let unit = await vm.textProvider?.unit(containing: locator) else { return }
            // Block-ownership invariant (mirrors `injectBilingualIfCached`): only
            // act when the orchestrator's blocks belong to THIS chapter, so the
            // shimmer never lands on a stale spine's bids.
            guard bilingualChapterTracker.blocksMatch(locatorHref: locator.href) else { return }
            let bids = bilingualOrchestrator.currentBlocks.map(\.bid)
            guard !bids.isEmpty else { return }
            if inFlightUnits.contains(unit) {
                // Fetching: ensure the combined block + shimmer `<style>` is on the
                // spine, then shimmer the still-untranslated blocks.
                await bilingualCommander.setStyle(bilingualStyleCSS())
                await bilingualCommander.injectLoading(
                    bids, targetIsCJK: bilingualTargetIsCJK)
            } else if vm.translations(for: unit) == nil {
                // Left the in-flight set WITHOUT a cached translation (failed /
                // cancelled) → remove the leftover shimmer. A landed translation is
                // replaced in place by the inject path, so it must NOT be cleared.
                await bilingualCommander.clearLoading()
            }
        }
    }

    /// Feature #77: the combined interlinear `<style>` CSS — the translation BLOCK
    /// rule plus the LOADING shimmer rule — so both injected translations and the
    /// in-flight shimmer render on the Readium spine (which never threads
    /// `epubOverrideCSS`). Tracks the live theme; idempotent on the spine.
    func bilingualStyleCSS() -> String {
        settingsStore.theme.bilingualBlockCSSRule()
            + " " + settingsStore.theme.bilingualLoadingCSSRule()
    }
}
#endif
