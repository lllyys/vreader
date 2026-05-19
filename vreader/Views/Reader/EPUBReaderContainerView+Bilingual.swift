// Purpose: Feature #56 WI-10 — EPUB bilingual wiring extension.
// Adds the `BilingualReadingViewModel` ownership, the
// `EPUBBilingualOrchestrator` + enumerate / inject / clear JS
// dispatch, the first-enable setup-sheet presentation, and the
// `.readerMoreBilingual` observer that toggles bilingual mode.
//
// Sits as a separate file to keep `EPUBReaderContainerView.swift`
// under the ~300-line budget (rule 50 §9) while concentrating all
// bilingual state in one place. The container hosts the
// `@State` instances and applies the modifier `bilingualSurfaces(...)`
// returned here.
//
// Key decisions:
// - **VM + orchestrator + service held as `@State`.** SwiftUI owns
//   their lifecycle; deinit on container teardown frees everything
//   without explicit cleanup. The translation service is lazily
//   constructed once per book so we don't pay the `.shared` store
//   wiring on every render.
// - **Pipeline is event-driven.** Chapter `didFinish` → `enumerateJS`
//   runs. The bridge's `onBilingualEnumerate` callback parses
//   blocks → ask the VM to prefetch → on `.readerBilingualDidChange`,
//   build inject JS via the orchestrator and push through the
//   bridge's `pendingHighlightJS` seam (the same seam highlights
//   use, so chapter-swap defers correctly per Bug #182).
// - **The setup sheet binding is the VM's `needsSetupSheet`.** The
//   VM sets it on first-enable; the sheet's confirm closes it via
//   `dismissSetupSheet()`.
//
// @coordinates-with: EPUBReaderContainerView.swift,
//   EPUBBilingualJS.swift, EPUBBilingualOrchestrator.swift,
//   EPUBBilingualPipeline.swift, BilingualReadingViewModel.swift,
//   ChapterTranslationPrefetcher.swift, ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    /// Build the `ChapterPrefetching` adapter for the open book.
    /// One per book; constructed lazily after the parser exposes
    /// the spine list so the `EPUBChapterTextProvider` has its
    /// source ready. The adapter pins the `ChapterTranslationService`
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

    /// The single pinned prompt version for the chapter-bilingual
    /// pipeline. Stored on the `lookupKey` so a bump invalidates
    /// every cached row at once (re-translation is then a single
    /// schema-change-class operation).
    static let bilingualPromptVersion = "bilingual-v1"

    /// Build the EPUB chapter-text adapter for the open book once
    /// the parser + spine list are known. Returns `nil` until the
    /// parser has loaded its metadata (the container threads that
    /// state in).
    static func makeTextProvider(
        parser: any EPUBParserProtocol,
        spineItems: [EPUBSpineItem]?
    ) -> EPUBChapterTextProvider? {
        guard let spine = spineItems, !spine.isEmpty else { return nil }
        return EPUBChapterTextProvider(parser: parser, spineItems: spine)
    }

    // MARK: - Bilingual surface modifier + event handlers

    /// Lazily constructs the bilingual VM + prefetcher after EPUB
    /// metadata has loaded. Idempotent — already-constructed VM is
    /// preserved on subsequent calls (a chapter swap inside the
    /// same book must NOT discard prefetched translations).
    func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard viewModel.metadata != nil else { return }
        let spine = viewModel.metadata?.spineItems
        guard let textProvider = Self.makeTextProvider(
            parser: parser, spineItems: spine
        ) else { return }
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
        // Surface the first-enable setup sheet if the VM raised it
        // before construction completed (it shouldn't have, but
        // mirror state defensively).
        if vm.needsSetupSheet {
            showBilingualSetupSheet = true
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
        }
    }

    /// Process a parsed `[BilingualBlock]` from the JS enumerate
    /// channel. Replaces the orchestrator's block list and asks the
    /// VM to prefetch translation for the current unit (idempotent —
    /// the VM dedupes by `lastTriggerUnit`).
    func handleBilingualBlocks(_ blocks: [BilingualBlock]) {
        bilingualOrchestrator.updateBlocks(blocks)
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = viewModel.makeCurrentLocator() else { return }
        Task { await vm.handlePositionChange(locator) }
        // If the VM already has cached translations for the current
        // unit, inject immediately; otherwise the next
        // `.readerBilingualDidChange` (posted when prefetch lands)
        // is when inject JS gets pushed.
        injectBilingualIfCached(for: locator)
    }

    /// Build inject JS for the current unit's translations (if any
    /// are cached) and push through the bridge's `pendingHighlightJS`
    /// seam. A no-op when the orchestrator has no blocks or the
    /// VM has no translations for the current unit.
    func injectBilingualIfCached(for locator: Locator) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        Task {
            guard let unit = await vm.textProvider?.unit(containing: locator),
                  let segments = vm.translations(for: unit) else { return }
            await MainActor.run {
                if let js = bilingualOrchestrator.buildInjectJS(
                    translatedSegments: segments
                ) {
                    pendingHighlightJS = js
                }
            }
        }
    }

    /// Build clear JS and push through `pendingHighlightJS` to
    /// remove every bilingual decoration node from the live chapter.
    func clearBilingualDecorations() {
        pendingHighlightJS = bilingualOrchestrator.clearJS()
    }

    /// Handle a `.readerMoreBilingual` notification — toggle the
    /// bilingual VM's `isEnabled` state. Construct the VM lazily if
    /// the More menu fired before metadata loaded (a rare edge — the
    /// menu is gated on the chrome which only appears after load).
    ///
    /// Codex Gate-4 audit finding [3]: enabling bilingual on an
    /// already-loaded chapter must trigger a fresh enumerate so the
    /// orchestrator's `currentBlocks` populates and the next
    /// `.readerBilingualDidChange` (posted when the prefetch lands)
    /// can build inject JS. Without this push, the current chapter
    /// stays source-only until the user navigates to a new chapter.
    func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            clearBilingualDecorations()
            return
        }
        // Codex Gate-4 round-2 finding [R2-2]: a FIRST enable raises
        // the setup sheet — the user has not yet confirmed the
        // target language / granularity. We must NOT trigger
        // enumerate (and therefore the prefetch) until either the
        // confirm path runs OR the user cancels (which turns
        // bilingual back off). A subsequent enable (no setup sheet
        // — `hasBeenConfigured == true`) goes straight to enumerate
        // since the user's prior choice is reused.
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        } else {
            // No setup-sheet gate — run enumerate against the live
            // DOM. The bridge's `pendingJS` seam applies it
            // immediately; the resulting `bilingualEnumerate`
            // message lands via the bridge's script-message handler
            // and routes back to `handleBilingualBlocks(_:)`.
            pendingHighlightJS = bilingualOrchestrator.enumerateJS()
        }
    }

    /// Handle a `.readerBilingualDidChange` notification — when the
    /// VM's prefetch lands, the cached translations for the current
    /// unit are ready; build inject JS and push it. The VM also
    /// posts on disable; we route that through `clearBilingualDecorations`.
    func handleBilingualDidChange() {
        guard let vm = bilingualViewModel else { return }
        if !vm.isEnabled {
            clearBilingualDecorations()
            return
        }
        guard let locator = viewModel.makeCurrentLocator() else { return }
        injectBilingualIfCached(for: locator)
    }

    /// Commit the setup-sheet's chosen language + granularity to the
    /// VM and dismiss the sheet. Drives the first-enable confirm
    /// path — subsequent flips do not re-raise the sheet
    /// (`hasBeenConfigured`).
    ///
    /// Codex Gate-4 round-2 finding [R2-2]: this is also where the
    /// first-enable's enumerate runs — `handleMoreBilingualToggle`
    /// defers it to confirm so the prefetch always uses the user's
    /// committed language, not the persisted default.
    func confirmBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.setTargetLanguage(bilingualSetupState.languageKey)
        vm.setGranularity(bilingualSetupState.granularity)
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        // Now that the user has committed the language/granularity,
        // run enumerate so the prefetch can land translations under
        // the chosen settings. Idempotent if the sheet was raised
        // for a different reason and enumerate had already run for
        // the current chapter (`updateBlocks` replaces — stale
        // blocks get replaced with the fresh stamp pass).
        pendingHighlightJS = bilingualOrchestrator.enumerateJS()
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
    /// Wraps the chapter-spine lazy-init, the More-menu toggle, the
    /// inject/clear pipeline, and the first-enable setup sheet
    /// into a single composition site — the container body adds
    /// `.modifier(bilingualSurfacesModifier)` rather than several
    /// inline modifiers, which would otherwise overflow SwiftUI's
    /// type-inference budget on this already-large body.
    var bilingualSurfacesModifier: some ViewModifier {
        EPUBBilingualSurfacesModifier(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            spineCount: viewModel.metadata?.spineCount,
            ensureViewModel: { ensureBilingualViewModel() },
            onMoreBilingualToggle: { handleMoreBilingualToggle() },
            onBilingualDidChange: { handleBilingualDidChange() },
            showSetupSheet: $showBilingualSetupSheet,
            sheetView: { AnyView(bilingualSetupSheetView) }
        )
    }

    /// The first-enable `BilingualSetupSheet` view, kept here so the
    /// container body stays under SwiftUI's type-inference budget.
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
                // WI-15 hook — for now, dismiss the sheet so the
                // user can navigate to Settings via the AA panel.
                cancelBilingualSetup()
            }
        )
    }
}

/// View modifier bundling EPUB bilingual reading hooks — the lazy
/// VM construction, the More-menu toggle, the `.readerBilingualDidChange`
/// observer, and the first-enable setup sheet. Encapsulates the
/// modifier graph so the container body stays under SwiftUI's
/// type-inference budget.
struct EPUBBilingualSurfacesModifier: ViewModifier {
    let bookFingerprintKey: String
    let spineCount: Int?
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    let onBilingualDidChange: () -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: spineCount) { _, _ in ensureViewModel() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerBilingualDidChange)
            ) { notification in
                let key = notification.userInfo?["fingerprintKey"] as? String
                guard key == bookFingerprintKey else { return }
                onBilingualDidChange()
            }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
