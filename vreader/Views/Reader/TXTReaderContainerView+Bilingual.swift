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
    /// | mode | `textContent` content | provider type |
    /// |---|---|---|
    /// | continuous (`isContinuousMode == true`) | full book | full-book slicer |
    /// | legacy small-file (`isChapterMode == false`) | full book | full-book slicer |
    /// | chapter-paged (`isChapterMode == true && isContinuousMode == false`) | current chapter only | loader-backed (WI-12b) |
    ///
    /// Chapter-paged mode was deliberately disabled for WI-12a; WI-12b
    /// introduces `TXTLoaderBackedChapterTextProvider` so the chapter-
    /// paged path uses `TXTChapterContentLoader` to read each chapter on
    /// demand, independent of what the VM holds in `textContent`.
    ///
    /// Codex Gate-4 round-1 finding [H2] + round-2 follow-up: the prior
    /// version guarded only on `textContent != nil`, but the TXT VM
    /// sets `textContent = chapterText` on chapter navigation in
    /// chapter-paged mode. Slicing document-global offsets out of that
    /// chapter-local string would corrupt every non-open chapter. The
    /// WI-12b fix routes chapter-paged mode through the loader.
    static func makeTextProvider(
        viewModel: TXTReaderViewModel
    ) -> (any ChapterTextProviding)? {
        guard let index = viewModel.chapterIndex,
              !index.chapters.isEmpty else { return nil }
        // Chapter-paged mode: use the loader-backed adapter — independent
        // of `textContent`'s chapter-local state.
        if viewModel.isChapterMode && !viewModel.isContinuousMode {
            guard let loader = viewModel.chapterContentLoader else { return nil }
            return TXTLoaderBackedChapterTextProvider(
                fingerprint: viewModel.bookFingerprint,
                chapters: index.chapters,
                loader: loader
            )
        }
        // Continuous + legacy paths: `textContent` IS the full book.
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
        // Feature #56 WI-14: publish the same text provider to the
        // parent ReaderContainerView so the Book Details sheet's
        // "Translate entire book…" row can consume it without bubbling
        // the per-format VM upwards.
        NotificationCenter.default.post(
            name: .readerBookTranslationTextProviderAvailable,
            object: textProvider,
            userInfo: ["fingerprintKey": viewModel.bookFingerprintKey])
        // Bug #245 / GH #1070: if persistence loaded `isEnabled == true`
        // (the user previously enabled bilingual for this book) AND the
        // setup sheet is NOT needed (it's a re-open, not a first-enable),
        // kick the initial `handlePositionChange` to warm the cache for
        // the open chapter. Without this, TXT's in-memory
        // `translationsByUnit` dict stays empty even when the disk cache
        // already has rows for the open chapter, and the renderer falls
        // back to source-only. Mirrors PDF's Gate-4 round-1 H1 fix.
        if vm.isEnabled && !vm.needsSetupSheet {
            Self.triggerBilingualPositionChange(
                viewModel: vm, locator: viewModel.makeLocator()
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
        } else {
            // Bug #245 / GH #1070: a subsequent enable on an already-
            // configured book must warm the prefetch immediately so the
            // open chapter's translations land. Mirrors the PDF path.
            Self.triggerBilingualPositionChange(
                viewModel: vm, locator: viewModel.makeLocator()
            )
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
        // Bug #245 / GH #1070: kick the initial prefetch for the open
        // chapter now that language + granularity are committed.
        Self.triggerBilingualPositionChange(
            viewModel: vm, locator: viewModel.makeLocator()
        )
    }

    /// Dismiss the setup sheet without persisting changes and turn
    /// bilingual mode back off — the user opted out of first-enable.
    func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    // MARK: - Position-change trigger (Bug #245 / GH #1070)

    /// Drive `vm.handlePositionChange(locator)` so the unit-aware
    /// prefetch trigger fires for the open chapter. The prefetcher
    /// looks up the disk cache via `ChapterTranslationService`, so a
    /// disk-cache hit populates `translationsByUnit` for the open unit
    /// (and the next one); the renderer then sees a non-empty
    /// `translations(for:)` and interleaves the translation runs into
    /// the source attrString.
    ///
    /// Without this trigger the in-memory dict stays empty even after
    /// the disk cache fills, and the chapter renders English-only
    /// regardless of how many `ZCHAPTERTRANSLATION` rows exist. EPUB /
    /// Foliate / PDF wire equivalent helpers (see the corresponding
    /// `+Bilingual` extensions); TXT was the missing path until this
    /// fix.
    ///
    /// Idempotent on nil inputs and on a disabled VM — the underlying
    /// `handlePositionChange` short-circuits when `isEnabled == false`
    /// or no prefetcher is attached.
    static func triggerBilingualPositionChange(
        viewModel: BilingualReadingViewModel?, locator: Locator?
    ) {
        guard let viewModel, let locator else { return }
        Task { await viewModel.handlePositionChange(locator) }
    }

    // MARK: - Offset routing helpers (Feature #56 WI-12b)

    /// Routes an `NSRange` of source UTF-16 offsets through the segment
    /// map. A nil input returns nil; an identity map returns the input
    /// unchanged (byte-identical pass-through).
    static func routeNSRange(_ source: NSRange?,
                             map: BilingualDisplaySegmentMap) -> NSRange? {
        guard let source else { return nil }
        return BilingualOffsetRouter.displayNSRange(forSourceNSRange: source, map: map)
    }

    /// Routes a list of persisted highlight ranges from source to display.
    static func routePersisted(_ source: [PaintedHighlight],
                               map: BilingualDisplaySegmentMap) -> [PaintedHighlight] {
        source.map { highlight in
            let routed = BilingualOffsetRouter.displayNSRange(
                forSourceNSRange: highlight.range, map: map
            )
            return PaintedHighlight(range: routed, colorName: highlight.colorName)
        }
    }

    /// Routes the UUID-keyed highlight lookup entries from source to display.
    static func routeLookup(_ lookup: [PersistedHighlightLookupEntry],
                            map: BilingualDisplaySegmentMap) -> [PersistedHighlightLookupEntry] {
        lookup.map { entry in
            let routed = BilingualOffsetRouter.displayNSRange(
                forSourceNSRange: entry.range, map: map
            )
            return PersistedHighlightLookupEntry(id: entry.id, range: routed)
        }
    }

    /// Builds the bridge delegate adapter when the segment map is
    /// non-identity (bilingual is on with a cached translation). For
    /// identity maps, returns nil so the container passes the VM as
    /// the delegate directly — preserves the byte-identical
    /// pass-through.
    static func makeBilingualDelegateIfNeeded(
        map: BilingualDisplaySegmentMap,
        wrapping vm: TXTReaderViewModel
    ) -> BilingualTXTBridgeDelegateAdapter? {
        guard map.sourceLength != map.displayLength else { return nil }
        return BilingualTXTBridgeDelegateAdapter(wrapping: vm, segmentMap: map)
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
            currentChapterIdxNonce: viewModel.currentChapterIdx,
            ensureViewModel: { ensureBilingualViewModel() },
            onMoreBilingualToggle: { handleMoreBilingualToggle() },
            onPositionChanged: {
                // Bug #245 / GH #1070: chapter navigation + scroll-driven
                // position broadcasts drive the bilingual prefetch trigger.
                // Without this wire the in-memory translationsByUnit dict
                // never populates, and the renderer falls back to source-
                // only even after the disk cache fills.
                Self.triggerBilingualPositionChange(
                    viewModel: bilingualViewModel,
                    locator: viewModel.makeLocator()
                )
            },
            onReTranslateApplied: { unit, segments in
                bilingualViewModel?.applyReTranslateResult(segments, for: unit)
            },
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
    /// Bug #245 / GH #1070: chapter-navigation nonce. Mirror of
    /// `PDFBilingualSurfacesModifier.currentPageIndexNonce` — fires
    /// `onPositionChanged` so the open chapter's bilingual prefetch
    /// kicks off as soon as the user navigates.
    let currentChapterIdxNonce: Int
    let ensureViewModel: () -> Void
    let onMoreBilingualToggle: () -> Void
    /// Bug #245 / GH #1070: drives `vm.handlePositionChange(locator)`
    /// when chapter navigation or `.readerPositionDidChange` fires.
    /// Without this, TXT's in-memory `translationsByUnit` dict never
    /// populates and the renderer falls back to source-only despite
    /// warm disk cache. Mirrors PDF's `onPositionChanged`.
    let onPositionChanged: () -> Void
    /// Feature #56 WI-15: routes a re-translate result to the format's
    /// bilingual VM so the open chapter re-renders without waiting for the
    /// next prefetch trigger.
    let onReTranslateApplied: (TranslationUnitID, [String]) -> Void
    @Binding var showSetupSheet: Bool
    let sheetView: () -> AnyView

    func body(content: Content) -> some View {
        content
            .onChange(of: chapterIndexNonce) { _, _ in ensureViewModel() }
            .onChange(of: textContentReady) { _, _ in ensureViewModel() }
            .onChange(of: currentChapterIdxNonce) { _, _ in onPositionChanged() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerMoreBilingual)
            ) { _ in onMoreBilingualToggle() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerPositionDidChange)
            ) { _ in onPositionChanged() }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerBilingualReTranslateApplied)
            ) { notification in
                guard let info = notification.userInfo,
                      info["fingerprintKey"] as? String == bookFingerprintKey,
                      let unit = info["unit"] as? TranslationUnitID,
                      let segments = info["segments"] as? [String]
                else { return }
                onReTranslateApplied(unit, segments)
            }
            .sheet(isPresented: $showSetupSheet) { sheetView() }
    }
}
#endif
