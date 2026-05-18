// Purpose: Sheets, deferred setup, and chrome overlay for ReaderContainerView.
// Also hosts the Feature #60 WI-6c More-menu popover composition
// (`readerMorePopoverOverlay`) and its row-action router
// (`handleMoreMenuAction`).
//
// @coordinates-with: ReaderContainerView.swift, ReaderTopChrome.swift,
//   ReaderMorePopover.swift, ShareSheet.swift, SearchView.swift,
//   AIReaderPanel.swift, ReaderAICoordinator.swift,
//   ReaderSearchCoordinator.swift, BookContentCache.swift

import SwiftUI
import SwiftData

extension ReaderContainerView {

    // MARK: - TTS Integration (WI-B03)

    /// Starts or stops TTS read-aloud. If currently speaking, stops.
    /// Otherwise, loads text from the book file and starts speaking.
    func startTTS() {
        ensureAIReady()
        let ai = resolvedAICoordinator
        if ttsService.state != .idle {
            ttsService.stop()
            return
        }

        // Use already-loaded text content if available
        if let text = ai.loadedTextContent, !text.isEmpty {
            let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
            withAnimation(.easeInOut(duration: 0.2)) {
                ttsService.startSpeaking(text: text, fromOffset: offset)
            }
        } else {
            // Trigger text loading and start TTS when ready
            Task {
                await ai.loadBookTextContent(
                    fileURL: resolvedFileURL,
                    format: book.format.lowercased()
                )
                if let text = ai.loadedTextContent, !text.isEmpty {
                    let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ttsService.startSpeaking(text: text, fromOffset: offset)
                    }
                }
            }
        }
    }

    // MARK: - Deferred Setup (bug #64)

    /// Lazily sets up AI coordinator and loads book text for AI context.
    func ensureAIReady() {
        let ai = resolvedAICoordinator
        ai.setupIfNeeded()
        guard ai.loadedTextContent == nil else { return }
        Task {
            let format = book.format.lowercased()
            if format == "txt" || format == "md" {
                if let text = await contentCache.getText(for: resolvedFileURL, format: format) {
                    ai.loadedTextContent = text
                    ai.chatViewModel?.bookContext = ai.currentTextContent
                } else {
                    await ai.loadBookTextContent(fileURL: resolvedFileURL, format: format)
                }
            } else {
                await ai.loadBookTextContent(fileURL: resolvedFileURL, format: format)
            }
        }
    }

    /// Triggers full search setup (indexing) when search sheet opens.
    /// prepareService() may have already created the service; setup() handles that.
    func ensureSearchReady() {
        guard let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else { return }
        Task {
            await searchCoordinator.setup(
                fingerprint: fingerprint,
                fileURL: resolvedFileURL,
                format: book.format.lowercased()
            )
        }
    }

    /// Lazily builds TOC entries.
    func ensureTOCReady() {
        guard tocEntries.isEmpty,
              let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else { return }
        Task {
            tocEntries = await ReaderTOCFactory.buildTOC(
                format: book.format.lowercased(),
                fileURL: resolvedFileURL,
                fingerprint: fingerprint
            )
        }
    }

    /// Loads replacement rules for the unified coordinator.
    func loadReplacementRules() async {
        let bookKey = book.fingerprintKey
        let container = modelContext.container
        let rules: [ReplacementRuleDescriptor] = await Task.detached {
            let ctx = ModelContext(container)
            let descriptor = FetchDescriptor<ContentReplacementRule>(
                sortBy: [SortDescriptor(\.order)]
            )
            let allRules = (try? ctx.fetch(descriptor)) ?? []
            return allRules
                .filter { $0.enabled && ($0.scopeKey.isEmpty || $0.scopeKey == bookKey) }
                .map { ReplacementRuleDescriptor(
                    pattern: $0.pattern,
                    replacement: $0.replacement,
                    isRegex: $0.isRegex,
                    enabled: $0.enabled,
                    order: $0.order
                ) }
        }.value

        var transforms: [any TextTransform] = []
        if !rules.isEmpty {
            transforms.append(ReplacementTransform(rules: rules))
        }
        if settingsStore.chineseConversion != .none {
            transforms.append(SimpTradTransform(direction: settingsStore.chineseConversion))
        }
        unifiedCoordinator.activeTransforms = transforms
    }

    // MARK: - Sheets & Placeholders

    /// Search sheet — uses SearchView when search pipeline is ready.
    @ViewBuilder
    var searchSheet: some View {
        if let searchViewModel = searchCoordinator.searchViewModel {
            SearchView(
                viewModel: searchViewModel,
                theme: settingsStore.theme,
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator,
                        object: locator
                    )
                    showSearch = false
                },
                onDismiss: {
                    showSearch = false
                },
                bookTitle: book.title
            )
            .accessibilityIdentifier("searchSheet")
        } else {
            NavigationStack {
                ProgressView("Preparing search\u{2026}")
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showSearch = false
                            }
                        }
                    }
            }
            .accessibilityIdentifier("searchSheet")
        }
    }

    /// Feature #61 WI-3: the reader Book Details sheet content,
    /// presented by `ReaderContainerView`'s
    /// `.sheet(isPresented: $showBookDetails)`. Held here so the host
    /// body's `.sheet` closure stays trivial — the same pattern as
    /// `searchSheet` / `aiSheet`. The sheet dismisses via swipe-down
    /// (its title bar carries a Share button, not a close button —
    /// design `vreader-book-details.jsx`).
    var bookDetailsSheet: some View {
        BookDetailsSheet(book: book, theme: settingsStore.theme)
    }

    // MARK: - Custom Chrome Overlay (bug #62 v3, Feature #60 WI-6b/WI-6c)

    /// Feature #60 WI-6b: the shared top reader chrome. The four shed
    /// actions (Contents / Notes / Display / AI) now live in
    /// `ReaderBottomChrome`, composed per-format inside each container.
    /// WI-6c: `onMore` toggles the anchored `ReaderMorePopover` (the
    /// WI-6b interim `⋯` → settings routing is removed); `moreActive`
    /// draws the design's backdrop tint while the popover is open.
    var readerChromeOverlay: some View {
        ReaderTopChrome(
            theme: settingsStore.theme,
            title: book.title,
            bookmarked: false,
            moreActive: showMorePopover,
            onBack: { dismiss() },
            onSearch: { showSearch = true },
            onBookmark: {
                NotificationCenter.default.post(name: .readerBookmarkRequested, object: nil)
            },
            onMore: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showMorePopover.toggle()
                }
            }
        )
    }

    // MARK: - More-menu Popover (Feature #60 WI-6c)

    /// The anchored More-menu popover, floating above the chrome.
    /// Presented while `showMorePopover` is set; the host's
    /// `.readerMoreMenuActionObservers` modifier handles row taps.
    var readerMorePopoverOverlay: some View {
        ReaderMorePopover(
            theme: settingsStore.theme,
            ttsPlaying: ttsService.state != .idle,
            autoTurnOn: settingsStore.autoPageTurn,
            autoTurnInterval: settingsStore.autoPageTurnInterval,
            // Bug #176 / GH #602: gate the `Read aloud` row by the
            // book format's capabilities — AZW3 / MOBI exclude `.tts`,
            // so the row is dropped rather than surfacing a no-op.
            // Same `BookFormat(...).capabilities` lookup the reader
            // settings panel uses (`ReaderContainerView`).
            formatCapabilities: BookFormat(rawValue: book.format.lowercased())?.capabilities,
            // The design anchors the popover just below the top chrome.
            // Chrome height = the Dynamic-Island inset + the ~52pt
            // button row; add a small gap so the notch tucks under the
            // `⋯` button. The prototype's fixed `top: 92` is the
            // equivalent for its fixed-height chrome.
            topInset: ReaderSafeAreaResolver.windowSafeAreaTop + 56,
            onClose: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showMorePopover = false
                }
            }
        )
    }

    /// Routes a tapped More-menu row to the matching reader action.
    /// The popover already posted `row.notification` and dismissed
    /// itself; this is the host-side effect.
    ///
    /// The row → effect decision is `ReaderMoreMenuEffect`, a pure type
    /// pinned by `BookDetailsRouteTests`; this method applies the
    /// `@State` mutation each effect maps to. Feature #61 WI-3 routes
    /// `.bookDetails` to the dedicated Book Details sheet (the
    /// feature-#60 WI-6c interim opened the reader settings panel).
    ///
    /// `.presentAnnotationsExport` opens the annotations panel on the
    /// Highlights tab, which carries the existing export action — there
    /// is no separate export-picker sheet.
    func handleMoreMenuAction(_ row: ReaderMoreMenuRow) {
        switch ReaderMoreMenuEffect(row: row) {
        case .toggleReadAloud:
            startTTS()
        case .toggleAutoPageTurn:
            // The design draws an inline toggle; flipping
            // `autoPageTurn` is live-applied by the paged TXT/MD
            // containers' `onChange` observers.
            settingsStore.autoPageTurn.toggle()
        case .presentBookDetails:
            showBookDetails = true
        case .presentShareSheet:
            showShareSheet = true
        case .presentAnnotationsExport:
            annotationsPanelInitialTab = .highlights
            showAnnotationsPanel = true
        }
    }

    // MARK: - AI Sheet

    @ViewBuilder
    var aiSheet: some View {
        let ai = resolvedAICoordinator
        if let aiVM = ai.aiViewModel,
           let transVM = ai.translationViewModel,
           let chatVM = ai.chatViewModel,
           let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
            AIReaderPanel(
                viewModel: aiVM,
                translationViewModel: transVM,
                chatViewModel: chatVM,
                locator: ai.currentLocator ?? Locator(
                    bookFingerprint: fingerprint,
                    href: nil, progression: nil, totalProgression: nil, cfi: nil,
                    page: nil, charOffsetUTF16: nil,
                    charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                    textQuote: nil, textContextBefore: nil, textContextAfter: nil
                ),
                textContent: ai.currentTextContent,
                format: resolvedBookFormat,
                onDismiss: { showAIPanel = false },
                theme: settingsStore.theme,
                initialTab: aiInitialTab
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
