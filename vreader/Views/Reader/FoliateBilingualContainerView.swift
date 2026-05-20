// Purpose: Feature #56 WI-11 — host wrapper for the AZW3/MOBI
// bilingual interlinear renderer. Wraps `FoliateSpikeView` (the
// live AZW3/MOBI host) with the bilingual VM, orchestrator,
// first-enable setup sheet, and the notification observers that
// drive the enumerate / inject / clear pipeline.
//
// Sits in `ReaderContainerView`'s `.foliateWeb` dispatch branch so
// the spike itself stays unchanged for non-bilingual paths (no
// runtime overhead beyond an idle observer for AZW3/MOBI books
// the user never enables bilingual on).
//
// Pipeline (mirror of `EPUBReaderContainerView+Bilingual`):
//
//   1. `.readerMoreBilingual` → toggle the VM. First enable raises
//      `BilingualSetupSheet`; confirm posts an enumerate.
//      Subsequent flips skip the sheet.
//   2. `.readerRelocate` (or `section-load`) → if bilingual on
//      and not in the setup sheet, post the enumerate JS via
//      `.foliateRequestBilingualEvalJS`. The spike's coordinator
//      runs it; the resulting `bilingualEnumerate` message goes
//      back through `.foliateBilingualBlocksEnumerated`.
//   3. `.foliateBilingualBlocksEnumerated` → cache blocks on the
//      orchestrator, ask the VM to prefetch translations for the
//      current unit.
//   4. `.readerBilingualDidChange` → prefetch landed; build the
//      inject JS and post it.
//
// Key decisions:
// - **No new SwiftData / network deps in this file.** The wrapper
//   owns view-layer state; data flow goes through the existing
//   `BilingualReadingViewModel` + `ChapterTranslationPrefetcher`
//   the EPUB renderer already uses.
// - **`FoliateSectionExtracting` comes from the live Coordinator.**
//   Captured via the `FoliateCoordinatorBox` the spike fills in
//   from `makeCoordinator()`. The `FoliateChapterTextProvider`
//   actor is constructed once the coordinator is non-nil + the
//   book is ready.
// - **Setup sheet is the same `BilingualSetupSheet`.** UI parity
//   with the EPUB renderer — rule 51 is satisfied because the
//   sheet is already a designed surface (rendered by WI-9).
//
// @coordinates-with: FoliateSpikeView.swift,
//   FoliateBilingualOrchestrator.swift, FoliateBilingualJS.swift,
//   FoliateChapterTextProvider.swift, FoliateSectionExtracting.swift,
//   ChapterTranslationPrefetcher.swift, BilingualSetupSheet.swift,
//   ReaderNotifications.swift,
//   EPUBReaderContainerView+Bilingual.swift (sibling EPUB host),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import SwiftUI
import SwiftData

/// AZW3/MOBI host wrapper that adds bilingual interlinear rendering
/// to `FoliateSpikeView`. Owns the VM + orchestrator + setup sheet
/// state.
struct FoliateBilingualContainerView: View {

    let bookURL: URL
    let fingerprintKey: String
    let readerToken: UUID?
    let settingsStore: ReaderSettingsStore?
    let coordinatorBox: FoliateCoordinatorBox?

    @Environment(\.modelContext) private var modelContext

    // MARK: - Bilingual state

    @State private var bilingualViewModel: BilingualReadingViewModel?
    @State private var bilingualOrchestrator = FoliateBilingualOrchestrator()
    @State private var showBilingualSetupSheet: Bool = false
    @State private var bilingualSetupState: BilingualSetupSheetState = .defaultValue

    /// The active locator's section href — captured from the Foliate
    /// relocate notification. Used to resolve the current unit for
    /// prefetch + inject. We track the section index (stringified)
    /// since `TranslationUnitID.Kind.foliateHref` carries the
    /// integer-string id the JS host exposes.
    @State private var currentSectionHref: String?

    /// The Foliate section index of the current page. Updated on
    /// every relocate (Gate-4 audit H1) so a page turn
    /// within an already-loaded section keeps the current unit in
    /// sync. Drives the `targetSectionIndex` argument on the
    /// orchestrator's enumerate / inject / clear JS so a unit's
    /// translations never bleed into adjacent loaded sections.
    @State private var currentSectionIndex: Int?

