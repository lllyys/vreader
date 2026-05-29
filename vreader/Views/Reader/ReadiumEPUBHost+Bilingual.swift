// Purpose: Feature #42 WI-11b/WI-12 — bilingual interlinear wiring for the
// Readium EPUB host. WI-12 lifted the WI-11 paged-only gate: bilingual now works
// in BOTH paged and scroll, PER-SPINE (Readium scroll mode enumerates one chapter
// at a time on scroll-into-view; it does NOT reproduce legacy #71's stitched
// cross-chapter continuous bilingual — see `ReadiumBilingualChapterTracker.swift`
// for the full delta). This file owns the parser/VM lifecycle, the More-menu
// toggle + setup sheet.
// The enumerate→prefetch→inject DRIVER methods live in
// `ReadiumEPUBHost+BilingualDriver.swift`, and the chapter-tracker dedup state +
// pure decision enums live in `Bilingual/ReadiumBilingualChapterTracker.swift`
// (300-line budget).
// Mirrors `EPUBReaderContainerView+Bilingual.swift` but drives the
// enumerate→prefetch→inject loop through Readium's one-way `evaluateJavaScript`
// channel via `ReadiumBilingualCommander` instead of the legacy WKWebView's
// `bilingualEnumerate` message handler + `pendingHighlightJS` seam (Readium owns
// its content controller — there is no message channel to app code).
//
// The pipeline: the More-menu row posts `.readerMoreBilingual` → the host toggles
// the VM (first enable raises the designed `BilingualSetupSheet`). Enumerate
// awaits `bilingualCommander.enumerate()` (the navigator eval RETURN value parsed
// into `[BilingualBlock]?`), replaces the orchestrator's PAGED `-1` bucket, then
// prefetches; when the prefetch lands the VM posts `.readerBilingualDidChange` and
// the host injects. A chapter change re-enumerates; an intra-chapter change is
// deduped by `ReadiumBilingualChapterTracker`. (Driver in `+BilingualDriver`.)
//
// Seam #3 (the WI-8 href-consistency finding class): the Readium host's vreader
// `Locator` carries Readium's CONTAINER-relative reading-order href, while the
// `EPUBChapterTextProvider` keys on OPF-relative spine hrefs.
// `ReadiumBilingualCommander.normalizedLocator(_:toSpineHrefs:)` rewrites the href
// onto the OPF spine before `vm.handlePositionChange(...)` so the unit resolves.
//
// SwiftUI `@State` cannot live in an extension, so the stored bilingual state is
// declared on the `ReadiumEPUBHost` struct in `ReadiumEPUBHost.swift`; this file
// owns the methods + the surfaces modifier + the setup-sheet view.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+BilingualDriver.swift,
//   ReadiumBilingualCommander.swift, EPUBBilingualOrchestrator.swift,
//   BilingualReadingViewModel.swift, EPUBChapterTextProvider.swift,
//   EPUBReaderContainerView+Bilingual.swift, ReaderNotifications.swift,
//   EPUBLayoutPreference.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import SwiftUI
import ReadiumShared

// `ReadiumBilingualChapterTracker` + its pure decision enums
// (`BilingualLayoutChangeAction`, `BilingualEnableAction`) live in
// `Bilingual/ReadiumBilingualChapterTracker.swift` (300-line budget).

extension ReadiumEPUBHost {

    // MARK: - Parser + VM lifecycle

    /// Opens vreader's own EPUB parser for the open book so the
    /// `EPUBChapterTextProvider` can supply per-spine source text for
    /// translation, and captures the OPF-relative spine hrefs for seam-#3
    /// normalization. Non-fatal on failure — bilingual just stays unavailable.
    func openBilingualParser() async {
        guard bilingualParser == nil else { return }
        let parser = EPUBParser()
        do {
            let metadata = try await parser.open(url: fileURL)
            bilingualParser = parser
            bilingualSpineHrefs = metadata.spineItems.map(\.href)
        } catch {
            // Leave bilingual unavailable for this book; logged by the parser.
        }
    }

