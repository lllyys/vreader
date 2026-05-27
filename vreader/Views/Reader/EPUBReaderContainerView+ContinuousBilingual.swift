// Purpose: Feature #71 WI-7 (Gate-4 round-2) — the continuous-scroll
// bilingual hooks for the EPUB reader, split out of
// `EPUBReaderContainerView+Bilingual.swift` so each file stays under the
// ~300-line budget (rule 50 §9).
//
// In continuous-scroll mode the EPUB DOM stitches multiple chapter
// `<section data-vreader-spine-index="N">` blocks into ONE document. Each
// section materializes independently (the WI-6b `sectionMaterialized` JS
// post) and is frequently OFF-SCREEN relative to the visible locator (the
// ±1 initial fill, lazy append/prepend). The paged path's "drive everything
// off the current visible locator" assumption is wrong here, so this file
// holds the section-scoped pipeline:
//
//   - **enumerate per section** through the LIVE continuous-scroll evaluator
//     (`EPUBContinuousScrollConfig.evaluateBilingual`), not the single
//     `pendingHighlightJS` slot — a burst of section-materialize posts would
//     otherwise let a later section's enumerate JS overwrite an earlier one
//     before the bridge evaluates it (Gate-4 round-2 MEDIUM 1).
//   - **prefetch the SECTION's OWN unit** (the section's spine href →
//     `TranslationUnitID`) via the unit-scoped `prefetchUnitIfNeeded`, NOT the
//     current visible locator's unit (Gate-4 round-2 HIGH 1).
//   - **inject PER SECTION** against `blocksBySection[spineIndex]`, and on
//     `.readerBilingualDidChange` reinject EVERY materialized section that has
//     cached translations — not just the current locator's section (Gate-4
//     round-2 HIGH 2).
//   - **evict** a section's block bucket when the continuous coordinator trims
//     it from the DOM (Gate-4 round-2 MEDIUM 2).
//
// @coordinates-with: EPUBReaderContainerView+Bilingual.swift,
//   EPUBReaderContainerView.swift, EPUBBilingualOrchestrator.swift,
//   EPUBContinuousScrollBridge.swift (the live evaluator),
//   EPUBContinuousScrollCoordinator.swift (the eviction signal),
//   BilingualReadingViewModel+Prefetch.swift (prefetchUnitIfNeeded),
//   ReaderNotifications.swift,
//   FoliateBilingualContainerView.swift (sibling per-section template)

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    // MARK: - Section ↔ unit resolution

    /// The `TranslationUnitID` for a stitched section's spine index — the
    /// section's OWN spine `href`, NOT the current visible locator's. Used by
    /// the per-section prefetch / inject path so an off-screen materialized
    /// section warms + injects its own translation. `nil` when metadata hasn't
    /// loaded or the index is out of range.
    func bilingualUnit(forSection spineIndex: Int) -> TranslationUnitID? {
        guard let items = viewModel.metadata?.spineItems,
              spineIndex >= 0, spineIndex < items.count else { return nil }
        return TranslationUnitID(kind: .epubHref, value: items[spineIndex].href)
    }

    // MARK: - Per-section enumerate

    /// Feature #71 WI-7: drive a per-section bilingual enumerate when a stitched
    /// chapter materializes in continuous-scroll mode. Appended/prepended
    /// sections never fire `didFinish` (only the bootstrap doc does), so the
    /// `sectionMaterialized` signal is the per-section lifecycle hook that
    /// starts the enumerate/translate/inject pipeline for THAT section. No-op
    /// when bilingual is off or the first-enable setup sheet is still open
    /// (mirrors the `onPageDidFinishLoad` gate).
    ///
    /// MEDIUM 1: the enumerate JS is evaluated through the live continuous-scroll
    /// evaluator (`continuousScrollConfig.evaluateBilingual`) rather than the
    /// single `pendingHighlightJS` slot — the initial materialization posts
    /// several `.readerBilingualSectionMaterialized` notifications in quick
    /// succession, and the single slot would drop all but the last. Falls back
    /// to `pendingHighlightJS` only when no live evaluator is bound (defensive —
    /// the section-materialize path only fires in continuous mode where the
    /// config is non-nil).
    func enumerateBilingualSection(spineIndex: Int) {
        guard bilingualViewModel?.isEnabled == true,
              !showBilingualSetupSheet else { return }
        let js = bilingualOrchestrator.enumerateJS(spineIndex: spineIndex)
        if let config = continuousScrollConfig {
            config.evaluateBilingual(js)
        } else {
            pendingHighlightJS = js
        }
    }

    // MARK: - Section-tagged enumerate result (HIGH 1)

    /// Process a section-tagged `[BilingualBlock]` payload (continuous-scroll
    /// per-section enumerate). The blocks are already bucketed under their
    /// section by `handleBilingualBlocks`; this drives the prefetch + inject
    /// for THAT section's own unit.
    ///
    /// HIGH 1: in continuous mode `sectionMaterialized` (and therefore this
    /// enumerate result) fires for ADJACENT / off-screen sections, so the
    /// payload's section ≠ the current visible locator. We resolve the
    /// section's OWN spine href → `TranslationUnitID`, prefetch THAT unit
    /// (unit-scoped — does not clobber the visible-locator trigger state), and
    /// inject that section if its translation is already cached. The next
    /// `.readerBilingualDidChange` (prefetch lands) reinjects via
    /// `reinjectAllMaterializedBilingualSections`.
    func handleSectionBilingualBlocks(forSection spineIndex: Int) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let unit = bilingualUnit(forSection: spineIndex) else { return }
        vm.prefetchUnitIfNeeded(unit)
        injectBilingualSection(spineIndex: spineIndex, unit: unit)
    }

    /// Build inject JS for ONE materialized section against its OWN cached
    /// translation and evaluate it through the live continuous evaluator. No-op
    /// when the section's unit has no cached translation (the prefetch landing
    /// reinjects via `.readerBilingualDidChange`).
    ///
    /// HIGH 2: scopes the inject to `blocksBySection[spineIndex]` so one
    /// stitched chapter's translation never pairs against another section's
    /// blocks (the cross-section flatten bug).
    ///
    /// MEDIUM 2 (Gate-4 round-3): mirrors the paged path's Bug #268 fallback —
    /// when a section's cached plain-text segment count diverges from its DOM
    /// leaf-block count (nested `<pre>` / mixed-content `<blockquote>`),
    /// `buildInjectJS(...forSection:)` returns nil (the 1:1 count guard) and the
    /// section would stay source-only. Translate the section's OWN enumerate
    /// block texts directly so blocks↔segments are 1:1 by construction; the
    /// resulting `.readerBilingualDidChange` reinjects every materialized
    /// section (this section now pairs 1:1).
    private func injectBilingualSection(spineIndex: Int, unit: TranslationUnitID) {
        guard let vm = bilingualViewModel, vm.isEnabled,
              let segments = vm.translations(for: unit) else { return }
        let blocks = bilingualOrchestrator.blocksBySection[spineIndex] ?? []
        // Bug #268 (continuous parity): a count mismatch means the plain-text
        // prefetch's segmentation diverged from the DOM leaf-enumerate for THIS
        // section. Translate the section's own block texts directly so the
        // pairing is 1:1; reinject lands via `.readerBilingualDidChange`.
        if !blocks.isEmpty, segments.count != blocks.count {
            Task { await vm.translateBlocksDirectly(blocks.map(\.text), for: unit) }
            return
        }
        guard let js = bilingualOrchestrator.buildInjectJS(
            translatedSegments: segments, forSection: spineIndex
        ) else { return }
        evaluateBilingualLive(js)
    }

    // MARK: - Reinject every materialized section (HIGH 2)

    /// On `.readerBilingualDidChange` in continuous mode: reinject EVERY
    /// materialized section that has a cached translation for its unit — not
    /// just the current locator's section. The prefetch may have landed for any
    /// of the ±1 / lazily-stitched sections, so we resolve each materialized
    /// section's unit, collect the sections with cached translations, and emit
    /// ONE combined inject JS (per-section 1:1 pairing) so the single evaluator
    /// call covers them all without a single-slot overwrite.
    func reinjectAllMaterializedBilingualSections() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        var translationsBySection: [Int: [String]] = [:]
        for spineIndex in bilingualOrchestrator.materializedSections {
            // The paged path's `-1` bucket has no spine href — skip it here;
            // the paged inject path (`injectBilingualIfCached`) handles it.
            guard spineIndex >= 0,
                  let unit = bilingualUnit(forSection: spineIndex),
                  let segments = vm.translations(for: unit) else { continue }
            let blocks = bilingualOrchestrator.blocksBySection[spineIndex] ?? []
            // MEDIUM 2 (Gate-4 round-3): a per-section count mismatch (Bug #268)
            // would make `buildInjectJS(translationsBySection:)` silently drop
            // this section (1:1 count guard), leaving it source-only. Mirror the
            // paged Bug #268 fallback: translate this section's own block texts
            // directly so it pairs 1:1, then it reinjects on the next
            // `.readerBilingualDidChange`. Sections that already pair 1:1 inject
            // now via the combined payload below.
            if !blocks.isEmpty, segments.count != blocks.count {
                Task { await vm.translateBlocksDirectly(blocks.map(\.text), for: unit) }
                continue
            }
            translationsBySection[spineIndex] = segments
        }
        guard !translationsBySection.isEmpty else { return }
        if let js = bilingualOrchestrator.buildInjectJS(
            translationsBySection: translationsBySection
        ) {
            evaluateBilingualLive(js)
        }
    }

    // MARK: - Enable / disable in continuous mode (HIGH 2)

    /// Feature #71 WI-7 (Gate-4 round-3 HIGH 2): enable bilingual in
    /// continuous-scroll mode. The paged enable path pushes one global
    /// `enumerateJS()` through `pendingHighlightJS`, but the continuous bridge
    /// returns from `updateUIView` BEFORE consuming `pendingJS` (it never
    /// re-loads the stitched DOM), so that push is dead here. Instead, enumerate
    /// every CURRENTLY-MATERIALIZED window section (`coordinator.window.lo...hi`)
    /// section-by-section through the live evaluator — each enumerate result
    /// routes back through `handleBilingualEnumeratePayload` →
    /// `handleSectionBilingualBlocks`, driving the per-section prefetch + inject.
    /// No-op when there is no live config / coordinator window.
    func enableBilingualContinuousAllSections() {
        guard let config = continuousScrollConfig else { return }
        let window = config.coordinator.window
        guard window.lo <= window.hi else { return }
        for spineIndex in window.lo...window.hi {
            enumerateBilingualSection(spineIndex: spineIndex)
        }
    }

    /// Feature #71 WI-7 (Gate-4 round-3 HIGH 2): clear every bilingual
    /// decoration from the live stitched DOM in continuous-scroll mode. The
    /// paged disable path pushes `clearJS()` through `pendingHighlightJS` (dead
    /// in continuous mode — see `enableBilingualContinuousAllSections`), so
    /// route the GLOBAL clear (a whole-document `querySelectorAll` is correct
    /// for disable — it removes EVERY section's decorations) through the live
    /// evaluator. Also drop every per-section block bucket so a later re-enable
    /// re-enumerates from a clean slate.
    func disableBilingualContinuous() {
        evaluateBilingualLive(bilingualOrchestrator.clearJS())
        for spineIndex in bilingualOrchestrator.materializedSections {
            bilingualOrchestrator.clearBlocks(forSection: spineIndex)
        }
    }

    // MARK: - Eviction (MEDIUM 2)

    /// Drop a section's cached block bucket when the continuous coordinator
    /// evicts it from the DOM. Without this the per-section caches accumulate
    /// (a leak) and stale buckets could feed a later flatten / reinject.
    func handleBilingualSectionEvicted(spineIndex: Int) {
        bilingualOrchestrator.clearBlocks(forSection: spineIndex)
    }

    // MARK: - Live evaluator helper

    /// Evaluate bilingual JS through the live continuous-scroll evaluator
    /// (MEDIUM 1). Falls back to `pendingHighlightJS` only when no live
    /// evaluator is bound (defensive). Used by the inject paths so a burst of
    /// per-section injects does not overwrite one another in the single slot.
    func evaluateBilingualLive(_ js: String) {
        if let config = continuousScrollConfig {
            config.evaluateBilingual(js)
        } else {
            pendingHighlightJS = js
        }
    }

    /// Whether the EPUB reader is in continuous-scroll mode (a live config is
    /// bound). The bilingual paths branch on this to choose the section-scoped
    /// pipeline over the paged single-chapter one.
    var isBilingualContinuousMode: Bool { continuousScrollConfig != nil }
}

