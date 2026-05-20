// Purpose: Feature #56 WI-13 — PDF bilingual host wiring. Owns the
// `BilingualReadingViewModel` lifecycle, the `PDFChapterTextProvider`
// + `ChapterTranslationPrefetcher` build, the first-enable setup
// sheet, the More-menu toggle observer, the retry / open-AI-tab
// observers, the position-driven prefetch trigger, and the
// `.safeAreaInset`-attached `PDFBilingualPanel`.
//
// Mirrors `TXTReaderContainerView+Bilingual.swift` /
// `MDReaderContainerView+Bilingual.swift` /
// `EPUBReaderContainerView+Bilingual.swift` structurally.
//
// Key decisions:
// - **VM + prefetcher held as `@State` on the container.** SwiftUI
//   owns their lifecycle; container teardown frees everything.
// - **Lazy construction**: VM only spins up after the PDF document
//   has loaded (`isDocumentLoaded` AND `totalPages > 0`). The
//   container threads `viewModel.totalPages` via `.onChange` so the
//   lazy init fires when the document opens.
// - **No interlinear injection** — PDF page glyphs are fixed-layout.
//   The panel below the page is the entire bilingual surface.
// - **`PDFReaderViewModel.bookFingerprint` was promoted to `let`** so
//   this extension can build the `PDFChapterTextProvider` (Gate-2 v5
//   round-1 M2).
// - **State derivation is synchronous + pure** via
//   `PDFBilingualPanelState.panelState(...)`. The host's
//   `.readerPositionDidChange` observer drives `handlePositionChange`
//   to warm the cache; the panel itself reads VM state indexed by its
//   own synchronous unit derivation (Gate-2 v5 round-1 H1).
//
// @coordinates-with: PDFReaderContainerView.swift,
//   PDFBilingualPanel.swift, PDFBilingualPanelState.swift,
//   PDFReaderViewModel.swift, PDFChapterTextProvider.swift,
//   BilingualReadingViewModel.swift,
//   BilingualReadingViewModel+Prefetch.swift,
//   ChapterTranslationPrefetcher.swift, ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-13)

#if canImport(UIKit)
import SwiftUI

extension PDFReaderContainerView {

