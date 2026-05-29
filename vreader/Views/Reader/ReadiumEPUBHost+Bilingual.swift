// Purpose: Feature #42 WI-11b — bilingual interlinear wiring for the Readium
// EPUB host (PAGED path only — continuous-scroll bilingual parity is WI-12).
// Mirrors `EPUBReaderContainerView+Bilingual.swift` but drives the
// enumerate→prefetch→inject loop through Readium's one-way `evaluateJavaScript`
// channel via `ReadiumBilingualCommander` instead of the legacy WKWebView's
// `bilingualEnumerate` message handler + `pendingHighlightJS` seam (Readium owns
// its content controller — there is no message channel to app code).
//
// The pipeline:
//   1. The More-menu bilingual row posts `.readerMoreBilingual` → the host
//      toggles `BilingualReadingViewModel.isEnabled`. A FIRST enable raises the
//      designed `BilingualSetupSheet`; confirm runs enumerate; a subsequent
//      enable runs enumerate straight away.
//   2. Enumerate awaits `bilingualCommander.enumerate()` (the navigator's
//      `evaluateJavaScript(enumerateJS())` RETURN value parsed into
//      `[BilingualBlock]`), replaces the orchestrator's PAGED `-1` bucket via
//      `updateBlocks(_:)`, then asks the VM to prefetch the current unit.
//   3. When the prefetch lands, the VM posts `.readerBilingualDidChange`; the
//      host builds inject JS via the orchestrator and awaits
//      `bilingualCommander.inject(...)`.
//   4. A chapter change (spine href differs) re-enumerates; an intra-chapter
//      location change is deduped by `ReadiumBilingualChapterTracker`.
//
// Seam #3 (the WI-8 href-consistency finding class): the vreader `Locator` the
// Readium host produces carries Readium's CONTAINER-relative reading-order href;
// the `EPUBChapterTextProvider` is keyed on vreader's OPF-relative spine hrefs.
// `ReadiumBilingualCommander.normalizedLocator(_:toSpineHrefs:)` rewrites the
// href onto the OPF spine before `vm.handlePositionChange(...)` so the unit
// resolves (unit-pinned by `ReadiumBilingualCommanderTests`).
//
// SwiftUI `@State` cannot live in an extension, so the stored bilingual state
// (commander / orchestrator / VM / parser / setup-sheet flags / chapter tracker)
// is declared on the `ReadiumEPUBHost` struct in `ReadiumEPUBHost.swift`; this
// file owns the methods + the surfaces modifier + the setup-sheet view.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumBilingualCommander.swift,
//   EPUBBilingualOrchestrator.swift, BilingualReadingViewModel.swift,
//   EPUBChapterTextProvider.swift, EPUBReaderContainerView+Bilingual.swift,
//   ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import SwiftUI
import ReadiumShared

/// Reference-type chapter-change dedup for the Readium bilingual loop. A class
/// (not a value `@State`) so the `onLocationChange` closure — captured at
/// body-eval — mutates the live instance rather than a stale value snapshot.
@MainActor
final class ReadiumBilingualChapterTracker {
    /// The spine href the bilingual loop last enumerated. `nil` until the first
    /// enumerate. An intra-chapter location change (same href) is deduped.
    var lastEnumeratedHref: String?
    init() {}
}

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
            bilingualChapterTracker.lastEnumeratedHref = nil
            Task { await bilingualCommander.clear() }
            return
        }
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage, granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        } else {
            runBilingualEnumerateForCurrentChapter()
        }
    }

    /// Commit the setup-sheet's language/granularity to the VM, dismiss it, and
    /// run the first enumerate under the chosen settings.
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

    // MARK: - Enumerate / inject driver

    /// Runs a fresh enumerate for whatever spine is currently visible, forcing a
    /// re-enumerate even within the same chapter (used by the toggle/confirm
    /// paths where the user just enabled on an already-rendered chapter). Resets
    /// the chapter tracker so the next location change is not mistaken for a
    /// dedup hit.
    func runBilingualEnumerateForCurrentChapter() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        bilingualChapterTracker.lastEnumeratedHref = nil
        Task { await runBilingualEnumerate(currentReadiumLocator: nil) }
    }

    /// Drive the bilingual chapter-change enumerate off the navigator's
    /// `locationDidChange`. A fresh enumerate runs only when the resolved spine
    /// href changes AND bilingual is enabled; an intra-chapter scroll is deduped
    /// against the chapter tracker so it does NOT re-enumerate.
    func handleBilingualLocationChange(_ readiumLocator: ReadiumShared.Locator) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        let href = readiumLocator.href.string
        guard href != bilingualChapterTracker.lastEnumeratedHref else { return }
        Task { await runBilingualEnumerate(currentReadiumLocator: readiumLocator) }
    }

    /// The shared enumerate→prefetch driver. Enumerates the live spine via the
    /// commander, replaces the orchestrator's PAGED block bucket, marks the
    /// chapter as enumerated, and asks the VM to prefetch the current unit
    /// (resolving the unit through the seam-#3 normalized locator). The actual
    /// inject runs later, off `.readerBilingualDidChange`, once the prefetch
    /// lands.
    private func runBilingualEnumerate(
        currentReadiumLocator: ReadiumShared.Locator?
    ) async {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        let blocks = await bilingualCommander.enumerate()
        bilingualOrchestrator.updateBlocks(blocks)
        // Mark the chapter enumerated so an intra-chapter scroll is deduped.
        if let href = currentReadiumLocator?.href.string {
            bilingualChapterTracker.lastEnumeratedHref = href
        }
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

    /// `.readerBilingualDidChange` handler — the VM's prefetch landed (or it
    /// disabled). On disable, clear decorations; otherwise inject the now-cached
    /// translation for the current chapter.
    func handleBilingualDidChange() {
        guard let vm = bilingualViewModel else { return }
        if !vm.isEnabled {
            bilingualChapterTracker.lastEnumeratedHref = nil
            Task { await bilingualCommander.clear() }
            return
        }
        Task {
            guard let locator = currentVReaderLocator(from: nil) else { return }
            await injectBilingualIfCached(for: locator)
        }
    }

    /// Builds the seam-#3-normalized vreader `Locator` for the current chapter.
    /// Prefers the supplied Readium locator's href; falls back to the chapter
    /// tracker's last-enumerated href (so an inject driven by a prefetch-landed
    /// notification — which carries no locator — still resolves the unit).
    private func currentVReaderLocator(
        from readiumLocator: ReadiumShared.Locator?
    ) -> Locator? {
        let href = readiumLocator?.href.string ?? bilingualChapterTracker.lastEnumeratedHref
        guard let href else { return nil }
        let raw = Locator(
            bookFingerprint: fingerprint,
            href: href,
            progression: readiumLocator?.locations.progression,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return ReadiumBilingualCommander.normalizedLocator(
            raw, toSpineHrefs: bilingualSpineHrefs
        )
    }

    // MARK: - Setup sheet

    /// The first-enable `BilingualSetupSheet` (designed surface from #56). The
    /// More-menu toggle + prefetch-landed observers + `.sheet` presentation are
    /// wired inline in `ReadiumEPUBHost.body`.
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
