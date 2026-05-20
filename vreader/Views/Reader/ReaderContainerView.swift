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
// - Annotations sheets: feature #62 split the unified panel into
//   `TOCSheet` (Contents/Bookmarks) + `HighlightsSheet` (review),
//   routed via `AnnotationsSheetRoute`.
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
//   TOCSheet.swift, HighlightsSheet.swift, AnnotationsSheetRoute.swift,
//   ReaderSettingsStore.swift, ReaderSettingsPanel.swift,
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
    /// Feature #62: `TOCSheet`'s Contents-empty "Open Search" CTA must
    /// open the reader search sheet — but `TOCSheet` is itself a sheet,
    /// so the search sheet is opened from `annotationsRoute`'s
    /// `.sheet(onDismiss:)` once `TOCSheet` has fully dismissed (the same
    /// sibling-sheet hand-off feature #61 established for Book Details).
    @State var openSearchAfterAnnotationsDismiss = false
    /// Feature #62: which annotations sheet the reader presents — `nil`
    /// when none is up. Replaces the feature-#60 WI-6b
    /// `showAnnotationsPanel` + `annotationsPanelInitialTab` pair: the
    /// `TOCSheet` and `HighlightsSheet` are mutually exclusive, so one
    /// optional route makes that a type invariant and carries the
    /// initial tab/filter inline. Kept `internal` (not `private`) so the
    /// More-menu router in `+Sheets.swift` can write it.
    @State var annotationsRoute: AnnotationsSheetRoute?
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
    /// Feature #56 WI-14 — the host-owned translate-entire-book view
    /// model + the resolved per-format text provider published by the
    /// active reader container. Set lazily on the first Book Details
    /// open. Lifetime tied to `ReaderContainerView` so a confirm-alert
    /// → status-sheet → cancel handoff survives Book Details dismiss.
    @State var translateBookVM: BookTranslationViewModel?
    /// Feature #56 WI-15 — the per-chapter re-translation view model + the
    /// list of `ProviderProfile`s the picker offers. The VM is constructed
    /// lazily on the first `.readerMoreReTranslateChapter` notification and
    /// held for the reader's lifetime so a picker → progress → complete →
    /// re-open cycle reuses the same selection state. The profile list is
    /// loaded fresh at picker-open time (Codex Gate-4-pattern from WI-14:
    /// the active profile may have changed between opens).
    @State var reTranslateVM: ChapterReTranslateViewModel?
    @State var reTranslateProviderProfiles: [ProviderProfile] = []

    /// Latest text provider published by the active reader container.
    /// TXT / EPUB / MD / Foliate containers post
    /// `.readerBookTranslationTextProviderAvailable` with their provider
    /// the moment it's ready (chapter index built, EPUB spine parsed,
    /// etc.); the host caches it here. The provider config snapshot is
    /// NOT cached — it's resolved fresh at confirm time so profile/model
    /// changes between Book Details open and translate tap are picked
    /// up (Codex Gate-4 medium finding).
    @State var translateBookTextProvider: (any ChapterTextProviding)?
    @State private var showDictionary = false
    @State private var dictionaryWord: String = ""
    /// Controls whether the navigation bar chrome is visible. Tap content to toggle.
    @State private var isChromeVisible = true
    /// Computed TOC entries for the current book (format-specific).
    @State var tocEntries: [TOCEntry] = []
    /// Feature #62: true once the eager `ensureTOCReady()` build has
    /// completed. Passed into `TOCSheet` so its Contents tab does not
    /// flash a false "No table of contents" empty state when the
    /// Contents chrome button is tapped before the build resolves —
    /// the same load-vs-emptiness distinction `TOCSheet` already makes
    /// for bookmarks (`bookmarksDidLoad`).
    @State var tocDidLoad = false
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

    // MARK: - Feature #56 WI-10: bilingual reading parent state
    //
    // The bilingual VM lives in the per-format host (EPUB / Foliate /
    // TXT / MD / PDF), but the chrome (pill, More popover bilingual
    // row state) lives on the parent container. The host posts
    // `.readerBilingualDidChange` whenever its state changes; the
    // parent mirrors `isEnabled` + `targetLanguage` here so the
    // chrome can render without crossing the host boundary.

    /// Whether bilingual mode is active for the open book — mirrors
    /// the per-format host's VM state via `.readerBilingualDidChange`.
    /// Drives the `BilingualPill` render path in `ReaderTopChrome`.
    @State var bilingualActive: Bool = false

    /// The bilingual target language key (one of `BilingualLanguage.all`).
    /// Mirrored alongside `bilingualActive`; the pill resolves the
    /// glyph from this key via the registry's fallback.
    @State var bilingualLanguage: String?

    /// Feature #57: handle to the live `FoliateSpikeView.Coordinator`
    /// for AZW3/MOBI books, populated by the spike's `makeCoordinator()`.
    /// The TTS path (`startTTS()`) calls the Coordinator's
    /// `extractPlainText()` through this box once the book has rendered.
    /// Holds the Coordinator `weak`, so this `@State` does not leak the
    /// reader. `internal` (not `private`) because `startAZW3TTS` lives
    /// in the `+Sheets.swift` extension — same reason as the sibling
    /// `showSettings` / `showShareSheet` flags.
    @State var foliateCoordinatorBox = FoliateCoordinatorBox()

    /// Feature #57 (round-2 Finding 1): the in-flight AZW3/MOBI
    /// extraction gate. The whole-book `extractPlainText()` section
    /// walk takes noticeable time; a rapid second speaker tap before
    /// it completes must not spawn a duplicate walk. `startAZW3TTS`
    /// stores its extraction `Task` here while it runs and clears it
    /// on completion; a re-tap with this non-nil is a no-op.
    /// `Task<String?, Never>` — `extractPlainText()` is non-throwing
    /// (its own 12 s timeout maps a hang to nil), so the gate always
    /// clears. `@State`-owned per-reader handle, never a global.
    /// `internal` for the `+Sheets.swift` extension (same reason as
    /// `foliateCoordinatorBox` above).
    @State var azw3ExtractionTask: Task<String?, Never>?

    #if DEBUG
    /// DebugBridge probe (feature #44). Registers on appear, unregisters on
    /// disappear. Holds a closure that the registry queries for the current
    /// position; v1 will wire per-format settle/eval hooks here.
    @State private var debugProbe: DebugReaderProbeAdapter?

    /// Bug #238 — in-flight bridge-search task. A new
    /// `.debugBridgeSearchCommand` URL cancels the previous task before
    /// spawning a new one; `.onDisappear` also cancels so a late completion
    /// can never fire `.readerNavigateToLocator` after the reader closes.
    /// `internal` (not `private`) for the +DebugBridgeSearch extension.
    @State var debugBridgeSearchTask: Task<Void, Never>?
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

            // Feature #56 WI-14: reader-side translate-entire-book
            // banner — appears when a global translate job is in flight
            // for the open book. Tapping the banner body opens the
            // status sheet; the trailing close pill presents the cancel
            // confirmation. Anchored under the chrome.
            if let vm = translateBookVM, vm.progress.isRunning {
                VStack {
                    Spacer().frame(height: 88)
                    ReaderTranslateBanner(
                        progress: vm.progress,
                        targetLanguageLabel: "Chinese",
                        theme: settingsStore.theme,
                        onOpen: { vm.openStatusSheet() },
                        onCancel: { vm.requestCancel() })
                        .padding(.horizontal, 14)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(true)
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
                // Feature #62: Contents opens `TOCSheet`; Notes opens
                // `HighlightsSheet` on the All filter — the design's
                // bottom-chrome routing.
                annotationsRoute = AnnotationsSheetRoute.route(forChromeButton: .contents)
            },
            onNotes: {
                annotationsRoute = AnnotationsSheetRoute.route(forChromeButton: .notes)
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
        // Feature #56 WI-13: PDF below-page bilingual panel's
        // offline-state "Open AI tab" button posts
        // `.readerOpenAITranslate` to open the AI sheet on the
        // `.translate` tab without a selection. Routed through a
        // dedicated `ViewModifier` so the body stays under SwiftUI's
        // type-inference budget after WI-14's additions.
        .modifier(ReaderOpenAITranslateObserver(
            isAIAvailable: resolvedAICoordinator.isAIAvailable,
            translationViewModel: resolvedAICoordinator.translationViewModel,
            ensureAIReady: { ensureAIReady() },
            setInitialTab: { aiInitialTab = $0 },
            setShowAIPanel: { showAIPanel = $0 }
        ))
        // AI setup + text loading deferred until AI/TTS is invoked (bug #64)
        .onChange(of: showAIPanel) { _, isShowing in
            if isShowing { ensureAIReady() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerBilingualDidChange)) { notification in
            // Feature #56 WI-10: mirror the per-format host's
            // bilingual VM state into the parent so the chrome
            // (pill + More-menu row) can render without crossing the
            // host boundary. The host posts on enable/disable +
            // language/granularity change; the userInfo carries the
            // book's `fingerprintKey` so an unrelated host (e.g. a
            // second reader off-screen) does not pollute this state.
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == book.fingerprintKey else { return }
            let enabled = notification.userInfo?["isEnabled"] as? Bool
            let language = notification.userInfo?["targetLanguage"] as? String
            // The current `postDidChange()` in BilingualReadingViewModel
            // only sends `fingerprintKey`; fall back to a paint based
            // on the presence of the notification — if we got here for
            // this book, the host wants the chrome refreshed. The
            // explicit fields are forward-looking for richer payloads.
            if let enabled { bilingualActive = enabled }
            if let language { bilingualLanguage = language }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .readerBookTranslationTextProviderAvailable)) { notification in
            // Feature #56 WI-14 — the active per-format reader container
            // has constructed its ChapterTextProviding adapter and is
            // publishing it to the host so the Book Details translate-
            // book entry point can use it. Cache the provider for this
            // book; the VM is constructed lazily so we don't pay the
            // cost for users who never open Book Details. **Provider
            // config is NOT resolved here** — a user may not tap the
            // translate row for minutes, and the active profile could
            // have changed in the meantime. We re-resolve at confirm
            // time so the snapshot reflects the user's choices at the
            // moment they commit (Codex Gate-4 medium-finding follow-up).
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == book.fingerprintKey else { return }
            guard let provider = notification.object as? (any ChapterTextProviding) else { return }
            translateBookTextProvider = provider
            if translateBookVM == nil {
                let vm = BookTranslationViewModel(
                    bookFingerprintKey: book.fingerprintKey,
                    coordinator: BookTranslationCoordinator.shared)
                translateBookVM = vm
                // Reader-side observation — keeps `ReaderTranslateBanner`
                // in sync regardless of whether Book Details is open.
                // Without this the banner only updated while the Book
                // Details overlay was mounted (Codex Gate-4 round-2 H1).
                Task { @MainActor in await vm.startObserving() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPositionDidChange)) { notification in
            guard let locator = notification.object as? Locator else { return }
            currentLocator = locator
            resolvedAICoordinator.currentLocator = locator
            if resolvedAICoordinator.loadedTextContent != nil {
                resolvedAICoordinator.chatViewModel?.bookContext = resolvedAICoordinator.currentTextContent
            }
        }
        // Feature #56 WI-15: per-chapter re-translation picker. The
        // observer fires on `.readerMoreReTranslateChapter`, resolves the
        // current unit, builds the VM lazily, and raises the sheet.
        // Factored into `ReaderReTranslateObserver` so the body stays under
        // SwiftUI's type-inference budget (WI-13 / WI-14 precedent).
        .modifier(ReaderReTranslateObserver(
            isPresented: reTranslatePickerBinding,
            sheetContent: { reTranslateSheetContent },
            onTrigger: { handleReTranslateChapterRequested() }
        ))
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
        // Bug #238 — drive the in-reader search sheet from outside the
        // chrome. Factored into a dedicated `ViewModifier` (same precedent
        // as `ReaderOpenAITranslateObserver`) so adding the new observer
        // doesn't push `body` over SwiftUI's type-inference budget.
        .modifier(ReaderDebugBridgeSearchObserver(
            onCommand: { query, index in
                handleDebugBridgeSearchCommand(query: query, index: index)
            }
        ))
        // Bug #237 — DebugBridge highlight-driver observer lives in the
        // TXT and MD format hosts, NOT here. Format hosts have the source
        // text + chapter index they need to build canonical Locators via
        // `LocatorFactory`, and they own a `HighlightCoordinator`. Wiring
        // the observer here would mean any EPUB/PDF/AZW3 reader receiving
        // a stray `vreader-debug://highlight` URL would persist a
        // TXT-shaped highlight against its own book — invisible because
        // EPUB/PDF require an anchor, and a dedupe mismatch (canonicalHash
        // includes textQuote/context). See TXTReaderContainerView and
        // MDReaderContainerView for the per-format observer wiring.
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
            // Feature #62: build the TOC eagerly on reader load — for
            // TXT it feeds the chapter progress bar (bug #31), and for
            // every format it gets `tocEntries` populated before the
            // user can reach the Contents chrome button. The eager
            // build alone is best-effort (the build is async); the
            // hard guarantee that `TOCSheet`'s "No table of contents"
            // empty state means "this book ships no TOC" rather than
            // "still loading" is the `tocDidLoad` flag passed into the
            // sheet — it withholds the empty state until the build
            // resolves. `ensureTOCReady()` is idempotent.
            ensureTOCReady()
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
        // Feature #62: the annotations panel split — Contents/Bookmarks
        // present `TOCSheet`, the review filters present `HighlightsSheet`.
        // One `.sheet(item:)` over the `AnnotationsSheetRoute` replaces the
        // legacy `.sheet(isPresented:)` over the unified `AnnotationsPanelView`.
        .sheet(item: $annotationsRoute, onDismiss: {
            // The TOCSheet "Open Search" CTA defers the search sheet to
            // this dismiss handler — TOCSheet is itself a sheet, so
            // presenting `showSearch` while it is up risks the
            // double-sheet drop (the feature-#61 sibling-sheet pattern).
            if openSearchAfterAnnotationsDismiss {
                openSearchAfterAnnotationsDismiss = false
                showSearch = true
            }
        }) { route in
            annotationsSheet(for: route)
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
            // Feature #61 WI-4 / #62: the "Export annotations…" row
            // routes to `HighlightsSheet` (Highlights filter) — opened
            // here, after Book Details has fully dismissed, because the
            // two are sibling sheets sharing this view's presenter.
            if exportAnnotationsAfterBookDetailsDismiss {
                exportAnnotationsAfterBookDetailsDismiss = false
                annotationsRoute = .highlights(initialFilter: .highlights)
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
        // Feature #62: the bug-#64 `.onChange(of: showAnnotationsPanel)`
        // deferred-TOC call is dropped — `ensureTOCReady()` is now an
        // eager preload in the reader-load `.task` above, so the TOC is
        // ready before the Contents chrome button is reachable.
        // Feature #57: cancel an in-flight AZW3/MOBI TTS extraction
        // walk when the reader is dismissed, so a late completion can
        // never call `startSpeaking` after the reader has closed. The
        // post-await block in `startAZW3TTS` also re-checks
        // `Task.isCancelled`, so cancellation here suppresses late
        // speech even if the walk had already resolved.
        // Bug #238 (DEBUG-only): same posture for the bridge-search
        // task — kill it so a late result tap can never post
        // `.readerNavigateToLocator` after the reader closes.
        .onDisappear {
            azw3ExtractionTask?.cancel()
            azw3ExtractionTask = nil
            #if DEBUG
            debugBridgeSearchTask?.cancel()
            debugBridgeSearchTask = nil
            #endif
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
                // Feature #56 WI-11: wraps the live AZW3/MOBI spike
                // in the bilingual container.
                FoliateBilingualContainerView(
                    bookURL: resolvedFileURL,
                    fingerprintKey: book.fingerprintKey,
                    readerToken: readerToken,
                    settingsStore: settingsStore,
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

/// Feature #56 WI-13: dedicated `ViewModifier` for the
/// `.readerOpenAITranslate` notification. The PDF below-page bilingual
/// panel's offline-state "Open AI tab" button posts this; the
/// container resets stale Translate-tab state and opens the AI sheet
/// on the `.translate` tab without a selection. Factored out of
/// `ReaderContainerView.body` so the body stays under SwiftUI's
/// type-inference budget after WI-14's translate-book additions.
private struct ReaderOpenAITranslateObserver: ViewModifier {
    let isAIAvailable: Bool
    let translationViewModel: AITranslationViewModel?
    let ensureAIReady: () -> Void
    let setInitialTab: (AIReaderTab) -> Void
    let setShowAIPanel: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .readerOpenAITranslate)
        ) { _ in
            // Gated on AI availability (matches the
            // `.readerTranslateRequested` defense-in-depth precedent).
            guard isAIAvailable else { return }
            ensureAIReady()
            // Gate-4 round-1 M1: clear stale Translate-tab state
            // before opening cold — `.readerTranslateRequested`
            // overwrites `originalText` with a fresh selection, but
            // the no-selection path here would leave the prior
            // selection's text + result visible. Reset the
            // translation VM to its idle state.
            translationViewModel?.reset()
            setInitialTab(.translate)
            setShowAIPanel(true)
        }
    }
}


