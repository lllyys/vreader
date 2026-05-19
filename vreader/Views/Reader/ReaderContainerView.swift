// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to a format-specific reader host by `ReaderEngine.resolve(format:)`
//   — an internal per-format engine selector (feature #54). There is no
//   user-visible reading-mode toggle.
// - File URL resolved from fingerprintKey using the sandbox import convention.
// - DocumentFingerprint parsed from the canonical key string.
// - Format host views (TXTReaderHost, etc.) extracted to ReaderFormatHosts.swift (WI-004).
// - AnnotationsPanelView extracted to AnnotationsPanelView.swift (WI-004).
// - Custom chrome overlay (ReaderTopChrome) replaces system nav bar for stable content layout.
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
// @coordinates-with: ReaderTopChrome.swift, ReaderBottomChrome.swift, ReaderFormatHosts.swift,
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
    @State var showSettings = false
    /// Feature #61 WI-3: whether the reader Book Details sheet is
    /// presented — driven by the More-menu's "Book details" row,
    /// replacing the feature-#60 WI-6c settings-panel interim.
    /// `internal` (not `private`) because the More-menu router and the
    /// `bookDetailsSheet` content both live in the `+Sheets.swift`
    /// extension — same reason as the sibling `showSettings` /
    /// `showShareSheet` flags.
    @State var showBookDetails = false
    /// Feature #61 WI-4: set by the Book Details "Export annotations…"
    /// row. The annotations panel and Book Details are sibling sheets
    /// on this view, so the panel is opened from Book Details'
    /// `.sheet(onDismiss:)` once it has fully dismissed — presenting
    /// both in one state update can drop the second sheet.
    @State var exportAnnotationsAfterBookDetailsDismiss = false
    @State var showAnnotationsPanel = false
    /// Feature #60 WI-6b: which tab the annotations panel opens on —
    /// the bottom chrome's Contents button opens `.toc`, Notes opens
    /// `.highlights`.
    @State var annotationsPanelInitialTab: AnnotationsPanelTab = .toc
    @State var showSearch = false
    /// Feature #60 WI-6c: whether the reader More-menu popover is
    /// presented. The `⋯` button in `ReaderTopChrome` toggles it; the
    /// popover floats in the chrome overlay anchored to that button.
    @State var showMorePopover = false
    /// Feature #60 WI-6c: whether the system share sheet for the book
    /// file is presented — driven by the More-menu's "Share book" row.
    @State var showShareSheet = false
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
    /// Current reading position for TOC scroll-to-current.
    @State var currentLocator: Locator?

    // MARK: - Coordinators

    @State var aiCoordinator: ReaderAICoordinator?
    @State var searchCoordinator = ReaderSearchCoordinator()
    /// Feature #61 WI-4: drives the Book Details sheet's cover-replace
    /// PhotosPicker flow. Owned here (not inside `BookDetailsSheet`) so
    /// the pick survives the sheet's dismiss / re-present and its
    /// `coverVersion` bump re-renders the cover.
    @State var coverPickCoordinator = CoverPickCoordinator()

    /// Shared content cache — loads book text once, shared across AI/search/TTS.
    @State var contentCache = BookContentCache()

    /// Bug #142: per-reader instance token. Generated once per
    /// ReaderContainerView mount and threaded into both EPUB and Foliate
    /// bridges so the DebugBridge registry can disambiguate same-book
    /// reopens (a late didFinish from an outgoing webview cannot match
    /// the new reader's token even if the fingerprintKey matches).
    /// Used by the DEBUG-only registry API; the field itself is plain
    /// state with no Release-build cost beyond a UUID.
    @State private var readerToken: UUID = UUID()

    /// Feature #57: handle to the live `FoliateSpikeView.Coordinator`
    /// for AZW3/MOBI books, populated by the spike's `makeCoordinator()`.
    /// The TTS path (`startTTS()`) calls the Coordinator's
    /// `extractPlainText()` through this box once the book has rendered.
    /// Holds the Coordinator `weak`, so this `@State` does not leak the
    /// reader.
    @State private var foliateCoordinatorBox = FoliateCoordinatorBox()

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
                    // Route by ReaderEngine (feature #54). Tap handling lives
                    // in each UIKit bridge (UITapGestureRecognizer with
                    // shouldRecognizeSimultaneously). Do NOT add a SwiftUI
                    // overlay — it blocks scroll gestures. (bug #70)
                    engineReaderView(fingerprint: fingerprint)
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

            // Feature #60 WI-6c: the reader More-menu popover, anchored
            // to the `⋯` button in the top chrome. Floats above all
            // content + chrome; only present while the chrome is too,
            // so hiding the chrome dismisses it.
            if showMorePopover && isChromeVisible {
                readerMorePopoverOverlay
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            // A content tap toggles the chrome. If the More popover is
            // open, the tap should dismiss it rather than (also)
            // flipping the chrome out from under it.
            if showMorePopover {
                showMorePopover = false
            } else {
                toggleChrome()
            }
        }
        // Feature #60 WI-6b: the shared `ReaderBottomChrome` toolbar
        // posts these instead of threading handler closures through
        // every per-format host view. Contents/Notes open the
        // annotations panel on the matching tab; Display opens reader
        // settings; AI opens the assistant when configured. Bundled
        // into one modifier so `body` stays inside the type-checker's
        // complexity budget.
        .readerToolbarActionObservers(
            onContents: {
                annotationsPanelInitialTab = .toc
                showAnnotationsPanel = true
            },
            onNotes: {
                annotationsPanelInitialTab = .highlights
                showAnnotationsPanel = true
            },
            onDisplay: { showSettings = true },
            onAI: {
                // Mirrors the legacy chrome's AI gate — a no-op when
                // AI isn't configured rather than presenting an empty
                // sheet.
                if resolvedAICoordinator.isAIAvailable {
                    showAIPanel = true
                }
            }
        )
        // Feature #60 WI-6c: the More-menu popover posts the five
        // `.readerMore*` notifications; each maps 1:1 from a
        // `ReaderMoreMenuRow`. Bundled into one modifier so `body`
        // stays inside the type-checker's complexity budget (same
        // reason as the WI-6b toolbar observers above). Action
        // semantics live in `handleMoreMenuAction(_:)`.
        .readerMoreMenuActionObservers { row in
            handleMoreMenuAction(row)
        }
        // Page turn from tap zones — handled by unified renderer directly.
        // Native mode bridges handle taps internally (center=chrome toggle).
        // Left/right zones only functional in unified paged mode. (bug #81)
        .accessibilityAction(named: isChromeVisible ? "Hide toolbar" : "Show toolbar") {
            toggleChrome()
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!isChromeVisible)
        // Feature #60 WI-10: tint the status bar to match the reader
        // theme. `preferredColorScheme` resolves to `.dark` for the
        // dark-family themes (Dark / OLED / Photo) so the status-bar
        // text stays light-on-dark, and `.light` for Paper / Sepia so
        // it stays dark-on-light. WI-11 migrated `theme` to
        // `ReaderThemeV2`, so the token is read directly.
        .preferredColorScheme(settingsStore.theme.preferredColorScheme)
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
        #if DEBUG
        // Bug #144: pull bridge-driven theme changes into the live store.
        // `RealDebugBridgeContext.theme(_:_:)` writes UserDefaults via a
        // short-lived `ReaderSettingsStore`; this observer mirrors the
        // change into the @State-owned store so an open reader re-themes
        // without an app relaunch.
        //
        // Bug #145: respect per-book override semantics. The bridge
        // command writes the GLOBAL default. When the active book has
        // a per-book override that explicitly sets a field
        // (`themeName != nil` / `fontSize != nil`), per-book wins for
        // that field — skip applying the bridge's value to keep
        // session state consistent with what reopen would re-apply.
        // Fields the per-book override leaves nil still inherit from
        // global, so the bridge change does take effect there.
        .onReceive(NotificationCenter.default.publisher(for: .debugBridgeThemeChanged)) { notification in
            guard let userInfo = notification.userInfo else { return }
            let perBook = PerBookSettingsStore.settings(
                for: book.fingerprintKey,
                baseURL: Self.perBookSettingsBaseURL
            )
            // Theme: skip when per-book themeName is explicitly set.
            // Feature #60 WI-11: decode the bridge's `mode` string via
            // `ReaderThemeV2(recognized:)` — it accepts both the new
            // rawValues the bridge now posts (`paper` / `dark`) and a
            // legacy `light` from any older notification, and yields
            // nil for an unrecognized string (no clobber).
            if perBook?.themeName == nil,
               let modeRaw = userInfo["mode"] as? String,
               let theme = ReaderThemeV2(recognized: modeRaw),
               settingsStore.theme != theme {
                settingsStore.theme = theme
            }
            // Font size: skip when per-book fontSize is explicitly set.
            if perBook?.fontSize == nil,
               let fontSize = userInfo["fontSize"] as? Int {
                var typography = settingsStore.typography
                let newSize = Double(fontSize)
                if typography.fontSize != newSize {
                    typography.fontSize = newSize
                    settingsStore.typography = typography
                }
            }
        }
        // Feature #45 WI-4c-b: drive TTS from outside the play-button tap.
        // XCUITest's gesture path cannot reliably activate AVSpeechSynthesizer's
        // audio session under iOS 26.5, so verification tests fire
        // `vreader-debug://tts?action=start` after opening a book.
        // Reuses startTTS() so the audio-session activation path is identical
        // to a real user tap — that's the property we need spike-0 to verify.
        .onReceive(NotificationCenter.default.publisher(for: .debugBridgeTTSCommand)) { notification in
            guard let action = notification.userInfo?["action"] as? String else { return }
            switch action {
            case "start":
                if ttsService.state == .idle {
                    startTTS()
                }
            case "stop":
                if ttsService.state != .idle {
                    ttsService.stop()
                }
            default:
                break
            }
        }
        #endif
        // PERF: Single deferred .task for all non-critical setup.
        // Per-book settings + TOC prep deferred to avoid contending with the
        // format host's file-open .task.
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
            // Build TOC eagerly for TXT — needed for chapter progress bar (bug #31)
            if resolvedBookFormat == .txt {
                ensureTOCReady()
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(
                store: settingsStore,
                bookFingerprintKey: book.fingerprintKey,
                perBookBaseURL: Self.perBookSettingsBaseURL,
                formatCapabilities: BookFormat(rawValue: book.format.lowercased())?.capabilities,
                bookFormat: BookFormat(rawValue: book.format.lowercased())
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
                theme: settingsStore.theme,
                initialTab: annotationsPanelInitialTab,
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
        // Feature #60 WI-6c: the More-menu "Share book" row presents
        // the system share sheet for the book file. Reuses the
        // library's `ShareSheet` (book-file `UIActivityViewController`).
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(book: book)
        }
        // Feature #61 WI-3: the More-menu "Book details" row presents
        // the reader Book Details sheet. Content composed in
        // `bookDetailsSheet` (ReaderContainerView+Sheets.swift) so the
        // body stays inside the type-checker's complexity budget.
        .sheet(isPresented: $showBookDetails, onDismiss: {
            // Feature #61 WI-4: the "Export annotations…" row routes to
            // the annotations panel — opened here, after Book Details
            // has fully dismissed, because the two are sibling sheets
            // sharing this view's presenter.
            if exportAnnotationsAfterBookDetailsDismiss {
                exportAnnotationsAfterBookDetailsDismiss = false
                annotationsPanelInitialTab = .highlights
                showAnnotationsPanel = true
            }
        }) {
            // Design `vreader-book-details.jsx` sizes the stacked sheet
            // at 660pt — a tall partial sheet, not full-height; `.large`
            // is offered so the user can expand it.
            bookDetailsSheet
                .presentationDetents([.height(660), .large])
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
            // Bug #126: wire jsEvaluator for EPUB. Closure captures the
            // book's fingerprintKey and pulls the registry's keyed webview
            // ref at call-time. The registry's `epubWebView(for:)` returns
            // nil if the stored webview was registered for a different
            // book — preventing a late didFinish from an outgoing reader
            // from being matched against an incoming probe (Codex audit
            // 2026-05-06). Compare on the typed enum, not raw string, so
            // case/aliasing drift can't silently disable the wiring.
            if resolvedBookFormat == .epub {
                let key = book.fingerprintKey
                let token = readerToken
                probe.jsEvaluator = { @MainActor script in
                    guard let webView = DebugReaderRegistry.shared.epubWebView(for: key, token: token) else {
                        throw DebugReaderProbeError.evalUnsupported(format: "epub")
                    }
                    let raw = try await webView.evaluateJavaScript(script)
                    let normalized: Any = raw ?? NSNull()
                    return try JSONSerialization.data(
                        withJSONObject: normalized,
                        options: [.fragmentsAllowed]
                    )
                }
                // Bug #141: wire settleStrategy for EPUB. The registry's
                // `awaitReaderSettled` fast-paths if the WKWebView already
                // fired `didFinish` (page-load complete), else suspends
                // until it does or the timeout throws `settleTimeout` —
                // replacing the 100ms placeholder for native EPUB.
                probe.settleStrategy = { @MainActor timeout in
                    try await DebugReaderRegistry.shared.awaitReaderSettled(
                        for: key, token: token, timeout: timeout
                    )
                }
            } else if resolvedBookFormat == .azw3 {
                // BookFormat.azw3 covers all Foliate-rendered formats
                // (azw3/azw/mobi/prc per FormatCapabilities); the
                // FoliateViewBridge is the single host for all of them.
                // Bug #141: wire jsEvaluator for AZW3/MOBI via the same
                // keyed-binding pattern as the bug #126 EPUB fix. Foliate
                // hosts a separate WKWebView (FoliateViewBridge) registered
                // via `setActiveFoliateWebView(_:for:)` from the
                // FoliateViewCoordinator's didFinish.
                let key = book.fingerprintKey
                let token = readerToken
                let formatString = book.format
                probe.jsEvaluator = { @MainActor script in
                    guard let webView = DebugReaderRegistry.shared.foliateWebView(for: key, token: token) else {
                        throw DebugReaderProbeError.evalUnsupported(format: formatString)
                    }
                    let raw = try await webView.evaluateJavaScript(script)
                    let normalized: Any = raw ?? NSNull()
                    return try JSONSerialization.data(
                        withJSONObject: normalized,
                        options: [.fragmentsAllowed]
                    )
                }
                // Bug #141: wire settleStrategy for AZW3/MOBI. Foliate-js
                // fires `relocate` only after the book is paginated and
                // rendered; `FoliateSpikeView.Coordinator` marks the
                // reader settled from its `relocate` handler. The registry
                // fast-paths if that already fired, else suspends until it
                // does or the timeout throws `settleTimeout` — replacing
                // the 100ms placeholder for the Foliate path.
                probe.settleStrategy = { @MainActor timeout in
                    try await DebugReaderRegistry.shared.awaitReaderSettled(
                        for: key, token: token, timeout: timeout
                    )
                }
            }
            // TXT/MD/PDF intentionally leave `settleStrategy` nil — the
            // 100ms `Task.sleep` fallback in `DebugReaderProbeAdapter`
            // stays for those formats (out of scope for bug #141).
            // Feature #45 WI-4c-c: surface TTS state into DebugSnapshot.
            // Closure captures the @MainActor @Observable TTSService owned
            // by this view; runs @MainActor whenever the snapshot path
            // reads `probe.currentTTSState` / `currentTTSOffsetUTF16`.
            // Offset is meaningless while idle (TTSService resets it to
            // 0 on stop), so we map idle → nil for offset to signal
            // "no current reading position" to consumers.
            let service = ttsService
            probe.ttsProbe = { @MainActor in
                let state = service.state
                let offset: Int? = (state == .idle) ? nil : service.currentOffsetUTF16
                return (state: state.publicName, offsetUTF16: offset)
            }
            debugProbe = probe
            // Bug #142: tell the registry the expected token BEFORE
            // registering the probe — that way, if a coordinator's
            // didFinish from an outgoing reader fires concurrently, the
            // registry can reject the stale write rather than clobber
            // the new reader's binding.
            DebugReaderRegistry.shared.setExpectedReaderToken(readerToken)
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
    /// a custom overlay (ReaderTopChrome) instead of the system nav bar.
    ///
    /// Feature #60 WI-6c: hiding the chrome also clears `showMorePopover`.
    /// The popover only renders while the chrome does, so without this
    /// a chrome-hide that bypasses the content-tap path (e.g. the
    /// "Hide toolbar" accessibility action) would leave `showMorePopover`
    /// set and resurrect the popover when the chrome reappears.
    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible.toggle()
            if !isChromeVisible {
                showMorePopover = false
            }
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

    // MARK: - Engine Dispatch

    /// Dispatches to the format-specific reader host, selecting the host by
    /// `ReaderEngine.resolve(format:)` (feature #54). For an unrecognized
    /// format string, `resolvedBookFormat` falls back to `.txt`; the genuine
    /// unknown-format case is the `else` of the `BookFormat(rawValue:)` guard.
    @ViewBuilder
    func engineReaderView(fingerprint: DocumentFingerprint) -> some View {
        if let format = BookFormat(rawValue: book.format.lowercased()) {
            switch ReaderEngine.resolve(format: format) {
            case .epubWKWebView:
                EPUBReaderHost(
                    fileURL: resolvedFileURL,
                    fingerprint: fingerprint,
                    modelContainer: modelContext.container,
                    settingsStore: settingsStore,
                    ttsService: ttsService,
                    readerToken: readerToken
                )
            case .pdfKit:
                PDFReaderHost(
                    fileURL: resolvedFileURL,
                    fingerprint: fingerprint,
                    modelContainer: modelContext.container,
                    ttsService: ttsService,
                    settingsStore: settingsStore
                )
            case .textNative:
                TXTReaderHost(
                    fileURL: resolvedFileURL,
                    fingerprint: fingerprint,
                    modelContainer: modelContext.container,
                    settingsStore: settingsStore,
                    ttsService: ttsService,
                    tocEntries: tocEntries
                )
            case .markdownNative:
                MDReaderHost(
                    fileURL: resolvedFileURL,
                    fingerprint: fingerprint,
                    modelContainer: modelContext.container,
                    settingsStore: settingsStore,
                    ttsService: ttsService
                )
            case .foliateWeb:
                FoliateSpikeView(
                    bookURL: resolvedFileURL,
                    fingerprintKey: book.fingerprintKey,
                    readerToken: readerToken,
                    settingsStore: settingsStore,
                    highlightActionPresenter: UIKitHighlightActionPresenter(),
                    coordinatorBox: foliateCoordinatorBox
                )
            }
        } else {
            unsupportedFormatView(format: book.format.uppercased())
        }
    }

    // MARK: - Error / Unsupported Views

    /// Shown when the book's `fingerprintKey` cannot be parsed into a
    /// `DocumentFingerprint`.
    var fingerprintErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to open this book.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("fingerprintErrorView")
    }

    /// Shown when the book's format string maps to no known `BookFormat`.
    func unsupportedFormatView(format: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(format) reader coming soon")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("unsupportedFormatView")
    }
}


