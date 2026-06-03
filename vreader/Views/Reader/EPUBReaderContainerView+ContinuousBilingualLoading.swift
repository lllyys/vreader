// Purpose: Feature #77 WI-5 — the legacy EPUB CONTINUOUS-SCROLL loading-shimmer
// reconcile, split out of `EPUBReaderContainerView+ContinuousBilingual.swift` for
// the ~300-line budget (Gate-4 Low). The stitched continuous DOM holds multiple
// chapter `<section data-vreader-spine-index="N">` blocks, each with its OWN
// translation unit; several can be in flight at once, so the shimmer is
// reconciled PER materialized section through the live continuous evaluator (not
// the single `pendingHighlightJS` slot, and not against the current visible
// locator).
//
// @coordinates-with: EPUBReaderContainerView+ContinuousBilingual.swift,
//   EPUBReaderContainerView+Bilingual.swift, EPUBBilingualOrchestrator.swift,
//   BilingualReadingViewModel.swift,
//   dev-docs/plans/20260603-feature-77-bilingual-loading.md (WI-5)

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    /// Feature #77 WI-5: the continuous-scroll `.readerBilingualPrefetchDidChange`
    /// handler. The stitched DOM holds MULTIPLE materialized sections, each with
    /// its OWN unit, and the FULL in-flight set may name any of them — so the
    /// shimmer is reconciled PER materialized section, not against the current
    /// visible locator (the same HIGH-1 lesson the inject path follows):
    ///
    ///   - section's unit IS in flight → shimmer that section
    ///     (`buildLoadingJS(forSection:)`, scoped to the section's own bids).
    ///   - section's unit LEFT the set WITHOUT a cached translation (failed /
    ///     cancelled) → clear THAT section's shimmer SECTION-SCOPED — a global
    ///     clear would wrongly remove OTHER still-fetching sections' shimmers.
    ///   - a LANDED translation is replaced in place by
    ///     `reinjectAllMaterializedBilingualSections` (on `.readerBilingualDidChange`),
    ///     so it is never cleared here.
    ///
    /// The reconcile is DEFERRED into a `Task { @MainActor }` — NOT run inline in
    /// the notification post. `BilingualReadingViewModel.finishPrefetch` posts
    /// `.readerBilingualPrefetchDidChange` (the unit already removed from the
    /// in-flight set) BEFORE it caches a successful translation; an inline handler
    /// would therefore see `translations(for: unit) == nil` for a just-LANDED unit
    /// and wrongly clear its shimmer (a flicker before the inject lands). Deferring
    /// lets `finishPrefetch` complete first, so the landed translation is cached
    /// and the `else if translations == nil` branch correctly skips it (the inject
    /// path replaces the shimmer in place). Every eval routes through the live
    /// continuous evaluator (`evaluateBilingualLive`), never the dead single
    /// `pendingHighlightJS` slot.
    func handleBilingualPrefetchChangeContinuous(inFlightUnits: Set<TranslationUnitID>) {
        Task { @MainActor in
            guard let vm = bilingualViewModel, vm.isEnabled else { return }
            for spineIndex in bilingualOrchestrator.materializedSections {
                // The paged `-1` bucket has no spine href; the paged handler owns it.
                guard spineIndex >= 0,
                      let unit = bilingualUnit(forSection: spineIndex) else { continue }
                if inFlightUnits.contains(unit) {
                    if let js = bilingualOrchestrator.buildLoadingJS(forSection: spineIndex) {
                        evaluateBilingualLive(js)
                    }
                } else if vm.translations(for: unit) == nil {
                    evaluateBilingualLive(
                        bilingualOrchestrator.clearLoadingJS(spineIndex: spineIndex))
                }
            }
        }
    }
}
#endif
