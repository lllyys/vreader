// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat and ReadingMode.
// - When readingMode == .unified: TXT/MD use UnifiedTextRenderer (WI-B04); EPUB shows placeholder.
// - PDF always falls through to native (no .unifiedReflow capability).
// - File URL resolved from fingerprintKey using the sandbox import convention.
// - DocumentFingerprint parsed from the canonical key string.
// - Format host views (TXTReaderHost, etc.) extracted to ReaderFormatHosts.swift (WI-004).
// - AnnotationsPanelView extracted to AnnotationsPanelView.swift (WI-004).
// - Custom chrome overlay (ReaderChromeBar) replaces system nav bar for stable content layout.
// - TOC entries computed per format: EPUB from spine items, PDF from outline tree, TXT from Legado rules.
// - Search sheet wired with SearchService, SearchViewModel, and SearchView.
// - Book content is indexed for search on first open using format-specific extractors.
// - AI button conditionally shown when feature flag is ON and API key exists (WI-010).
// - AIReaderPanel presented as sheet for summarization, translation, and chat (WI-010, WI-012).
// - AITranslationViewModel created alongside AIAssistantViewModel for bilingual translation.
// - AIChatViewModel created with book fingerprint and book content context.
// - Book text loaded for AI; AIContextExtractor extracts ~2500 chars around current position.
// - EPUB text extracted via EPUBParser + EPUBTextExtractor.stripHTML (not raw ZIP read).
// - AI panel locator uses live reader position via .readerPositionDidChange notification.
//
// - ThemeBackgroundView shown behind reader content when useCustomBackground is ON.
//
// @coordinates-with: ReaderChromeBar.swift, ReaderFormatHosts.swift,
//   AnnotationsPanelView.swift, ReaderSettingsStore.swift, ReaderSettingsPanel.swift,
//   DocumentFingerprint.swift, SearchView.swift, ThemeBackgroundView.swift,
//   ReaderAICoordinator.swift, ReaderSearchCoordinator.swift,
//   ReaderUnifiedCoordinator.swift, ReaderTOCBuilder.swift