    /// Lazily constructs the bilingual VM + prefetcher once the parser + spine
    /// are known. Idempotent — an already-built VM is preserved (a chapter swap
    /// must NOT discard prefetched translations).
    func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard let parser = bilingualParser, !bilingualSpineHrefs.isEmpty else { return }
        // Build the provider from vreader's OPF-relative spine (the parser keys
        // `contentForSpineItem` on these). The Readium-locator href is normalized
        // onto this same href space at the boundary (seam #3).
        let spineItems = bilingualSpineHrefs.enumerated().map { index, href in
            EPUBSpineItem(id: href, href: href, title: nil, index: index)
        }
        let textProvider = EPUBChapterTextProvider(
            parser: parser, spineItems: spineItems
        )
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: fingerprint.canonicalKey,
            perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
        )
        vm.attachProvider(textProvider)
        vm.attachPrefetcher(
            EPUBReaderContainerView.makePrefetcher(
                bookFingerprintKey: fingerprint.canonicalKey,
                textProvider: textProvider
            )
        )
        bilingualViewModel = vm
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage, granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        }
        // Feature #56 WI-14 parity: publish the provider so the Book Details
        // "Translate entire book…" entry point can consume it.
        NotificationCenter.default.post(
            name: .readerBookTranslationTextProviderAvailable,
            object: textProvider,
            userInfo: ["fingerprintKey": fingerprint.canonicalKey])
    }

    // MARK: - Toggle + setup sheet

    /// `.readerMoreBilingual` handler — toggles bilingual on/off. A first enable
    /// raises the designed setup sheet (defer enumerate to confirm so the
    /// prefetch uses the committed language); a subsequent enable runs enumerate
    /// straight away; disabling clears decorations.
    func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            bilingualChapterTracker.reset()
            Task { await bilingualCommander.clear() }
            return
        }
        // Finding B: first-enable confirmation must ALWAYS precede enumeration.
        // The setup sheet is layout-independent so a first enable raises the sheet.
        // WI-12: an already-configured re-enable enumerates the current spine in
        // BOTH layouts (Readium scroll mode is per-spine bilingual now).
        switch ReadiumBilingualChapterTracker.enableToggleAction(
            needsSetupSheet: vm.needsSetupSheet
        ) {
        case .presentSetup:
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage, granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        case .enumerate:
            runBilingualEnumerateForCurrentChapter()
        }
    }

    /// Commit the setup-sheet's language/granularity to the VM, dismiss it, and
    /// run the first enumerate under the chosen settings. WI-12: bilingual is now
    /// supported in both layouts, so the post-confirm enumerate runs for the
    /// current spine regardless of paged/scroll.
    func confirmBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.setTargetLanguage(bilingualSetupState.languageKey)
        vm.setGranularity(bilingualSetupState.granularity)
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        runBilingualEnumerateForCurrentChapter()
    }

    /// Dismiss the setup sheet without persisting and turn bilingual back off —
    /// the user opted out of first-enable.
    func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    // MARK: - Body surfaces

    /// The bilingual body modifiers, factored out of `ReadiumEPUBHost.body` for the
    /// 300-line budget. Owns the More-menu toggle observer, the prefetch-landed
    /// re-inject observer, the first-enable setup sheet, and the `epubLayout`-change
    /// handler (WI-12: re-enumerate the current spine on a paged↔scroll switch).
    /// Works in both paged and scroll (per-spine). Reuses the designed
    /// `BilingualSetupSheet` (rule 51).
    func bilingualSurfaces<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreBilingual)) { _ in
                handleMoreBilingualToggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerBilingualDidChange)) { notification in
                let key = notification.userInfo?["fingerprintKey"] as? String
                guard key == fingerprint.canonicalKey else { return }
                handleBilingualDidChange()
            }
            // WI-12: a paged↔scroll switch while bilingual is enabled re-renders the
            // spine in Readium, discarding the injected decorations + bid stamps, so
            // we re-enumerate the current spine in either direction.
            .onChange(of: settingsStore.epubLayout) { _, _ in
                handleEPUBLayoutChange()
            }
            .sheet(isPresented: $showBilingualSetupSheet) { bilingualSetupSheetView }
    }

    // MARK: - Setup sheet

    /// The first-enable `BilingualSetupSheet` (designed surface from #56). The
    /// More-menu toggle + prefetch-landed observers + `.sheet` presentation are
    /// driven by `bilingualSurfaces(_:)`.
    @ViewBuilder
    var bilingualSetupSheetView: some View {
        BilingualSetupSheet(
            theme: settingsStore.theme,
            state: $bilingualSetupState,
            engineDescriptor: BilingualEngineDescriptor(
                configured: true, providerName: nil, subtitle: nil
            ),
            onConfirm: { confirmBilingualSetup() },
            onCancel: { cancelBilingualSetup() },
            onOpenSettings: { cancelBilingualSetup() }
        )
    }
}
#endif
