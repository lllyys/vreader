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

    /// Gate-4 round-3 MED-2: reverts the in-flight mark recorded by
    /// `shouldEnumerate` when that href's enumerate FAILED (eval returned nil), so
    /// a later `locationDidChange` for the same chapter retries instead of being
    /// permanently deduped (the chapter would otherwise stay blank forever). Only
    /// reverts when the current in-flight href still matches — a newer chapter that
    /// already moved on (its own enumerate legitimately in flight) is left intact.
    func clearInFlight(href: String?) {
        if lastEnumeratedHref == href {
            lastEnumeratedHref = nil
        }
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

    /// Gate-4 round-3 MED-3: pure decision for an `epubLayout` change while
    /// bilingual is enabled. Enumerate is paged-gated, so paged→scroll must CLEAR
    /// the injected decorations + reset the tracker (else stale nodes linger), and
    /// scroll→paged must RE-ENUMERATE so translation reappears. Disabled → no-op.
    nonisolated static func layoutChangeAction(
        newLayout: EPUBLayoutPreference, isEnabled: Bool
    ) -> BilingualLayoutChangeAction {
        guard isEnabled else { return .none }
        return isBilingualSupported(forLayout: newLayout) ? .reEnumerate : .clearAndReset
    }
}

/// Gate-4 round-3 MED-3: the action the host takes when `epubLayout` changes while
/// bilingual is enabled. Pure value so the decision is unit-testable apart from the
/// SwiftUI `.onChange` plumbing.
enum BilingualLayoutChangeAction: Equatable {
    /// Leaving paged: clear injected decorations + reset the chapter tracker.
    case clearAndReset
    /// Returning to paged: re-enumerate the current chapter so translation returns.
    case reEnumerate
    /// Disabled, or no observable change — do nothing.
    case none
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

    // MARK: - Body surfaces

    /// Gate-4 round-3 MED-3: the bilingual body modifiers, factored out of
    /// `ReadiumEPUBHost.body` for the 300-line budget. Owns the More-menu toggle
    /// observer, the prefetch-landed re-inject observer, the first-enable setup
    /// sheet, and the `epubLayout`-change handler (clear+reset on leaving paged /
    /// re-enumerate on returning). PAGED path only — continuous bilingual is WI-12.
    /// Reuses the designed `BilingualSetupSheet` (rule 51).
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
            // Gate-4 round-3 MED-3: a paged↔scroll switch while bilingual is enabled
            // must clear stale decorations (leaving paged) or re-enumerate the
            // current chapter (returning to paged) — enumerate is paged-gated, so
            // without this the injected nodes linger or never reappear.
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
