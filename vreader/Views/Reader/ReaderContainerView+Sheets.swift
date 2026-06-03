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

extension ReaderContainerView {

    // MARK: - TTS Integration (WI-B03)

    /// Starts or stops TTS read-aloud. If currently speaking, stops.
    /// Otherwise sources the book text and starts speaking.
    ///
    /// `@MainActor` (feature #57): explicit so the AZW3/MOBI branch's
    /// WKWebView touch (`extractPlainText()`, itself `@MainActor`) has
    /// a stated, checkable isolation contract rather than relying on
    /// SwiftUI `View` inference. Both call sites — the More-menu
    /// "Read aloud" row and the DEBUG `.debugBridgeTTSCommand`
    /// observer — are already main-actor contexts.
    @MainActor
    func startTTS() {
        ensureAIReady()
        let ai = resolvedAICoordinator
        if ttsService.state != .idle {
            ttsService.stop()
            return
        }

        // Use already-loaded text content if available (any format).
        if let text = ai.loadedTextContent, !text.isEmpty {
            speakLoadedText(ai: ai)
            return
        }

        switch TTSTextSource.source(for: resolvedBookFormat) {
        case .foliateExtraction:
            // Feature #57: AZW3/MOBI text comes from the Foliate
            // WKWebView, not loadBookTextContent (which has no azw3
            // case and returns nil).
            startAZW3TTS(ai: ai)
        case .fileLoad:
            // TXT/MD/PDF/EPUB: unchanged file-path load.
            Task {
                await ai.loadBookTextContent(
                    fileURL: resolvedFileURL,
                    format: book.format.lowercased()
                )
                if let text = ai.loadedTextContent, !text.isEmpty {
                    speakLoadedText(ai: ai)
                }
            }
        }
    }

    /// Feature #57: speak `ai.loadedTextContent` from the current
    /// position. Extracted so every text-ready path (cached, file-load,
    /// AZW3 extraction) starts speech through one helper. `@MainActor`
    /// inherited — called only from the `@MainActor` `startTTS()` /
    /// `startAZW3TTS`.
    @MainActor
    private func speakLoadedText(ai: ReaderAICoordinator) {
        guard let text = ai.loadedTextContent, !text.isEmpty else { return }
        let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
        withAnimation(.easeInOut(duration: 0.2)) {
            ttsService.startSpeaking(text: text, fromOffset: offset)
        }
    }

    /// Feature #57 (round-2 Finding 1): AZW3/MOBI TTS start with an
    /// explicit in-flight extraction gate. The whole-book
    /// `extractPlainText()` section walk takes noticeable time; a rapid
    /// second speaker tap before it finishes must NOT spawn a duplicate
    /// walk or a duplicate `startSpeaking`. The host holds the
    /// extraction `Task` in `@State azw3ExtractionTask`; a re-tap during
    /// the walk is a no-op. `@MainActor` inherited (called only from
    /// the `@MainActor` `startTTS()`).
    ///
    /// Three-layer idempotency: (1) re-tap while playing →
    /// `startTTS()`'s `ttsService.state != .idle` early-return;
    /// (2) re-tap during the first walk → the `azw3ExtractionTask`
    /// in-flight gate here; (3) re-tap after a completed extraction →
    /// the cached-`loadedTextContent` fast path in `startTTS()`.
    @MainActor
    private func startAZW3TTS(ai: ReaderAICoordinator) {
        let inFlight = azw3ExtractionTask != nil
        guard TTSTextSource.shouldStartExtraction(
            extractionInFlight: inFlight,
            cachedText: ai.loadedTextContent
        ) else {
            // Either a walk is already running (a rapid re-tap — the
            // running task will start speech) or usable text is already
            // cached. The cached case is handled by startTTS()'s
            // fast path before reaching here; this guard is the
            // in-flight no-op.
            return
        }

        // `extractPlainText()` carries its own 12 s timeout (WI-1
        // audit), so this Task always completes and the gate always
        // clears — no separate timeout wrapper is needed here.
        let task = Task { @MainActor () -> String? in
            await foliateCoordinatorBox.coordinator?.extractPlainText()
        }
        azw3ExtractionTask = task

        Task { @MainActor in
            let text = await task.value
            // Reader dismissed while the walk ran → `.onDisappear`
            // cancelled `task`; suppress late speech and skip clearing
            // the gate (which `.onDisappear` already nil'd).
            guard !task.isCancelled else { return }
            azw3ExtractionTask = nil
            // Re-check state after the await: the user may have stopped
            // TTS (debug-stop), or another path may have set
            // loadedTextContent, while the walk ran.
            guard ttsService.state == .idle else { return }
            guard ai.loadedTextContent == nil else { return }
            guard let text, !text.isEmpty else { return }
            ai.loadedTextContent = text
            // Feature #86 WI-1 (Gate-4 MED): this AZW3/Foliate TTS path also
            // populates loadedTextContent — funnel it through the chat-context
            // writer too, else "start TTS first, then open Chat" leaves bookContext
            // on the stale fallback until a later locator/TOC event.
            ai.refreshChatContext()
            speakLoadedText(ai: ai)
        }
    }