    var body: some View {
        FoliateSpikeView(
            bookURL: bookURL,
            fingerprintKey: fingerprintKey,
            readerToken: readerToken,
            settingsStore: settingsStore,
            coordinatorBox: coordinatorBox
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .readerMoreBilingual)
        ) { _ in handleMoreBilingualToggle() }
        .onReceive(
            NotificationCenter.default.publisher(for: .readerBilingualDidChange)
        ) { notification in
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == fingerprintKey else { return }
            handleBilingualDidChange()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateBilingualBlocksEnumerated)
        ) { notification in
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == fingerprintKey else { return }
            let blocks = (notification.userInfo?["blocks"] as? [BilingualBlock]) ?? []
            // Gate-4 round-3 audit fix:
            // `requestedSectionIndex` is present when the enumerate
            // was scoped to one section. An empty blocks list for a
            // scoped request signals "previously-populated section
            // re-enumerated empty" — the container must clear that
            // section's cache.
            let requestedSection = notification.userInfo?["requestedSectionIndex"] as? Int
            handleEnumeratedBlocks(blocks, requestedSection: requestedSection)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateSectionLoaded)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == fingerprintKey else { return }
            // Feature #56 WI-14: publish the Foliate text provider on
            // section-load so the Book Details "Translate entire book…"
            // entry point becomes reachable on normal book open (not
            // only after the user toggles bilingual mode). Codex Gate-4
            // round-2 H2 fix. Idempotent — host caches by fingerprintKey.
            publishTranslateBookTextProviderIfReady()
            handleSectionLoaded(notification.userInfo)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateRelocated)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == fingerprintKey else { return }
            handleRelocated(notification.userInfo)
        }
        .sheet(isPresented: $showBilingualSetupSheet) {
            BilingualSetupSheet(
                theme: settingsStore?.theme ?? .paper,
                state: $bilingualSetupState,
                engineDescriptor: BilingualEngineDescriptor(
                    configured: true,
                    providerName: nil,
                    subtitle: nil
                ),
                onConfirm: { confirmBilingualSetup() },
                onCancel: { cancelBilingualSetup() },
                onOpenSettings: { cancelBilingualSetup() }
            )
        }
    }

    // MARK: - VM lifecycle

    /// Lazily constructs the bilingual VM + prefetcher once the
    /// Foliate coordinator is available. Idempotent — already-built
    /// VM is preserved on subsequent calls.
    private func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard let extractor = coordinatorBox?.coordinator else { return }
        let textProvider = FoliateChapterTextProvider(extractor: extractor)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: fingerprintKey,
            perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
        )
        vm.attachProvider(textProvider)
        vm.attachPrefetcher(
            EPUBReaderContainerView.makePrefetcher(
                bookFingerprintKey: fingerprintKey,
                textProvider: textProvider
            )
        )
        bilingualViewModel = vm
        if vm.needsSetupSheet {
            showBilingualSetupSheet = true
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
        }
    }

    /// Feature #56 WI-14: publishes the Foliate chapter-text provider
    /// to the parent `ReaderContainerView` so the Book Details
    /// translate-entire-book entry point can consume it. The Foliate
    /// publish path needs to fire on normal book open (not only when
    /// the user toggles bilingual mode), so this is invoked from the
    /// `.foliateSectionLoaded` observer above. Idempotent — the host
    /// caches by `fingerprintKey`, so repeating the post on every
    /// section-load is cheap (Codex Gate-4 round-2 H2).
    private func publishTranslateBookTextProviderIfReady() {
        guard let extractor = coordinatorBox?.coordinator else { return }
        let textProvider = FoliateChapterTextProvider(extractor: extractor)
        NotificationCenter.default.post(
            name: .readerBookTranslationTextProviderAvailable,
            object: textProvider,
            userInfo: ["fingerprintKey": fingerprintKey])
    }

    // MARK: - Event handlers

    /// Toggle bilingual mode. First enable raises the setup sheet
    /// (sheet's confirm runs an enumerate against the freshest
    /// language). Subsequent enables push enumerate immediately.
    private func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            evalBilingualJS(bilingualOrchestrator.clearJS())
            return
        }
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        } else {
            evalBilingualJS(
                bilingualOrchestrator.enumerateJS(
                    sectionIndex: currentSectionIndex)
            )
        }
    }

    /// VM prefetch landed — build inject JS and push it through
    /// the eval observer.
    private func handleBilingualDidChange() {
        guard let vm = bilingualViewModel else { return }
        if !vm.isEnabled {
            evalBilingualJS(bilingualOrchestrator.clearJS())
            return
        }
        injectIfCached()
    }

    /// Parsed `[BilingualBlock]` from the JS enumerate channel —
    /// partition by section index and store each section's blocks
    /// in the orchestrator's per-section cache. Gate-4 round-2
    /// audit fix: per-section storage means an adjacent preloaded
    /// section (paginated mode) cannot clobber the active section's
    /// block list. Only the active section drives the prefetch
    /// trigger.
    ///
    /// Gate-4 round-3 audit fix:
    /// `requestedSection` is non-nil when the JS enumerate was
    /// scoped. An empty `blocks` for a scoped request means the
    /// section re-enumerated empty (re-render, transient failure);
    /// the matching per-section cache is cleared to avoid stale
    /// bid leaks. An empty payload from an unscoped request (no
    /// `requestedSection`) drops silently — we don't know which
    /// section to clear.
    private func handleEnumeratedBlocks(
        _ blocks: [BilingualBlock],
        requestedSection: Int? = nil
    ) {
        if blocks.isEmpty {
            if let section = requestedSection {
                // Round-3 fix: the JS enumerated this specific
                // section and found no blocks. Clear any stale
                // cache so a later inject for that section cannot
                // resolve old bids.
                bilingualOrchestrator.clearBlocks(forSection: section)
            }
            return
        }
        // Partition the parsed payload by section. Untagged blocks
        // (older bundle / EPUB-style payload) bucket under `-1`.
        let byIndex = Dictionary(grouping: blocks, by: { $0.sectionIndex ?? -1 })
        for (sectionIndex, sectionBlocks) in byIndex {
            bilingualOrchestrator.updateBlocks(
                sectionBlocks, forSection: sectionIndex)
        }
        // Round-3 fix: a scoped enumerate may also need to drop
        // an OLD section's cache. If the JS host walked one section
        // and returned blocks tagged with a different index, the
        // requested section was empty even though the response
        // wasn't empty overall. This case is unusual but defensive.
        if let section = requestedSection,
           byIndex[section] == nil {
            bilingualOrchestrator.clearBlocks(forSection: section)
        }
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = makeCurrentLocator() else { return }
        Task { await vm.handlePositionChange(locator) }
        // If translations are already cached for the resolved unit,
        // inject immediately; otherwise the prefetch landing will
        // fire `.readerBilingualDidChange` and we inject then.
        injectIfCached()
    }

    /// Foliate section-load — a (possibly off-screen, preloaded)
    /// section's DOM has just been rendered. Gate-4 round-2 audit
    /// fix: this handler must NOT mutate the
    /// canonical current-section state. In paginated mode, foliate-js
    /// can fire section-load for an adjacent preloaded section
    /// *before* the user relocates there; only `.foliateRelocated`
    /// owns the "I'm on section N now" transition.
    ///
    /// What this handler does do is push an enumerate scoped to the
    /// loaded section so the orchestrator's per-section block cache
    /// gets populated for that section. When the user eventually
    /// relocates to it, the inject path has the blocks ready.
    private func handleSectionLoaded(_ userInfo: [AnyHashable: Any]?) {
        guard let loadedIndex = userInfo?["sectionIndex"] as? Int else {
            return
        }
        guard let vm = bilingualViewModel, vm.isEnabled,
              !showBilingualSetupSheet else { return }
        evalBilingualJS(
            bilingualOrchestrator.enumerateJS(
                sectionIndex: loadedIndex)
        )
    }

    /// Foliate relocate — fires for every position change including
    /// page turns that stay within an already-loaded section. Gate-4
    /// audit H1: update the current-section tracking here so a page
    /// turn into an already-loaded next section refreshes the
    /// prefetch / inject target. When the index actually changes,
    /// also push a scoped enumerate of the now-current section so
    /// the orchestrator's block cache reflects the live DOM.
    ///
    /// Gate-4 round-2 audit fix: this is the
    /// SOLE owner of the canonical current-section state. The
    /// `section-load` handler does NOT mutate it, because foliate-js
    /// can fire `section-load` for an adjacent preloaded section
    /// before the user relocates there.
    ///
    /// Note: we do NOT clear the just-left section's block cache.
    /// In paginated mode the user often returns to recently-visited
    /// sections (back-paging), and keeping the cache avoids a
    /// re-enumerate round-trip. The orchestrator's per-section
    /// cache only grows by section-load count, which is bounded by
    /// the book length, so this is not a leak hazard.
    private func handleRelocated(_ userInfo: [AnyHashable: Any]?) {
        guard let nextIndex = userInfo?["sectionIndex"] as? Int else {
            return
        }
        let previousIndex = currentSectionIndex
        currentSectionHref = String(nextIndex)
        currentSectionIndex = nextIndex

        guard let vm = bilingualViewModel, vm.isEnabled,
              !showBilingualSetupSheet else { return }

        // The current rendered section's block list lives on the
        // orchestrator already (a section-load fires before its
        // relocate). What we need on a within-loaded-section page
        // turn is to (a) ask the VM to prefetch the (possibly new)
        // current unit + its next, and (b) push an inject scoped to
        // the new section if translations are cached.
        if previousIndex != nextIndex {
            // The user moved into a new (already-loaded) section.
            // Refresh enumerate so the block list reflects the new
            // section's DOM — section-load may not fire when
            // foliate-js had the section preloaded in paginated
            // mode.
            evalBilingualJS(
                bilingualOrchestrator.enumerateJS(
                    sectionIndex: nextIndex)
            )
        }
        injectIfCached()
    }

    /// Build inject JS for the current unit's translations (if any
    /// are cached) and push it through the eval observer. No-op when
    /// the orchestrator has no blocks or the VM has no translations
    /// for the current unit. Gate-4 audit H2: scopes
    /// to the current section index so an adjacent loaded section
    /// (paginated mode) does not get this unit's translations.
    private func injectIfCached() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = makeCurrentLocator() else { return }
        let scopedIndex = currentSectionIndex
        Task { @MainActor in
            guard let provider = vm.textProvider,
                  let unit = await provider.unit(containing: locator),
                  let segments = vm.translations(for: unit) else { return }
            if let js = bilingualOrchestrator.buildInjectJS(
                translatedSegments: segments,
                sectionIndex: scopedIndex
            ) {
                evalBilingualJS(js)
            }
        }
    }

    /// Confirm path for the first-enable setup sheet. Commits the
    /// chosen language + granularity to the VM and runs the first
    /// enumerate against the user's choice.
    private func confirmBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.setTargetLanguage(bilingualSetupState.languageKey)
        vm.setGranularity(bilingualSetupState.granularity)
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        evalBilingualJS(
            bilingualOrchestrator.enumerateJS(
                sectionIndex: currentSectionIndex)
        )
    }

    /// Cancel path — dismiss the sheet and turn bilingual back off
    /// without persisting changes.
    private func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    // MARK: - Helpers

    /// Build a `Locator` for the current Foliate render position.
    /// Foliate provides the section's href via the relocate event;
    /// we shoulder no canonical-fingerprint validation here — the
    /// bilingual VM only reads `.href` for unit resolution.
    private func makeCurrentLocator() -> Locator? {
        guard let fp = DocumentFingerprint(canonicalKey: fingerprintKey) else {
            return nil
        }
        return Locator(
            bookFingerprint: fp,
            href: currentSectionHref,
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
    }

    /// Post a `.foliateRequestBilingualEvalJS` notification with the
    /// given JS payload. The spike's Coordinator observer picks it
    /// up and evaluates against the live `WKWebView`.
    private func evalBilingualJS(_ js: String) {
        NotificationCenter.default.post(
            name: .foliateRequestBilingualEvalJS,
            object: nil,
            userInfo: [
                "js": js,
                "fingerprintKey": fingerprintKey,
            ]
        )
    }
}

#endif