import SwiftUI
import SwiftData
import os

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {

    let book: LibraryBookItem

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @State var settingsStore = ReaderSettingsStore()
    @State var tapZoneStore = TapZoneStore()
    @State var showSettings = false
    @State var showAnnotationsPanel = false
    @State var showSearch = false
    @State var showAIPanel = false
    @State var aiInitialTab: AIReaderTab = .summarize
    @State private var showDictionary = false
    @State private var dictionaryWord: String = ""
    /// Controls whether the navigation bar chrome is visible. Tap content to toggle.
    @State private var isChromeVisible = true
    /// Computed TOC entries for the current book (format-specific).
    @State var tocEntries: [TOCEntry] = []
    /// TTS service for read-aloud feature (WI-B03).
    @State var ttsService = TTSService()
    /// Reading progress for the unified renderer (WI-B04).
    @State var unifiedReadingProgress: Double = 0
    /// Current reading position for TOC scroll-to-current.
    @State var currentLocator: Locator?

    // MARK: - Coordinators

    @State var aiCoordinator: ReaderAICoordinator?
    @State var searchCoordinator = ReaderSearchCoordinator()
    @State var unifiedCoordinator = ReaderUnifiedCoordinator()

    /// Shared content cache — loads book text once, shared across AI/search/TTS.
    @State var contentCache = BookContentCache()
    /// Shared pagination cache for the unified renderer (B13).
    @State var paginationCache = PaginationCache()

    #if DEBUG
    /// DebugBridge probe (feature #44). Registers on appear, unregisters on
    /// disappear. Holds a closure that the registry queries for the current
    /// position; v1 will wire per-format settle/eval hooks here.
    @State private var debugProbe: DebugReaderProbeAdapter?
    #endif

    var body: some View {
        ZStack {
            if settingsStore.useCustomBackground {
                ThemeBackgroundView(settingsStore: settingsStore)
            }

            Group {
                if let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
                    // TODO: Phase B12 — EPUB classifier will set isComplexEPUB at runtime.
                    // Currently BookFormat.capabilities always returns simple EPUB capabilities,
                    // so complex EPUBs get .unifiedReflow when they shouldn't.
                    // TXT/MD use UnifiedTextRenderer (WI-B04); EPUB unified shows placeholder.
                    if settingsStore.readingMode == .unified
                        && resolvedBookFormat.capabilities.contains(.unifiedReflow) {
                        unifiedReaderView(fingerprint: fingerprint)
                    } else {
                        // Native mode: tap handling lives in each UIKit bridge
                        // (UITapGestureRecognizer with shouldRecognizeSimultaneously).
                        // Do NOT add a SwiftUI overlay — it blocks scroll gestures. (bug #70)
                        nativeReaderView(fingerprint: fingerprint)
                    }
                } else {
                    fingerprintErrorView
                }
            }

            // Custom chrome overlay — floats on top of content, never changes layout. (bug #62 v3)
            if isChromeVisible {
                readerChromeOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // TTS control bar at the bottom (WI-B03)
            if ttsService.state != .idle {
                VStack {
                    Spacer()
                    TTSControlBar(
                        ttsService: ttsService,
                        settingsStore: settingsStore
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            toggleChrome()
        }
        // Page turn from tap zones — handled by unified renderer directly.
        // Native mode bridges handle taps internally (center=chrome toggle).
        // Left/right zones only functional in unified paged mode. (bug #81)
        .accessibilityAction(named: isChromeVisible ? "Hide toolbar" : "Show toolbar") {
            toggleChrome()
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!isChromeVisible)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showAIPanel, onDismiss: { aiInitialTab = .summarize }) { aiSheet }
        .onReceive(NotificationCenter.default.publisher(for: .readerDefineRequested)) { notification in
            guard let info = notification.object as? TextSelectionInfo else { return }
            if let word = DictionaryLookup.extractWord(from: info.selectedText) {
                dictionaryWord = word
                showDictionary = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerTranslateRequested)) { notification in
            guard let info = notification.object as? TextSelectionInfo else { return }
            // Bug #90: even if a stale UI path or out-of-tree caller posts the
            // notification, refuse to open the panel when AI consent isn't
            // granted. The toolbar button + edit-menu translate action both
            // gate on AIReaderAvailability.isAvailable already; this is the
            // defense-in-depth layer at the sheet-presentation seam.
            guard resolvedAICoordinator.isAIAvailable else { return }
            ensureAIReady()
            if let transVM = resolvedAICoordinator.translationViewModel {
                transVM.originalText = info.selectedText
            }
            aiInitialTab = .translate // bug #95
            showAIPanel = true
        }
        .sheet(isPresented: $showDictionary) {
            DictionarySheet(word: dictionaryWord)
        }
        // AI setup + text loading deferred until AI/TTS is invoked (bug #64)
        .onChange(of: showAIPanel) { _, isShowing in
            if isShowing { ensureAIReady() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPositionDidChange)) { notification in
            guard let locator = notification.object as? Locator else { return }
            currentLocator = locator
            resolvedAICoordinator.currentLocator = locator
            if resolvedAICoordinator.loadedTextContent != nil {
                resolvedAICoordinator.chatViewModel?.bookContext = resolvedAICoordinator.currentTextContent
            }
        }
        // PERF: Single deferred .task for all non-critical setup.
        // Per-book settings, search prep, and replacement rules all deferred
        // to avoid contending with the format host's file-open .task.
        .task {
            // Per-book settings (bug #84) — fast file read, do first
            let perBook = PerBookSettingsStore.settings(
                for: book.fingerprintKey,
                baseURL: Self.perBookSettingsBaseURL
            )
            if perBook != nil {
                let resolved = PerBookSettingsStore.resolve(
                    perBook: perBook, global: settingsStore
                )
                settingsStore.applyResolvedSettings(resolved)
            }
            // Build TOC eagerly for TXT — needed for chapter progress bar in legacy mode (bug #31)
            if resolvedBookFormat == .txt {
                ensureTOCReady()
            }
            // Replacement rules (unified mode only)
            if settingsStore.readingMode == .unified {
                await loadReplacementRules()
            }
        }
        .onChange(of: settingsStore.chineseConversion) { _, newDirection in
            var transforms = unifiedCoordinator.activeTransforms.filter { !($0 is SimpTradTransform) }
            if newDirection != .none {
                transforms.append(SimpTradTransform(direction: newDirection))
            }
            unifiedCoordinator.activeTransforms = transforms
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(
                store: settingsStore,
                tapZoneStore: tapZoneStore,
                bookFingerprintKey: book.fingerprintKey,
                perBookBaseURL: Self.perBookSettingsBaseURL,
                formatCapabilities: BookFormat(rawValue: book.format.lowercased())?.capabilities
            )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAnnotationsPanel) {
            AnnotationsPanelView(
                bookFingerprintKey: book.fingerprintKey,
                modelContainer: modelContext.container,
                tocEntries: tocEntries,
                currentLocator: currentLocator,
                onNavigate: { locator in
                    NotificationCenter.default.post(
                        name: .readerNavigateToLocator,
                        object: locator
                    )
                },
                onDismiss: {
                    showAnnotationsPanel = false
                }
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearch) {
            searchSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Search setup deferred until search sheet opens (bug #64)
        .onChange(of: showSearch) { _, isShowing in
            if isShowing { ensureSearchReady() }
        }
        // TOC deferred until annotations panel opens (bug #64)
        .onChange(of: showAnnotationsPanel) { _, isShowing in
            if isShowing { ensureTOCReady() }
        }
        #if DEBUG
        .onAppear {
            let probe = DebugReaderProbeAdapter(
                fingerprintKey: book.fingerprintKey,
                format: book.format
                // positionProvider intentionally defaults to nil-returning
                // — wiring currentLocator → string lands when DebugSnapshot
                // reads from the registry (next WI). Returning a stand-in
                // value here would mislead consumers into treating it as
                // a real position.
            )
            debugProbe = probe
            DebugReaderRegistry.shared.register(probe)
        }
        .onDisappear {
            if let probe = debugProbe {
                DebugReaderRegistry.shared.unregister(probe)
                debugProbe = nil
            }
        }
        #endif
    }

    // MARK: - Resolved Helpers

    /// The resolved book format enum value.
    var resolvedBookFormat: BookFormat {
        BookFormat(rawValue: book.format.lowercased()) ?? .txt
    }

    /// Lazily creates the AI coordinator on first access.
    var resolvedAICoordinator: ReaderAICoordinator {
        if let existing = aiCoordinator { return existing }
        let coordinator = ReaderAICoordinator(
            fallbackTitle: book.title,
            bookFormat: resolvedBookFormat,
            fingerprintKey: book.fingerprintKey
        )
        // SwiftUI will apply the mutation at the end of the render pass
        DispatchQueue.main.async {
            aiCoordinator = coordinator
        }
        return coordinator
    }

    // MARK: - Chrome Toggle (bug #62 v3)

    /// Toggles chrome overlay visibility. Content is pixel-stable because we use
    /// a custom overlay (ReaderChromeBar) instead of the system nav bar.
    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible.toggle()
        }
    }

    // MARK: - File URL Resolution

    /// Resolves the sandbox file URL using the same convention as BookImporter.
    var resolvedFileURL: URL {
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        let safeName = book.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let bookFormat = BookFormat(rawValue: book.format.lowercased())
        let ext = bookFormat?.fileExtensions.first ?? book.format.lowercased()
        return booksDir
            .appendingPathComponent(safeName)
            .appendingPathExtension(ext)
    }

    // MARK: - Per-Book Settings Base URL (A05)

    /// Directory where per-book settings JSON files are stored.
    static let perBookSettingsBaseURL: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerBookSettings", isDirectory: true)
    }()

    // MARK: - Device ID

    /// Stable device identifier for reading position and session tracking.
    static let deviceId: String = {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }()

    /// Dispatches to the format-specific native reader.
    @ViewBuilder
    func nativeReaderView(fingerprint: DocumentFingerprint) -> some View {
        switch book.format.lowercased() {
        case "epub":
            EPUBReaderHost(
                fileURL: resolvedFileURL,
                fingerprint: fingerprint,
                modelContainer: modelContext.container,
                settingsStore: settingsStore,
                ttsService: ttsService
            )
        case "pdf":
            PDFReaderHost(
                fileURL: resolvedFileURL,
                fingerprint: fingerprint,
                modelContainer: modelContext.container,
                ttsService: ttsService
            )
        case "txt":
            TXTReaderHost(
                fileURL: resolvedFileURL,
                fingerprint: fingerprint,
                modelContainer: modelContext.container,
                settingsStore: settingsStore,
                ttsService: ttsService,
                tocEntries: tocEntries
            )
        case "md":
            MDReaderHost(
                fileURL: resolvedFileURL,
                fingerprint: fingerprint,
                modelContainer: modelContext.container,
                settingsStore: settingsStore,
                ttsService: ttsService
            )
        case "azw3":
            FoliateSpikeView(bookURL: resolvedFileURL)
        default:
            unsupportedFormatView(format: book.format.uppercased())
        }
    }
}


