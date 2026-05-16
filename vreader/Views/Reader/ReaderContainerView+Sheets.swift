// Purpose: Sheets, deferred setup, and chrome overlay for ReaderContainerView.
// Pure code extraction — no logic changes.
//
// @coordinates-with: ReaderContainerView.swift, ReaderTopChrome.swift,
//   SearchView.swift, AIReaderPanel.swift, ReaderAICoordinator.swift,
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
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator,
                        object: locator
                    )
                    showSearch = false
                },
                onDismiss: {
                    showSearch = false
                }
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

    // MARK: - Custom Chrome Overlay (bug #62 v3, Feature #60 WI-6b)

    /// Feature #60 WI-6b: the shared top reader chrome. The four shed
    /// actions (Contents / Notes / Display / AI) now live in
    /// `ReaderBottomChrome`, composed per-format inside each container.
    /// `onMore` routes to the existing settings sheet as the interim
    /// wiring — WI-6c swaps it for the anchored More popover.
    var readerChromeOverlay: some View {
        ReaderTopChrome(
            theme: settingsStore.theme.asV2,
            title: book.title,
            bookmarked: false,
            moreActive: false,
            onBack: { dismiss() },
            onSearch: { showSearch = true },
            onBookmark: {
                NotificationCenter.default.post(name: .readerBookmarkRequested, object: nil)
            },
            onMore: { showSettings = true }
        )
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
                initialTab: aiInitialTab
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
