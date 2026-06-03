// Purpose: Feature #56 WI-10 — EPUB bilingual wiring extension.
// Adds the `BilingualReadingViewModel` ownership, the
// `EPUBBilingualOrchestrator` + enumerate / inject / clear JS
// dispatch, the first-enable setup-sheet presentation, and the
// `.readerMoreBilingual` observer that toggles bilingual mode.
//
// Sits as a separate file to keep `EPUBReaderContainerView.swift`
// under the ~300-line budget (rule 50 §9) while concentrating all
// bilingual state in one place. The container hosts the
// `@State` instances and applies the modifier `bilingualSurfaces(...)`
// returned here.
//
// Key decisions:
// - **VM + orchestrator + service held as `@State`.** SwiftUI owns
//   their lifecycle; deinit on container teardown frees everything
//   without explicit cleanup. The translation service is lazily
//   constructed once per book so we don't pay the `.shared` store
//   wiring on every render.
// - **Pipeline is event-driven.** Chapter `didFinish` → `enumerateJS`
//   runs. The bridge's `onBilingualEnumerate` callback parses
//   blocks → ask the VM to prefetch → on `.readerBilingualDidChange`,
//   build inject JS via the orchestrator and push through the
//   bridge's `pendingHighlightJS` seam (the same seam highlights
//   use, so chapter-swap defers correctly per Bug #182).
// - **The setup sheet binding is the VM's `needsSetupSheet`.** The
//   VM sets it on first-enable; the sheet's confirm closes it via
//   `dismissSetupSheet()`.
//
// Feature #71 WI-7: the CONTINUOUS-SCROLL section-scoped hooks
// (per-section enumerate / inject, section materialize / evict, the
// reinject-all-materialized path, and the `EPUBBilingualSurfacesModifier`
// modifier graph) live in `EPUBReaderContainerView+ContinuousBilingual.swift`.
// This file keeps the paged/global pipeline + VM lifecycle + setup-sheet +
// More-toggle. It is slightly over the ~300-line guideline (pre-existing,
// WI-10 surface); the WI-7 split moved the new section hooks out rather than
// re-cutting WI-10's stable surface.
//
// @coordinates-with: EPUBReaderContainerView.swift,
//   EPUBReaderContainerView+ContinuousBilingual.swift (WI-7 section hooks),
//   EPUBBilingualJS.swift, EPUBBilingualOrchestrator.swift,
//   EPUBBilingualPipeline.swift, BilingualReadingViewModel.swift,
//   ChapterTranslationPrefetcher.swift, ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    /// Build the `ChapterPrefetching` adapter for the open book.
    /// One per book; constructed lazily after the parser exposes
    /// the spine list so the `EPUBChapterTextProvider` has its
    /// source ready. The adapter pins the `ChapterTranslationService`
    /// + active `AIService` for the book's lifetime in the reader.
    static func makePrefetcher(
        bookFingerprintKey: String,
        textProvider: any ChapterTextProviding
    ) -> ChapterTranslationPrefetcher {
        let keychain = KeychainService()
        let aiService = AIService(
            featureFlags: FeatureFlags.shared,
            consentManager: AIConsentManager(),
            keychainService: keychain,
            profileStore: ProviderProfileStore.shared
        )
        let service = ChapterTranslationService(
            sender: aiService,
            store: ChapterTranslationStore.shared,
            promptVersion: bilingualPromptVersion
        )
        return ChapterTranslationPrefetcher(
            bookFingerprintKey: bookFingerprintKey,
            textProvider: textProvider,
            translationService: service,
            aiService: aiService,
            style: .natural
        )
    }

    /// The single pinned prompt version for the chapter-bilingual
    /// pipeline. Stored on the `lookupKey` so a bump invalidates
    /// every cached row at once (re-translation is then a single
    /// schema-change-class operation).
    static let bilingualPromptVersion = "bilingual-v1"

    /// Build the EPUB chapter-text adapter for the open book once
    /// the parser + spine list are known. Returns `nil` until the
    /// parser has loaded its metadata (the container threads that
    /// state in).
    static func makeTextProvider(
        parser: any EPUBParserProtocol,
        spineItems: [EPUBSpineItem]?
    ) -> EPUBChapterTextProvider? {
        guard let spine = spineItems, !spine.isEmpty else { return nil }
        return EPUBChapterTextProvider(parser: parser, spineItems: spine)
    }

    // MARK: - Bilingual surface modifier + event handlers

    /// Lazily constructs the bilingual VM + prefetcher after EPUB
    /// metadata has loaded. Idempotent — already-constructed VM is
    /// preserved on subsequent calls (a chapter swap inside the
    /// same book must NOT discard prefetched translations).
    func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard viewModel.metadata != nil else { return }
        let spine = viewModel.metadata?.spineItems
        guard let textProvider = Self.makeTextProvider(
            parser: parser, spineItems: spine
        ) else { return }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
        )
        vm.attachProvider(textProvider)
        vm.attachPrefetcher(
            Self.makePrefetcher(
                bookFingerprintKey: viewModel.bookFingerprintKey,
                textProvider: textProvider
            )
        )
        bilingualViewModel = vm
        // Bug #301: resolve the LIVE AI-readiness so the setup-sheet
        // engineDescriptor (`configured`) is truthful, not hardcoded.
        Task { await vm.refreshAIConfigured() }
        // Surface the first-enable setup sheet if the VM raised it
        // before construction completed (it shouldn't have, but
        // mirror state defensively).
        if vm.needsSetupSheet {
            showBilingualSetupSheet = true
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
        }
        // Feature #56 WI-14: publish the EPUB chapter-text provider to
        // the parent ReaderContainerView so the Book Details "Translate
        // entire book…" entry point can consume it without bubbling
        // per-format internals upwards. Sibling of the TXT/MD/Foliate
        // publishers.
        NotificationCenter.default.post(
            name: .readerBookTranslationTextProviderAvailable,
            object: textProvider,
            userInfo: ["fingerprintKey": viewModel.bookFingerprintKey])
    }

    /// Feature #71 WI-7 (Gate-4 round-3 MEDIUM 1): route a parsed
    /// `EPUBBilingualEnumeratePayload` from the JS enumerate channel.
    ///
    /// The continuous-scroll scoped enumerate posts an envelope
    /// (`{sectionIndex, blocks}`) so an EMPTY result (a section with no
    /// translatable leaf blocks) still carries its section identity. Without
    /// the envelope, an empty `[]` would lose the section and fall into the
    /// paged `updateBlocks([])` path that clears EVERY bucket — wiping adjacent
    /// stitched sections' caches. Here, an empty scoped envelope clears ONLY
    /// that section. A non-empty payload (or the paged bare-array path with no
    /// requested section) delegates to `handleBilingualBlocks(_:)`.
    func handleBilingualEnumeratePayload(_ payload: EPUBBilingualEnumeratePayload) {
        if payload.blocks.isEmpty {
            // An emptied scoped enumerate: clear ONLY that section's stale
            // bucket so a later inject for it cannot resolve old bids. A bare
            // empty array (paged path, no requested section) is dropped — there
            // is no section to attribute it to, and clearing every bucket would
            // be wrong.
            if let section = payload.requestedSectionIndex {
                bilingualOrchestrator.clearBlocks(forSection: section)
            }
            return
        }
        handleBilingualBlocks(payload.blocks)
    }

    /// Process a parsed `[BilingualBlock]` from the JS enumerate
    /// channel. Replaces the orchestrator's block list and asks the
    /// VM to prefetch translation for the current unit (idempotent —
    /// the VM dedupes by `lastTriggerUnit`).
    ///
    /// Feature #71 WI-7: when the payload carries per-block section
    /// tags (continuous-scroll mode — a per-section enumerate stamps
    /// `sectionIndex` on every entry), the blocks are routed into the
    /// orchestrator's PER-SECTION bucket via `updateBlocks(_:forSection:)`
    /// so a re-enumerate of one stitched chapter cannot clobber an
    /// adjacent section's stamped blocks. The paged/global path (no
    /// section tags) keeps the replace-all `updateBlocks(_:)` behaviour.
    func handleBilingualBlocks(_ blocks: [BilingualBlock]) {
        if let section = blocks.first?.sectionIndex,
           blocks.allSatisfy({ $0.sectionIndex == section }) {
            // Continuous-scroll per-section enumerate: bucket under the
            // section so other stitched chapters' caches are preserved, then
            // drive the prefetch + inject for THAT section's own unit (HIGH 1
            // — NOT the current visible locator, which differs for the ±1 /
            // lazily-stitched off-screen sections).
            bilingualOrchestrator.updateBlocks(blocks, forSection: section)
            handleSectionBilingualBlocks(forSection: section)
            return
        }
        // Paged / global path (one chapter per document, untagged blocks) —
        // replace all and drive off the current visible locator.
        bilingualOrchestrator.updateBlocks(blocks)
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = viewModel.makeCurrentLocator() else { return }
        Task { await vm.handlePositionChange(locator) }
        // If the VM already has cached translations for the current
        // unit, inject immediately; otherwise the next
        // `.readerBilingualDidChange` (posted when prefetch lands)
        // is when inject JS gets pushed.
        injectBilingualIfCached(for: locator)
    }

    /// Build inject JS for the current unit's translations (if any
    /// are cached) and push through the bridge's `pendingHighlightJS`
    /// seam. A no-op when the orchestrator has no blocks or the
    /// VM has no translations for the current unit.
    func injectBilingualIfCached(for locator: Locator) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        Task {
            guard let unit = await vm.textProvider?.unit(containing: locator),
                  let segments = vm.translations(for: unit) else { return }
            // Bug #268: the plain-text prefetch's segment count diverged from the
            // DOM leaf-enumerate's block count (nested `<pre>` / mixed-content
            // `<blockquote>`), so the 1:1 pairing would paint source-only.
            // Translate the enumerate's OWN block texts directly so blocks↔segments
            // are 1:1 by construction; that re-injects via the VM's
            // `.readerBilingualDidChange` once it lands. The common matched-count
            // path is untouched.
            let blocks = bilingualOrchestrator.currentBlocks
            if !blocks.isEmpty, segments.count != blocks.count {
                await vm.translateBlocksDirectly(blocks.map(\.text), for: unit)
                return
            }
            if let js = bilingualOrchestrator.buildInjectJS(
                translatedSegments: segments
            ) {
                pendingHighlightJS = js
            }
        }
    }

    /// Build clear JS and push through `pendingHighlightJS` to
    /// remove every bilingual decoration node from the live chapter.
    ///
    /// Feature #71 WI-7 (Gate-4 round-3 HIGH 2): in continuous-scroll mode the
    /// bridge returns from `updateUIView` before consuming `pendingJS`, so the
    /// `pendingHighlightJS` push is dead. Route the clear (and the per-section
    /// bucket reset) through the live evaluator instead. The paged path keeps
    /// the `pendingHighlightJS` seam unchanged.
    func clearBilingualDecorations() {
        if isBilingualContinuousMode {
            disableBilingualContinuous()
        } else {
            pendingHighlightJS = bilingualOrchestrator.clearJS()
        }
    }

    /// Feature #77 WI-4: `.readerBilingualPrefetchDidChange` handler for the
    /// legacy EPUB engine (override-off PAGED path). Shows the inline loading
    /// shimmer while the current chapter's unit is fetching, and removes a
    /// leftover shimmer on a failed / cancelled prefetch (a landed translation is
    /// replaced in place by the inject path, so it is NOT cleared here). Pushes
    /// through the same `pendingHighlightJS` seam the paged inject uses.
    /// Continuous-scroll mode is handled separately (WI-5).
    func handleBilingualPrefetchChange(inFlightUnits: Set<TranslationUnitID>) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        if isBilingualContinuousMode {
            // Feature #77 WI-5: the stitched continuous DOM holds MULTIPLE
            // sections, each with its own unit — handled section-by-section.
            handleBilingualPrefetchChangeContinuous(inFlightUnits: inFlightUnits)
            return
        }
        Task {
            guard let locator = viewModel.makeCurrentLocator(),
                  let unit = await vm.textProvider?.unit(containing: locator) else { return }
            if inFlightUnits.contains(unit) {
                if let js = bilingualOrchestrator.buildLoadingJS() {
                    pendingHighlightJS = js
                }
            } else if vm.translations(for: unit) == nil {
                pendingHighlightJS = bilingualOrchestrator.clearLoadingJS()
            }
        }
    }

    /// Handle a `.readerMoreBilingual` notification — toggle the
    /// bilingual VM's `isEnabled` state. Construct the VM lazily if
    /// the More menu fired before metadata loaded (a rare edge — the
    /// menu is gated on the chrome which only appears after load).
    ///
    /// Codex Gate-4 audit finding [3]: enabling bilingual on an
    /// already-loaded chapter must trigger a fresh enumerate so the
    /// orchestrator's `currentBlocks` populates and the next
    /// `.readerBilingualDidChange` (posted when the prefetch lands)
    /// can build inject JS. Without this push, the current chapter
    /// stays source-only until the user navigates to a new chapter.
    func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            clearBilingualDecorations()
            return
        }
        // Codex Gate-4 round-2 finding [R2-2]: a FIRST enable raises
        // the setup sheet — the user has not yet confirmed the
        // target language / granularity. We must NOT trigger
        // enumerate (and therefore the prefetch) until either the
        // confirm path runs OR the user cancels (which turns
        // bilingual back off). A subsequent enable (no setup sheet
        // — `hasBeenConfigured == true`) goes straight to enumerate
        // since the user's prior choice is reused.
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        } else if isBilingualContinuousMode {
            // Feature #71 WI-7 (Gate-4 round-3 HIGH 2): in continuous mode the
            // bridge never consumes `pendingJS`, so enumerate every materialized
            // window section through the live evaluator instead.
            enableBilingualContinuousAllSections()
        } else {
            // No setup-sheet gate — run enumerate against the live
            // DOM. The bridge's `pendingJS` seam applies it
            // immediately; the resulting `bilingualEnumerate`
            // message lands via the bridge's script-message handler
            // and routes back to `handleBilingualBlocks(_:)`.
            pendingHighlightJS = bilingualOrchestrator.enumerateJS()
        }
    }

    /// Handle a `.readerBilingualDidChange` notification — when the
    /// VM's prefetch lands, the cached translations for the affected
    /// unit are ready; build inject JS and push it. The VM also
    /// posts on disable; we route that through `clearBilingualDecorations`.
    ///
    /// Feature #71 WI-7 (Gate-4 round-2 HIGH 2): in continuous-scroll mode the
    /// prefetch that just landed may belong to ANY materialized stitched
    /// section (the ±1 fill / lazily-stitched off-screen sections), not the
    /// current visible locator's. Reinject EVERY materialized section whose
    /// unit has a cached translation — each scoped to its own blocks — so a
    /// translation for an off-screen section paints correctly when the reader
    /// reaches it, with no cross-section bleed. The paged path keeps the
    /// single-locator inject.
    func handleBilingualDidChange() {
        guard let vm = bilingualViewModel else { return }
        if !vm.isEnabled {
            clearBilingualDecorations()
            return
        }
        if isBilingualContinuousMode {
            reinjectAllMaterializedBilingualSections()
            return
        }
        guard let locator = viewModel.makeCurrentLocator() else { return }
        injectBilingualIfCached(for: locator)
    }

    /// Commit the setup-sheet's chosen language + granularity to the
    /// VM and dismiss the sheet. Drives the first-enable confirm
    /// path — subsequent flips do not re-raise the sheet
    /// (`hasBeenConfigured`).
    ///
    /// Codex Gate-4 round-2 finding [R2-2]: this is also where the
    /// first-enable's enumerate runs — `handleMoreBilingualToggle`
    /// defers it to confirm so the prefetch always uses the user's
    /// committed language, not the persisted default.
    func confirmBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.setTargetLanguage(bilingualSetupState.languageKey)
        vm.setGranularity(bilingualSetupState.granularity)
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        // Now that the user has committed the language/granularity,
        // run enumerate so the prefetch can land translations under
        // the chosen settings. Idempotent if the sheet was raised
        // for a different reason and enumerate had already run for
        // the current chapter (`updateBlocks` replaces — stale
        // blocks get replaced with the fresh stamp pass).
        //
        // Feature #71 WI-7 (Gate-4 round-3 HIGH 2): in continuous mode the
        // bridge never consumes `pendingJS`; enumerate every materialized
        // window section through the live evaluator instead.
        if isBilingualContinuousMode {
            enableBilingualContinuousAllSections()
        } else {
            pendingHighlightJS = bilingualOrchestrator.enumerateJS()
        }
    }

    /// Dismiss the setup sheet without persisting changes and turn
    /// bilingual mode back off — the user opted out of first-enable.
    func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    /// SwiftUI modifier bundling all bilingual reading event hooks.
    /// Wraps the chapter-spine lazy-init, the More-menu toggle, the
    /// inject/clear pipeline, and the first-enable setup sheet
    /// into a single composition site — the container body adds
    /// `.modifier(bilingualSurfacesModifier)` rather than several
    /// inline modifiers, which would otherwise overflow SwiftUI's
    /// type-inference budget on this already-large body.
    var bilingualSurfacesModifier: some ViewModifier {
        EPUBBilingualSurfacesModifier(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            spineCount: viewModel.metadata?.spineCount,
            ensureViewModel: { ensureBilingualViewModel() },
            onMoreBilingualToggle: { handleMoreBilingualToggle() },
            onBilingualDidChange: { handleBilingualDidChange() },
            onPrefetchDidChange: { handleBilingualPrefetchChange(inFlightUnits: $0) },
            onReTranslateApplied: { unit, segments in
                bilingualViewModel?.applyReTranslateResult(segments, for: unit)
            },
            // Feature #71 WI-7: a stitched chapter materialized in
            // continuous-scroll mode — drive a section-scoped enumerate
            // through the LIVE continuous evaluator (Gate-4 round-2 MEDIUM 1 —
            // not the single `pendingHighlightJS` slot, which a burst of
            // materialize posts would overwrite). The enumerate result routes
            // back into `handleBilingualBlocks` → `handleSectionBilingualBlocks`.
            onSectionMaterialized: { spineIndex in
                enumerateBilingualSection(spineIndex: spineIndex)
            },
            // Feature #71 WI-7 (Gate-4 round-2 MEDIUM 2): a stitched chapter was
            // evicted from the continuous-scroll DOM — drop its stale block
            // bucket so per-section caches don't accumulate.
            onSectionEvicted: { spineIndex in
                handleBilingualSectionEvicted(spineIndex: spineIndex)
            },
            showSetupSheet: $showBilingualSetupSheet,
            sheetView: { AnyView(bilingualSetupSheetView) }
        )
    }

    /// The first-enable `BilingualSetupSheet` view, kept here so the
    /// container body stays under SwiftUI's type-inference budget.
    @ViewBuilder
    var bilingualSetupSheetView: some View {
        BilingualSetupSheetContainer(
            theme: settingsStore?.theme ?? .paper,
            state: $bilingualSetupState,
            engineDescriptor: BilingualEngineDescriptor(
                configured: bilingualViewModel?.aiConfigured ?? false,
                providerName: nil,
                subtitle: nil
            ),
            onConfirm: { confirmBilingualSetup() },
            onCancel: { cancelBilingualSetup() },
            // Feature #81: "Set up" / "Change…" pushes the scoped AI Providers
            // list (handled inside the container); on configure it refreshes
            // this strip + pops back.
            onConfigured: { await bilingualViewModel?.refreshAIConfigured() }
        )
        // Bug #301: re-resolve live AI readiness each time the sheet
        // appears, so the engine strip is truthful even if AI settings
        // changed after the reader VM was first built (audit-Medium).
        .task { await bilingualViewModel?.refreshAIConfigured() }
    }
}

#endif