    // MARK: - Deferred Setup (bug #64)

    /// Lazily sets up AI coordinator and loads book text for AI context.
    func ensureAIReady() {
        let ai = resolvedAICoordinator
        ai.setupIfNeeded()
        guard ai.loadedTextContent == nil else { return }
        let format = book.format.lowercased()
        // Feature #57: AZW3/MOBI text is extracted from the Foliate
        // WKWebView on first speaker tap (startTTS()'s AZW3 branch),
        // not loaded from the file here — `loadBookTextContent` has no
        // azw3 case and would return nil. Skipping this avoids a dead
        // detached task that would otherwise run concurrently with
        // `extractPlainText()`. (AZW3/MOBI AI-context text is a
        // separate pre-existing gap — feature #57 §10, out of scope.)
        if TTSTextSource.source(for: resolvedBookFormat) == .foliateExtraction {
            return
        }
        Task {
            if format == "txt" || format == "md" {
                if let text = await contentCache.getText(for: resolvedFileURL, format: format) {
                    ai.loadedTextContent = text
                    // Feature #86 WI-1: chapter-scoped chat context via the funnel.
                    ai.refreshChatContext()
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

    /// Lazily builds TOC entries. Idempotent — early-returns when
    /// entries are already present. Feature #62: flips `tocDidLoad` once
    /// the build resolves so `TOCSheet` can tell "this book ships no
    /// TOC" apart from "the TOC is still loading".
    func ensureTOCReady() {
        guard tocEntries.isEmpty else {
            // TOC already built (e.g. by an earlier call) — the load is
            // logically complete; mark it so `TOCSheet` won't withhold
            // a genuine empty state.
            tocDidLoad = true
            return
        }
        guard let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else { return }
        Task {
            tocEntries = await ReaderTOCFactory.buildTOC(
                format: book.format.lowercased(),
                fileURL: resolvedFileURL,
                fingerprint: fingerprint
            )
            tocDidLoad = true
            // Feature #86 WI-1: sync the freshly-built TOC to the AI coordinator
            // + refresh, so a late TOC upgrades the chat context to chapter scope.
            resolvedAICoordinator.tocEntries = tocEntries
            resolvedAICoordinator.refreshChatContext()
        }
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
        BookDetailsSheet(
            book: book,
            theme: settingsStore.theme,
            coverPickCoordinator: coverPickCoordinator,
            onExportAnnotations: {
                // Reuse the existing export surface — the annotations
                // panel's Highlights tab carries the export action, the
                // same destination the More-menu's Export row uses.
                // Book Details + the panel share `ReaderContainerView`'s
                // presenter, so the panel is opened from Book Details'
                // `.sheet(onDismiss:)` once this sheet has dismissed —
                // not in the same update (which can drop the panel).
                exportAnnotationsAfterBookDetailsDismiss = true
                showBookDetails = false
            },
            // Feature #56 WI-14 — reader-side Book Details translate
            // entry point. The VM is owned by ReaderContainerView so the
            // confirm-alert / status-sheet handoff survives Book Details
            // dismiss. When the host hasn't yet received the per-format
            // text provider (`.readerBookTranslationTextProviderAvailable`),
            // the BookDetailsSheet's nil-VM guard hides the row entirely
            // rather than presenting a broken affordance.
            translateBookViewModel: translateBookVM,
            translateBookTextProvider: translateBookTextProvider,
            translateBookTargetLanguage: "Chinese"
        )
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
            // Feature #56 WI-10: thread the bilingual VM's `isEnabled` +
            // `targetLanguage` mirror through to the chrome so the
            // `BilingualPill` renders when bilingual is on for this
            // book. Mirror is updated by the `.readerBilingualDidChange`
            // observer attached on `ReaderContainerView` itself.
            bilingualActive: bilingualActive,
            bilingualLanguage: bilingualLanguage,
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
            // Gate the `Read aloud` row by the book format's `.tts`
            // capability — the row drops for formats without a wired
            // TTS path (PDF). AZW3/MOBI regained `.tts` in feature #57,
            // so they show the row. Same `BookFormat(...).capabilities`
            // lookup the reader settings panel uses (`ReaderContainerView`).
            formatCapabilities: BookFormat(rawValue: book.format.lowercased())?.capabilities,
            // Feature #56 WI-10: the bilingual row's 3-way presentation
            // and the conditional re-translate row both depend on the
            // open book's bilingual state. The mirror `bilingualActive`
            // + `bilingualLanguage` is the source — once we add
            // AI-provider availability gating (WI-15), this resolves
            // into `.unavailable` for unconfigured providers. Until
            // then it's `.on(...)` / `.off`. The language fallback
            // tracks `BilingualReadingViewModel.defaultTargetLanguage`
            // so a freshly-enabled book with no override still paints
            // the right target.
            bilingualState: bilingualActive
                ? .on(targetLanguage: bilingualLanguage
                      ?? BilingualReadingViewModel.defaultTargetLanguage)
                : .off,
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
    /// `.presentAnnotationsExport` opens `HighlightsSheet` on the
    /// Highlights filter, whose trailing slot carries the designed
    /// export action — there is no separate export-picker sheet.
    func handleMoreMenuAction(_ row: ReaderMoreMenuRow) {
        let effect = ReaderMoreMenuEffect(row: row)
        switch effect {
        case .toggleReadAloud:
            startTTS()
        case .toggleAutoPageTurn:
            // The design draws an inline toggle; flipping
            // `autoPageTurn` is live-applied by the paged TXT/MD
            // containers' `onChange` observers.
            settingsStore.autoPageTurn.toggle()
        case .toggleBilingual:
            // Feature #56 WI-8: the popover posts
            // `.readerMoreBilingual`; the actual
            // `BilingualReadingViewModel.setEnabled(...)` wiring lives
            // in the per-format containers (WI-10..13). The
            // `.unavailable` state's routing to AI Settings also lives
            // there — the host VM is the source of truth for AI
            // availability. This switch is intentionally a no-op so
            // the popover dismisses cleanly while the row's
            // notification reaches the per-format observer.
            break
        case .presentReTranslatePicker:
            // Feature #56 WI-8: the popover posts
            // `.readerMoreReTranslateChapter`; the `ReTranslatePickerSheet`
            // presentation lives in the per-format containers
            // (WI-15). This switch is a no-op for the same reason as
            // `.toggleBilingual`.
            break
        case .presentBookDetails:
            showBookDetails = true
        case .presentShareSheet:
            showShareSheet = true
        case .presentAnnotationsExport:
            // Feature #62: route to `HighlightsSheet` (Highlights
            // filter) via the pure routing helper.
            annotationsRoute = AnnotationsSheetRoute.route(forMoreMenuEffect: effect)
        }
    }

    // MARK: - Annotations sheet (feature #62)

    /// Builds the annotations sheet for a route — `TOCSheet` for a
    /// `.toc` route, `HighlightsSheet` for a `.highlights` route. Held
    /// here so `ReaderContainerView`'s `.sheet(item:)` closure stays
    /// trivial (the `searchSheet` / `bookDetailsSheet` pattern).
    @ViewBuilder
    func annotationsSheet(for route: AnnotationsSheetRoute) -> some View {
        switch route {
        case .toc(let initialTab):
            TOCSheet(
                bookTitle: book.title,
                bookFingerprintKey: book.fingerprintKey,
                modelContainer: modelContext.container,
                tocEntries: tocEntries,
                tocDidLoad: tocDidLoad,
                currentLocator: currentLocator,
                theme: settingsStore.theme,
                initialTab: initialTab,
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator, object: locator
                    )
                },
                onOpenSearch: {
                    // Defer the search sheet to `annotationsRoute`'s
                    // `.sheet(onDismiss:)` — TOCSheet must fully dismiss
                    // first (sibling-sheet hand-off).
                    openSearchAfterAnnotationsDismiss = true
                },
                onDismiss: { annotationsRoute = nil }
            )
        case .highlights(let initialFilter):
            HighlightsSheet(
                bookFingerprintKey: book.fingerprintKey,
                modelContainer: modelContext.container,
                tocEntries: tocEntries,
                theme: settingsStore.theme,
                initialFilter: initialFilter,
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator, object: locator
                    )
                },
                onDismiss: { annotationsRoute = nil }
            )
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
            // Resolve the reading locator once — used both for the panel
            // and for the feature-#69 Chapter-scope bounds. The AI sheet
            // is modal, so this snapshot cannot go stale while it's open.
            let resolvedLocator = ai.currentLocator ?? Locator(
                bookFingerprint: fingerprint,
                href: nil, progression: nil, totalProgression: nil, cfi: nil,
                page: nil, charOffsetUTF16: nil,
                charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                textQuote: nil, textContextBefore: nil, textContextAfter: nil
            )
            // Feature #69: the FULL flattened book text (un-extracted).
            // Empty when text loading has not finished — the extractor
            // returns "" and the view model maps that to a context error.
            let fullText = ai.loadedTextContent ?? ""
            // Feature #69: the chapter span for the Chapter scope,
            // resolved from the reader's existing TOC entries. A nil
            // result (empty / non-char-offset-anchored TOC, e.g. EPUB)
            // degrades Chapter to Section inside the extractor.
            let chapterBounds = SummaryScopeResolver.chapterBounds(
                for: resolvedLocator,
                tocEntries: tocEntries,
                totalTextLengthUTF16: fullText.utf16.count
            )
            AIReaderPanel(
                viewModel: aiVM,
                translationViewModel: transVM,
                chatViewModel: chatVM,
                locator: resolvedLocator,
                textContent: ai.currentTextContent,
                fullTextContent: fullText,
                chapterBounds: chapterBounds,
                format: resolvedBookFormat,
                onDismiss: { showAIPanel = false },
                theme: settingsStore.theme,
                initialTab: aiInitialTab
            )
            .modifier(aiPanelDetentsModifier)
            .presentationDragIndicator(.visible)
        }
    }

    /// Bug #256 — the AI sheet's detent modifier. In Release this is the
    /// unchanged `presentationDetents([.medium, .large])` (no programmatic
    /// selection — the DebugBridge harness is compiled out). In DEBUG it binds
    /// a `selection` so the `present?sheet=ai&detent=large` command can drive
    /// the active detent CU-free (SwiftUI cannot programmatically change a
    /// detent without the `presentationDetents(_:selection:)` overload). The
    /// presented set (`[.medium, .large]`) and default (`.medium`) are
    /// identical across both configurations, so the user-facing presentation
    /// is unchanged. The `#if DEBUG` lives here — not inside an argument list —
    /// because a preprocessor conditional cannot appear mid-call-argument.
    private var aiPanelDetentsModifier: AIReaderPanelDetents {
        #if DEBUG
        AIReaderPanelDetents(selection: $aiPanelDetent)
        #else
        AIReaderPanelDetents()
        #endif
    }
}

/// Bug #256 — the AI sheet's detent set (see `aiPanelDetentsModifier`).
private struct AIReaderPanelDetents: ViewModifier {
    #if DEBUG
    @Binding var selection: PresentationDetent
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        content.presentationDetents([.medium, .large], selection: $selection)
        #else
        content.presentationDetents([.medium, .large])
        #endif
    }
}
