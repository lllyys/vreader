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
    /// + full book text. Returns `nil` until BOTH the index is
    /// populated AND the VM holds the **full book** in `textContent`.
    ///
    /// `TXTChapterTextProvider` slices by document-global UTF-16
    /// offsets, so it MUST be backed by full-book text — chapter-
    /// local slices would yield wrong source for every chapter except
    /// the open one.
    ///
    /// Where each TXT-VM mode lives on this axis:
    ///
    /// | mode | `textContent` content | safe to construct? |
    /// |---|---|---|
    /// | continuous (`isContinuousMode == true`) | full book | yes |
    /// | legacy small-file (`isChapterMode == false`) | full book | yes |
    /// | chapter-paged (`isChapterMode == true && isContinuousMode == false`) | current chapter only | NO |
    ///
    /// Chapter-paged mode is deliberately disabled for WI-12a; the
    /// follow-up WI-12b introduces a loader-backed text provider
    /// that reads chapter text on demand from
    /// `TXTChapterContentLoader`, so the chapter-paged path will be
    /// enabled then.
    ///
    /// Codex Gate-4 round-1 finding [H2] + round-2 follow-up: a
    /// prior version of this helper guarded only on `textContent !=
    /// nil`, but the TXT VM sets `textContent = chapterText` on
    /// chapter navigation in chapter-paged mode (lines 376 and 561
    /// of `TXTReaderViewModel.swift`). Slicing document-global
    /// offsets out of that chapter-local string would corrupt every
    /// non-open chapter. The fix is the explicit mode check below.
    static func makeTextProvider(
        viewModel: TXTReaderViewModel
    ) -> TXTChapterTextProvider? {
        guard let index = viewModel.chapterIndex,
              !index.chapters.isEmpty else { return nil }
        // Reject chapter-paged mode — `textContent` is chapter-local.
        if viewModel.isChapterMode && !viewModel.isContinuousMode {
            return nil
        }
        guard let fullText = viewModel.textContent else { return nil }
        return TXTChapterTextProvider(
            fingerprint: viewModel.bookFingerprint,
            fullText: fullText,
            chapters: index.chapters
        )
    }

    // MARK: - Bilingual surface modifier + event handlers

    /// Lazily constructs the bilingual VM + prefetcher once the
    /// chapter index AND the full book text become available.
    /// Idempotent — already-constructed VM is preserved on
    /// subsequent calls.
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
        // container's chrome — `.readerBilingualDidChange` is the
        // notification the parent observes to repaint the pill /
        // More-menu row.
        vm.postDidChange()
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
    /// The chapter-index nonce composes both `chapterIndex?.count`
    /// AND whether `textContent` has been populated — VM
    /// construction requires both (Codex Gate-4 round-1 finding
    /// [H2] requires the full book text), so the modifier triggers
    /// `ensureViewModel` on changes in either.
    var bilingualSurfacesModifier: some ViewModifier {
        TXTBilingualSurfacesModifier(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            chapterIndexNonce: viewModel.chapterIndex?.count,
            textContentReady: viewModel.textContent != nil,
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
    let textContentReady: Bool
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: chapterIndexNonce) { _, _ in ensureViewModel() }
            .onChange(of: textContentReady) { _, _ in ensureViewModel() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
