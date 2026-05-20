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
    /// prefetch + inject.
    @State private var currentSectionHref: String?

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
            handleEnumeratedBlocks(blocks)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateSectionLoaded)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == fingerprintKey else { return }
            handleSectionLoaded(notification.userInfo)
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
            evalBilingualJS(bilingualOrchestrator.enumerateJS())
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
    /// cache the blocks and ask the VM to prefetch the current unit.
    private func handleEnumeratedBlocks(_ blocks: [BilingualBlock]) {
        bilingualOrchestrator.updateBlocks(blocks)
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = makeCurrentLocator() else { return }
        Task { await vm.handlePositionChange(locator) }
        // If translations are already cached for the resolved unit,
        // inject immediately; otherwise the prefetch landing will
        // fire `.readerBilingualDidChange` and we inject then.
        injectIfCached()
    }

    /// Foliate section-load — record the current section's index
    /// (as a string, matching `TranslationUnitID.Kind.foliateHref`
    /// semantics) so the next inject resolves to the right unit.
    /// If bilingual is on and the setup sheet is not open, push an
    /// enumerate so the orchestrator's block list matches the
    /// freshly-rendered section.
    private func handleSectionLoaded(_ userInfo: [AnyHashable: Any]?) {
        if let idx = userInfo?["sectionIndex"] as? Int {
            currentSectionHref = String(idx)
        }
        guard let vm = bilingualViewModel, vm.isEnabled,
              !showBilingualSetupSheet else { return }
        evalBilingualJS(bilingualOrchestrator.enumerateJS())
    }

    /// Build inject JS for the current unit's translations (if any
    /// are cached) and push it through the eval observer. No-op when
    /// the orchestrator has no blocks or the VM has no translations
    /// for the current unit.
    private func injectIfCached() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = makeCurrentLocator() else { return }
        Task {
            guard let provider = await vm.textProvider,
                  let unit = await provider.unit(containing: locator),
                  let segments = await vm.translations(for: unit) else { return }
            await MainActor.run {
                if let js = bilingualOrchestrator.buildInjectJS(
                    translatedSegments: segments
                ) {
                    evalBilingualJS(js)
                }
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
        evalBilingualJS(bilingualOrchestrator.enumerateJS())
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
