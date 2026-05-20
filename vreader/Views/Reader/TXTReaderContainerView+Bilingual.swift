// Purpose: Feature #56 WI-12 — TXT bilingual host wiring. Adds
// `BilingualReadingViewModel` ownership, the first-enable setup-sheet
// presentation, and the `.readerMoreBilingual` observer that toggles
// the VM. Mirrors the WI-10 EPUB shape (see
// `EPUBReaderContainerView+Bilingual.swift`).
//
// The actual interlinear render-pipe (consuming the
// `BilingualTextRenderer` output into the TXT bridge's
// `NSAttributedString`) is deferred to a follow-up slice — the
// renderer + segment map are foundational and shipped under WI-12 so
// the next slice can wire them through the chunked/non-chunked
// rendering paths without re-implementing them. This slice ships the
// VM lifecycle + setup-sheet + More-menu activation + chrome-pill
// mirror; rendering injection into the live UITextView is a behavior
// the follow-up handles per-rendering-path.
//
// Key decisions:
// - **VM + prefetcher held as `@State`.** SwiftUI owns their
//   lifecycle; deinit on container teardown frees everything without
//   explicit cleanup. The translation service is lazily constructed
//   once per book so we don't pay the `.shared` store wiring on every
//   render.
// - **Lazy construction.** The VM only spins up after the parser has
//   exposed a chapter index — `ensureBilingualViewModel()` waits for
//   the `TXTChapterIndex` and constructs the `TXTChapterTextProvider`
//   then. The container observes the index via `onChange`.
// - **Setup-sheet bound to the VM's `needsSetupSheet` flag.** First
//   enable sets it; the confirm path commits the chosen language +
//   granularity and clears it. Cancel turns bilingual back off.
// - **No interlinear render injection in this slice.** The renderer +
//   segment map are exported via `BilingualTextRenderer.render(...)`
//   — consumers in the follow-up slice will swap `preparedAttrString`
//   / `chapterAttrString` / chunked content for the renderer's output
//   when `bilingualViewModel?.isEnabled == true`.
//
// @coordinates-with: TXTReaderContainerView.swift,
//   TXTChapterTextProvider.swift, BilingualReadingViewModel.swift,
//   BilingualTextRenderer.swift, BilingualDisplaySegmentMap.swift,
//   ChapterTranslationPrefetcher.swift, ReaderNotifications.swift,
//   EPUBReaderContainerView+Bilingual.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12)

#if canImport(UIKit)
import SwiftUI

extension TXTReaderContainerView {

    /// The single pinned prompt version for the chapter-bilingual
    /// pipeline. Shared with EPUB / Foliate; a bump invalidates every
    /// cached row at once.
    static let bilingualPromptVersion = "bilingual-v1"

    /// Build the `ChapterPrefetching` adapter for the open TXT book.
    /// One per book; the adapter pins the `ChapterTranslationService`
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

    /// Build the TXT chapter-text adapter from the VM's chapter index
    /// + full text. Returns `nil` until the index is populated (the
    /// container threads that state in via `onChange`).
    static func makeTextProvider(
        viewModel: TXTReaderViewModel
    ) -> TXTChapterTextProvider? {
        guard let index = viewModel.chapterIndex,
              !index.chapters.isEmpty else { return nil }
        // The provider reads from the full text; in chapter-based mode
        // the VM may not hold the whole book in `textContent`, so we
        // reconstruct from the chapter list's offset bounds. The
        // simplest valid source is the concatenation in order — which
        // matches `TXTChapterIndex.totalTextLengthUTF16` (the index's
        // own invariant).
        let fullText: String
        if let content = viewModel.textContent {
            fullText = content
        } else {
            // The index alone doesn't carry text. Without
            // `viewModel.textContent`, the provider's `sourceText`
            // can't slice safely — return nil so the VM waits for
            // text to be available (continuous mode populates
            // `textContent` lazily; chapter-paged mode loads chapter
            // text per navigation but not the whole book).
            //
            // The follow-up slice that wires the renderer into the
            // live UITextView will need to ensure `textContent` is
            // populated, or extend the provider to slice per-chapter
            // from the VM's chapter-text cache. WI-12 leaves the
            // hook in place but accepts source-only render when text
            // isn't yet available.
            return nil
        }
        return TXTChapterTextProvider(
            fingerprint: viewModel.bookFingerprint,
            fullText: fullText,
            chapters: index.chapters
        )
    }

    // MARK: - Bilingual surface modifier + event handlers

    /// Lazily constructs the bilingual VM + prefetcher once the
    /// chapter index becomes available. Idempotent — already-
    /// constructed VM is preserved on subsequent calls.
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
    }

    /// Handle a `.readerMoreBilingual` notification — toggle the
    /// bilingual VM's `isEnabled` state. Construct the VM lazily if
    /// the More menu fired before the chapter index loaded.
    func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            return
        }
        // A first enable raises the setup sheet — the user has not yet
        // confirmed the target language / granularity.
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
    /// bilingual mode back off — the user opted out of first-enable.
    func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    /// SwiftUI modifier bundling all bilingual reading event hooks.
    var bilingualSurfacesModifier: some ViewModifier {
        TXTBilingualSurfacesModifier(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            chapterIndexNonce: viewModel.chapterIndex?.count,
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
                // WI-15 hook — for now, dismiss the sheet so the user
                // can navigate to Settings via the AA panel.
                cancelBilingualSetup()
            }
        )
    }
}

/// View modifier bundling TXT bilingual reading hooks — the lazy VM
/// construction, the More-menu toggle, and the first-enable setup
/// sheet. Encapsulates the modifier graph so the container body stays
/// under SwiftUI's type-inference budget.
struct TXTBilingualSurfacesModifier: ViewModifier {
    let bookFingerprintKey: String
    let chapterIndexNonce: Int?
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: chapterIndexNonce) { _, _ in ensureViewModel() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