/// View modifier bundling EPUB bilingual reading hooks — the lazy VM
/// construction, the More-menu toggle, the `.readerBilingualDidChange`
/// observer, the first-enable setup sheet, AND the Feature #71 WI-7
/// continuous-scroll section observers (`.readerBilingualSectionMaterialized`
/// / `.readerBilingualSectionEvicted`). Encapsulates the modifier graph so the
/// container body stays under SwiftUI's type-inference budget. Lives in the
/// `+ContinuousBilingual` file because the section observers are the WI-7
/// surface; the paged observers ride along (one modifier site, not two).
struct EPUBBilingualSurfacesModifier: ViewModifier {
    let bookFingerprintKey: String
    let spineCount: Int?
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    let onBilingualDidChange: () -> Void
    /// Feature #56 WI-15: routes a re-translate result to the format's
    /// bilingual VM so the open chapter re-renders without waiting for the
    /// next prefetch trigger.
    let onReTranslateApplied: (TranslationUnitID, [String]) -> Void
    /// Feature #71 WI-7: a stitched chapter section materialized in
    /// continuous-scroll mode — drive a section-scoped bilingual enumerate.
    let onSectionMaterialized: (Int) -> Void
    /// Feature #71 WI-7 (Gate-4 round-2 MEDIUM 2): a stitched chapter section
    /// was evicted from the continuous-scroll DOM — drop its block bucket.
    let onSectionEvicted: (Int) -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: spineCount) { _, _ in ensureViewModel() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .readerBilingualSectionMaterialized)
            ) { notification in
                guard let info = notification.userInfo,
                      info["fingerprintKey"] as? String == bookFingerprintKey,
                      let spineIndex = info["spineIndex"] as? Int
                else { return }
                onSectionMaterialized(spineIndex)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .readerBilingualSectionEvicted)
            ) { notification in
                guard let info = notification.userInfo,
                      info["fingerprintKey"] as? String == bookFingerprintKey,
                      let spineIndex = info["spineIndex"] as? Int
                else { return }
                onSectionEvicted(spineIndex)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerBilingualDidChange)
            ) { notification in
                let key = notification.userInfo?["fingerprintKey"] as? String
                guard key == bookFingerprintKey else { return }
                onBilingualDidChange()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerBilingualReTranslateApplied)
            ) { notification in
                guard let info = notification.userInfo,
                      info["fingerprintKey"] as? String == bookFingerprintKey,
                      let unit = info["unit"] as? TranslationUnitID,
                      let segments = info["segments"] as? [String]
                else { return }
                onReTranslateApplied(unit, segments)
            }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
