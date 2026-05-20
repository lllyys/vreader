// Purpose: Feature #56 WI-12 — MD bilingual host wiring. Mirrors
// `TXTReaderContainerView+Bilingual.swift` for the Markdown reader.
// Adds `BilingualReadingViewModel` ownership, first-enable setup
// sheet presentation, and the `.readerMoreBilingual` observer that
// toggles the VM.
//
// Like the TXT slice, the actual interlinear render-pipe (consuming
// the `BilingualTextRenderer` output into the MD bridge's
// `NSAttributedString`) is deferred to a follow-up — the renderer +
// segment map are foundational and shipped under WI-12 so the next
// slice can wire them through without re-implementing them.
//
// Key decisions:
// - **VM + prefetcher held as `@State`.** SwiftUI owns their
//   lifecycle; deinit on container teardown frees everything.
// - **Lazy construction.** The VM only spins up after the parser has
//   exposed `renderedText` + `headings` — `ensureBilingualViewModel()`
//   waits for both, then constructs `MDChapterTextProvider`. The
//   container observes the heading count via `onChange` so the lazy
//   init fires when parsing completes.
// - **No interlinear render injection in this slice.** Same as the
//   TXT extension — the renderer is exported; injection into the
//   live UITextView is the next slice.
//
// @coordinates-with: MDReaderContainerView.swift,
//   MDChapterTextProvider.swift, BilingualReadingViewModel.swift,
//   BilingualTextRenderer.swift, BilingualDisplaySegmentMap.swift,
//   ChapterTranslationPrefetcher.swift, ReaderNotifications.swift,
//   EPUBReaderContainerView+Bilingual.swift,
//   TXTReaderContainerView+Bilingual.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12)

#if canImport(UIKit)
import SwiftUI

extension MDReaderContainerView {

    /// Build the `ChapterPrefetching` adapter for the open MD book.
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

    /// Build the MD chapter-text adapter from the VM's rendered text +
    /// heading list. Returns `nil` until both are populated (the
    /// container threads the heading-count nonce in via `onChange`).
    static func makeTextProvider(
        viewModel: MDReaderViewModel
    ) -> MDChapterTextProvider? {
        guard let text = viewModel.renderedText,
              let headings = viewModel.headings else { return nil }
        return MDChapterTextProvider(
            fingerprint: viewModel.bookFingerprint,
            renderedText: text,
            headings: headings
        )
    }

    // MARK: - Bilingual surface modifier + event handlers

    /// Lazily constructs the bilingual VM + prefetcher once parsing
    /// has populated `renderedText` + `headings`. Idempotent.
    ///
    /// Codex Gate-4 round-1 finding [M3]: if persistence loaded
    /// `isEnabled == true` (the user previously enabled bilingual
    /// for this book), the parent `ReaderContainerView` needs to
    /// learn that state so the chrome pill paints correctly on open.
    /// Without this `postDidChange()`, the parent stays in the
    /// default `bilingualActive = false` state until the user
    /// toggles manually.
    func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard let textProvider = Self.makeTextProvider(viewModel: viewModel) else { return }
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
        // container's chrome.
        vm.postDidChange()
        // Feature #56 WI-14: publish the MD chapter-text provider to
        // the parent ReaderContainerView so the Book Details translate-
        // entire-book entry point can consume it. Sibling of the
        // TXT/EPUB/Foliate publishers.
        NotificationCenter.default.post(
            name: .readerBookTranslationTextProviderAvailable,
            object: textProvider,
            userInfo: ["fingerprintKey": viewModel.bookFingerprintKey])
    }

    /// Handle a `.readerMoreBilingual` notification — toggle the
    /// bilingual VM's `isEnabled` state. Construct the VM lazily.
    func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            return
        }
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
            showBilingualSetupSheet = true
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
    }

    /// Dismiss the setup sheet without persisting changes and turn
    /// bilingual mode back off.
    func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    /// SwiftUI modifier bundling all bilingual reading event hooks.
    var bilingualSurfacesModifier: some ViewModifier {
        MDBilingualSurfacesModifier(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            headingsNonce: viewModel.headings?.count,
            ensureViewModel: { ensureBilingualViewModel() },
            onMoreBilingualToggle: { handleMoreBilingualToggle() },
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

/// View modifier bundling MD bilingual reading hooks.
struct MDBilingualSurfacesModifier: ViewModifier {
    let bookFingerprintKey: String
    let headingsNonce: Int?
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: headingsNonce) { _, _ in ensureViewModel() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