    /// Build the `ChapterPrefetching` adapter for the open PDF book.
    /// One per book; pins the `ChapterTranslationService` + active
    /// `AIService` for the book's lifetime in the reader. Mirrors
    /// `TXTReaderContainerView.makePrefetcher` exactly.
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
            promptVersion: TXTReaderContainerView.bilingualPromptVersion
        )
        return ChapterTranslationPrefetcher(
            bookFingerprintKey: bookFingerprintKey,
            textProvider: textProvider,
            translationService: service,
            aiService: aiService,
            style: .natural
        )
    }

    /// Build the PDF chapter-text adapter. Returns `nil` until the
    /// document has loaded (`isDocumentLoaded` + `totalPages > 0`).
    static func makeTextProvider(
        viewModel: PDFReaderViewModel, fileURL: URL
    ) -> PDFChapterTextProvider? {
        guard viewModel.isDocumentLoaded, viewModel.totalPages > 0 else {
            return nil
        }
        return PDFChapterTextProvider(
            fingerprint: viewModel.bookFingerprint,
            fileURL: fileURL
        )
    }

    // MARK: - Lifecycle helpers

    /// Lazily constructs the bilingual VM + prefetcher once the PDF
    /// document is loaded and has pages. Idempotent.
    ///
    /// Gate-4 round-1 H1: if the persisted state is `isEnabled ==
    /// true` AND the user does not navigate (book opens on page 0
    /// and stays), the `.onChange(of: currentPageIndexNonce)`
    /// observer never fires, so the bilingual panel would stay in
    /// `.loading` forever. After construction, if the VM is enabled
    /// AND the setup sheet is NOT needed (it's a re-open, not a
    /// first-enable), kick the initial `handlePositionChange` to warm
    /// the cache for the open page.
    func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard let textProvider = Self.makeTextProvider(
            viewModel: viewModel, fileURL: fileURL) else { return }
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
        if vm.needsSetupSheet {
            showBilingualSetupSheet = true
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
        }
        // Mirror the loaded-from-persistence state to the parent
        // container's chrome — `.readerBilingualDidChange` is the
        // notification the parent observes to repaint the pill /
        // More-menu row.
        vm.postDidChange()
        // Gate-4 round-1 H1: kick the initial prefetch for the open
        // page on a re-open (already-configured book). A first-enable
        // defers this to `confirmBilingualSetup()`.
        if vm.isEnabled && !vm.needsSetupSheet {
            triggerBilingualPositionChange()
        }
    }

    /// Handle a `.readerMoreBilingual` notification — toggle the
    /// bilingual VM's `isEnabled` state. Construct the VM lazily.
    func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            // Disabling clears the panel via state derivation (.off);
            // no JS to clear (no interlinear injection in PDF).
            return
        }
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        } else {
            // Subsequent enables (already-configured): immediately
            // trigger a position-change to warm the cache for the
            // current unit.
            triggerBilingualPositionChange()
        }
    }

    /// Commit the setup-sheet's chosen language + granularity to the
    /// VM and dismiss the sheet.
    func confirmBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.setTargetLanguage(bilingualSetupState.languageKey)
        vm.setGranularity(bilingualSetupState.granularity)
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        triggerBilingualPositionChange()
    }

    /// Dismiss the setup sheet without persisting changes and turn
    /// bilingual mode back off — the user opted out of first-enable.
    func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    /// Drive a one-shot prefetch for the current page. Used after
    /// enable / setup-sheet confirm / receiving
    /// `.readerPositionDidChange` (the panel itself doesn't observe
    /// the notification — the host does, to keep observation
    /// concentrated).
    func triggerBilingualPositionChange() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        let locator = viewModel.makeCurrentLocator()
        Task { await vm.handlePositionChange(locator) }
    }

    /// Handle a `.readerBilingualRetry` notification posted by the
    /// panel's offline-state Retry button — re-fetches the current
    /// unit only (NOT the whole-book cache).
    func handleBilingualRetry() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        let unit = currentBilingualUnit()
        vm.retryUnit(unit)
    }

    /// Resolve the current synchronously-derived unit (matches the
    /// panel's own derivation contract).
    func currentBilingualUnit() -> TranslationUnitID {
        let page = max(0, viewModel.currentPageIndex)
        return PDFBilingualPanelState.unitID(
            currentPage: page,
            pagesPerUnit: 1,
            totalPages: viewModel.totalPages
        )
    }

    // MARK: - Panel composition

    /// The view rendered into the bridge's `.safeAreaInset(edge: .bottom)`.
    /// `EmptyView` when bilingual is off (the inset reserves no space).
    @ViewBuilder
    var bilingualPanelInset: some View {
        let totalPages = viewModel.totalPages
        let page = max(0, viewModel.currentPageIndex)
        let state = PDFBilingualPanelState.panelState(
            viewModel: bilingualViewModel,
            currentPage: page,
            pagesPerUnit: 1,
            totalPages: totalPages
        )
        if state != .off {
            PDFBilingualPanel(
                state: state,
                theme: settingsStore?.theme ?? .paper,
                targetLanguage: bilingualViewModel?.targetLanguage
                    ?? BilingualReadingViewModel.defaultTargetLanguage,
                pageLabel: PDFBilingualPanelState.pageLabel(
                    currentPage: page,
                    pagesPerUnit: 1,
                    totalPages: totalPages
                ),
                isCollapsed: bilingualPanelCollapsed,
                onToggleCollapsed: { bilingualPanelCollapsed.toggle() },
                onRetry: { NotificationCenter.default.post(name: .readerBilingualRetry, object: nil) },
                onOpenAITab: {
                    NotificationCenter.default.post(name: .readerOpenAITranslate, object: nil)
                }
            )
            .frame(
                height: bilingualPanelCollapsed
                    ? PDFBilingualPanel.collapsedHeight
                    : PDFBilingualPanel.expandedHeight
            )
            .animation(.easeInOut(duration: 0.22), value: bilingualPanelCollapsed)
        } else {
            EmptyView()
        }
    }

    // MARK: - SwiftUI modifier bundle

    /// SwiftUI modifier bundling all PDF bilingual reading event
    /// hooks (lazy init, More-menu toggle, position-change prefetch,
    /// retry observer, setup sheet, bilingual-did-change re-paint
    /// trigger, `.readerOpenAITranslate` observer for the AI sheet).
    var bilingualSurfacesModifier: some ViewModifier {
        PDFBilingualSurfacesModifier(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            totalPagesNonce: viewModel.totalPages,
            currentPageIndexNonce: viewModel.currentPageIndex,
            ensureViewModel: { ensureBilingualViewModel() },
            onMoreBilingualToggle: { handleMoreBilingualToggle() },
            onPositionChanged: { triggerBilingualPositionChange() },
            onRetry: { handleBilingualRetry() },
            showSetupSheet: $showBilingualSetupSheet,
            sheetView: { AnyView(bilingualSetupSheetView) }
        )
    }

    /// The first-enable `BilingualSetupSheet` view.
    @ViewBuilder
    var bilingualSetupSheetView: some View {
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
            onOpenSettings: {
                // WI-15 hook — dismiss the sheet so the user can
                // navigate to Settings via the AA panel.
                cancelBilingualSetup()
            }
        )
    }
}

/// View modifier bundling PDF bilingual reading hooks. Encapsulates
/// the modifier graph so the container body stays under SwiftUI's
/// type-inference budget.
struct PDFBilingualSurfacesModifier: ViewModifier {
    let bookFingerprintKey: String
    let totalPagesNonce: Int
    let currentPageIndexNonce: Int
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    let onPositionChanged: () -> Void
    let onRetry: () -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: totalPagesNonce) { _, _ in ensureViewModel() }
            .onChange(of: currentPageIndexNonce) { _, _ in onPositionChanged() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerBilingualRetry)
            ) { _ in onRetry() }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
