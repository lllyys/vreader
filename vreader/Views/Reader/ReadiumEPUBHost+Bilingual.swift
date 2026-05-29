// Purpose: Feature #42 WI-11b — bilingual interlinear wiring for the Readium
// EPUB host (PAGED path only — continuous-scroll bilingual parity is WI-12).
// This file owns the parser/VM lifecycle, the More-menu toggle + setup sheet,
// and the chapter-tracker decision type. The enumerate→prefetch→inject DRIVER
// methods live in `ReadiumEPUBHost+BilingualDriver.swift` (300-line budget).
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
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+BilingualDriver.swift,
//   ReadiumBilingualCommander.swift, EPUBBilingualOrchestrator.swift,
//   BilingualReadingViewModel.swift, EPUBChapterTextProvider.swift,
//   EPUBReaderContainerView+Bilingual.swift, ReaderNotifications.swift,
//   EPUBLayoutPreference.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import SwiftUI
import ReadiumShared

/// Reference-type chapter-change dedup + pure decision logic for the Readium
/// bilingual loop. A class (not a value `@State`) so the `onLocationChange`
/// closure — captured at body-eval — mutates the live instance rather than a
/// stale value snapshot. The static helpers are pure (unit-tested in
/// `ReadiumBilingualChapterTrackerTests`).
@MainActor
final class ReadiumBilingualChapterTracker {
    /// The spine href the bilingual loop last enumerated (or has IN FLIGHT). `nil`
    /// until the first enumerate. An intra-chapter location change (same href) is
    /// deduped. Gate-4 MED-3: this is written SYNCHRONOUSLY in `shouldEnumerate`
    /// BEFORE the async enumerate launches, so a repeated `locationDidChange` for
    /// the same href before the eval completes does not schedule a second run.
    private(set) var lastEnumeratedHref: String?
    init() {}

    /// MED-3: synchronous dedupe gate. Returns whether an enumerate should run for
    /// `href` and, when it should, records the href immediately so a duplicate
    /// organic trigger arriving before the async enumerate completes is deduped.
    /// A `force` enumerate (the toggle/confirm path, where the user just enabled
    /// bilingual on the chapter they were already reading) bypasses the dedupe and
    /// still records the in-flight href.
    @discardableResult
    func shouldEnumerate(forHref href: String?, force: Bool) -> Bool {
        if !force, let href, href == lastEnumeratedHref { return false }
        lastEnumeratedHref = href
        return true
    }

    /// Records the href an enumerate actually ran for (the resolved spine href),
    /// keeping the dedupe key consistent after the async enumerate returns.
    func markEnumerated(href: String?) {
        if let href { lastEnumeratedHref = href }
    }

    /// Clears the dedupe state so the next location change re-enumerates (disable
    /// + the prefetch-disabled path).
    func reset() {
        lastEnumeratedHref = nil
    }

    /// HIGH-1: resolve the visible-chapter href for the bilingual unit lookup.
    /// Prefers the supplied Readium locator href, then the host's last-known
    /// locator href (the toggle/confirm first-enable path), then the
    /// last-enumerated href (a prefetch-landed inject that carries no locator).
    /// Never resets the only available source before reading it.
    nonisolated static func selectedHref(
        supplied: String?, lastKnown: String?, lastEnumerated: String?
    ) -> String? {
        supplied ?? lastKnown ?? lastEnumerated
    }

    /// MED-4: PAGED-only gate. Continuous-scroll bilingual is WI-12, so the
    /// enumerate/inject path no-ops in `.scroll` (the paged single-spine block
    /// assumptions do not hold there).
    nonisolated static func isBilingualSupported(forLayout layout: EPUBLayoutPreference) -> Bool {
        layout == .paged
    }
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
            bilingualChapterTracker.reset()
            Task { await bilingualCommander.clear() }
            return
        }
        // MED-4: continuous-scroll bilingual is WI-12. The VM toggle still flips
        // (so the per-book preference persists), but skip enumerate/inject and
        // keep the spine clear when the layout is not paged.
        guard ReadiumBilingualChapterTracker.isBilingualSupported(
            forLayout: settingsStore.epubLayout
        ) else {
            bilingualChapterTracker.reset()
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
