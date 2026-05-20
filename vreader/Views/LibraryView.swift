// Purpose: Main library view displaying the user's book collection,
// re-skinned for feature #60 visual identity v2 (WI-9 — container pass).
//
// The container shell follows the design `LibraryScreen` in
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// a warm-paper backdrop, a row of circular pill buttons in place of
// the system toolbar, a 36pt Source Serif 4 title with a `{N} books ·
// {M} reading` subtitle, a toggleable search bar, a horizontal
// filter-chip row, a "Continue reading" rail, and the grid/list body.
//
// Behavior is preserved verbatim across the re-skin — feature #47
// lazy-download row taps, OPDS catalogs, AI chat, collections, the
// context menu, cover picker, pull-to-refresh, swipe-to-delete, the
// empty state, and every bug-fix `.onReceive` observer still work.
//
// Key decisions:
// - The system `.navigationBar` toolbar is replaced by `LibraryNavBar`
//   (designed pill buttons). The `NavigationStack` is kept only for
//   the push-to-reader destination; its bar is hidden.
// - Search / filter derivations live in `LibraryContainerModel` (a
//   pure value type) so they are unit-testable without a render.
// - The sheet / alert / importer chain and the notification-observer
//   chain are extracted into `LibraryViewSheets` / `LibraryViewObservers`
//   view modifiers — the body would otherwise exceed the Swift
//   type-checker's complexity ceiling.
//
// @coordinates-with: LibraryViewModel.swift, BookCardView.swift, BookRowView.swift,
//   LibraryNavBar.swift, LibrarySearchBar.swift, LibraryFilterChips.swift,
//   ContinueReadingRail.swift, LibraryContainerModel.swift,
//   LibraryViewSheets.swift, LibraryViewObservers.swift,
//   ReaderContainerView.swift

import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "LibraryView")
import UniformTypeIdentifiers

/// Main library view for the book collection.
struct LibraryView: View {
    // NOTE: several `@State` / `@Environment` members below are
    // `internal` (no `private`) rather than `private` so the
    // `LibraryView+Body.swift` extension file (grid / list / context
    // menu) can read them. This mirrors `ReaderContainerView`'s split
    // with `ReaderContainerView+Sheets.swift`.
    @Environment(\.modelContext) var modelContext
    @State var viewModel: LibraryViewModel
    @State var bookToDelete: LibraryBookItem?
    @State var bookForInfo: LibraryBookItem?
    @State var bookToShare: LibraryBookItem?
    /// Bound to BookDownloadSheet — set when the user taps a non-`.local`
    /// row, cleared on success/cancel. Feature #47 WI-6.
    @State private var bookForDownloadSheet: LibraryBookItem?
    @State var isShowingImporter = false
    @State private var isShowingSettings = false
    @State private var isShowingAIChat = false
    /// Bug #93: cache the general-chat VM across sheet open/close cycles
    /// so multi-turn history is preserved when the user dismisses and
    /// re-opens the chat. Created lazily on first sheet open and reused
    /// for the rest of the LibraryView's lifetime.
    @State private var generalChatVM: AIChatViewModel?
    @State private var isShowingOPDSCatalogs = false
    @State private var isShowingCollections = false
    @State private var activeFilter: LibraryFilter = .allBooks
    /// Feature #60 WI-9: raw search text. Empty unless the search bar
    /// is open and the user has typed. `LibraryContainerModel` trims it.
    @State private var searchQuery: String = ""
    /// Feature #60 WI-9: whether the toggleable search bar is shown.
    @State private var isSearchVisible: Bool = false
    @State var collectionRecords: [CollectionRecord] = []
    @State private var allTags: [String] = []
    @State private var allSeries: [String] = []
    /// Fingerprint keys of books with new chapters detected by UpdateChecker (D07a).
    @State private var booksWithUpdates: Set<String> = []
    /// Owns the custom-cover PhotosPicker flow (feature #61 WI-2): the
    /// picker state plus a coverVersion counter the card / row / rail
    /// views observe. Not `private` — `LibraryView+Body.swift` reads it.
    @State var coverPickCoordinator = CoverPickCoordinator()
    /// Feature #56 WI-14 — per-book translate-entire-book progress
    /// snapshots mirrored from `BookTranslationCoordinator.shared` via
    /// `.readerBookTranslationProgressDidChange`. Drives the optional
    /// `LibraryCardTranslateBadge` overlay on each `BookCardView`.
    /// Cards without an entry render with the default `.idle` progress
    /// (badge hidden) so existing rows stay visually identical for
    /// books that haven't been translated.
    @State var translationProgressByBook: [String: BookTranslationProgress] = [:]
    /// Tracks NavigationStack path so the library chrome can hide during push transitions.
    @State private var navigationPath = NavigationPath()
    /// Set before appending to navigationPath so the chrome hides before the push animation starts (bug #72).
    @State private var isPushingReader = false
    let syncMonitor: SyncStatusMonitor?

    init(viewModel: LibraryViewModel, syncMonitor: SyncStatusMonitor? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.syncMonitor = syncMonitor
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                LibraryCardTokens.shellBackground
                    .ignoresSafeArea()

                if viewModel.isInitialLoad {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityIdentifier("libraryLoadingIndicator")
                } else {
                    libraryContent
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: LibraryBookItem.self) { book in
                ReaderContainerView(book: book)
            }
            .refreshable {
                await viewModel.refresh()
                await checkForBookSourceUpdates()
            }
            .task {
                await viewModel.loadBooks()
                // Load collections eagerly for the chip row + context
                // menu "Add to Collection" (bug #85; feature #60 WI-9).
                let persistence = PersistenceActor(modelContainer: modelContext.container)
                collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
            }
            .onChange(of: navigationPath) { _, newPath in
                // Reset chrome visibility when returning from reader (bug #72)
                if newPath.isEmpty { isPushingReader = false }
            }
            .onChange(of: viewModel.isEmpty) { _, isEmpty in
                // When the last book is removed, the Search pill is
                // dropped from the nav bar — clear any open search so
                // a re-import in the same session doesn't return with
                // the search bar unexpectedly expanded (Gate 4 round 2).
                if isEmpty {
                    isSearchVisible = false
                    searchQuery = ""
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .readerBookTranslationProgressDidChange)) { notification in
                // Feature #56 WI-14 — mirror translate-entire-book
                // progress so each library card's
                // `LibraryCardTranslateBadge` overlay reflects the live
                // job state. Filter by `fingerprintKey`; a notification
                // missing the key (defensive) is ignored.
                guard let key = notification.userInfo?["fingerprintKey"] as? String,
                      let completed = notification.userInfo?["completed"] as? Int,
                      let total = notification.userInfo?["total"] as? Int,
                      let phaseRaw = notification.userInfo?["phase"] as? String,
                      let phase = BookTranslationProgress.Phase(rawValue: phaseRaw)
                else { return }
                translationProgressByBook[key] = BookTranslationProgress(
                    phase: phase, completed: completed, total: total)
            }
            .modifier(LibraryViewObservers(
                viewModel: viewModel,
                bookForDownloadSheet: $bookForDownloadSheet,
                isPushingReader: $isPushingReader,
                navigationPath: $navigationPath
            ))
            .modifier(LibraryViewSheets(
                viewModel: viewModel,
                bookToDelete: $bookToDelete,
                bookForInfo: $bookForInfo,
                bookToShare: $bookToShare,
                bookForDownloadSheet: $bookForDownloadSheet,
                isShowingImporter: $isShowingImporter,
                isShowingSettings: $isShowingSettings,
                isShowingAIChat: $isShowingAIChat,
                isShowingOPDSCatalogs: $isShowingOPDSCatalogs,
                isShowingCollections: $isShowingCollections,
                activeFilter: $activeFilter,
                collectionRecords: $collectionRecords,
                allTags: $allTags,
                allSeries: $allSeries,
                coverPickCoordinator: coverPickCoordinator,
                resolvedGeneralChatVM: resolvedGeneralChatVM
            ))
        }
    }

    // MARK: - Constants

    static let importableTypes: [UTType] = {
        var types: [UTType] = [.epub, .pdf, .plainText]
        if let md = UTType("net.daringfireball.markdown") {
            types.append(md)
        }
        // AZW3/MOBI — no system UTType, use generic binary data.
        if let mobi = UTType("com.amazon.mobi8-ebook") {
            types.append(mobi)
        }
        // Accept generic data so .azw3/.mobi/.azw aren't filtered out
        types.append(.data)
        return types
    }()

    // MARK: - Container composition (feature #60 WI-9)

    /// The re-skinned container shell — nav bar, title, subtitle,
    /// optional search bar, filter chips, then the scrollable region
    /// holding the optional Continue-reading rail + the grid/list body.
    ///
    /// The nav bar + title stay mounted for the empty-library state so
    /// the user keeps access to Settings / OPDS / Collections / AI /
    /// Import (the pre-#60 toolbar stayed visible when empty too). The
    /// search bar and filter chips are suppressed when empty — there is
    /// nothing to search or filter — but the empty-state CTA replaces
    /// the grid / list body.
    private var libraryContent: some View {
        VStack(spacing: 0) {
            navBar
            titleBlock

            if viewModel.isEmpty {
                emptyState
            } else {
                if isSearchVisible {
                    LibrarySearchBar(query: $searchQuery)
                        .padding(.bottom, 12)
                }
                LibraryFilterChips(
                    activeFilter: $activeFilter,
                    collections: collectionRecords
                )
                .padding(.bottom, 14)

                scrollableBody
            }
        }
    }

    /// Pure derivation layer for the current search + filter state.
    /// Not `private` — `LibraryView+Body.swift` (the grid/list/context-
    /// menu extension) reads it.
    var containerModel: LibraryContainerModel {
        LibraryContainerModel(
            searchQuery: searchQuery,
            activeFilter: activeFilter
        )
    }

    /// Books visible in the grid / list under the active filter + query.
    /// Not `private` — consumed by `LibraryView+Body.swift`.
    var displayedBooks: [LibraryBookItem] {
        containerModel.matchingBooks(in: viewModel.books)
    }

    /// The re-skinned nav-bar pill row. Hidden during a reader push
    /// (`isPushingReader`) so the custom chrome does not flicker over
    /// the push transition — the re-skin's equivalent of bug #72's
    /// pre-#60 `.toolbar(isPushingReader ? .hidden : .visible)`.
    private var navBar: some View {
        LibraryNavBar(
            viewMode: viewModel.viewMode,
            isAIChatAvailable: isAIChatAvailable,
            isSearchEnabled: !viewModel.isEmpty,
            syncMonitor: syncMonitor,
            onSettings: { isShowingSettings = true },
            onSearchToggle: {
                isSearchVisible.toggle()
                // Clearing the query on collapse keeps the grid from
                // staying filtered by a no-longer-visible search.
                if !isSearchVisible { searchQuery = "" }
            },
            onViewModeToggle: { viewModel.toggleViewMode() },
            onCollections: { openCollections() },
            onOPDSCatalogs: { isShowingOPDSCatalogs = true },
            onAIChat: { isShowingAIChat = true },
            onImport: { isShowingImporter = true }
        )
        .padding(.top, 6)
        .opacity(isPushingReader ? 0 : 1)
    }

    /// 36pt Source Serif 4 "Library" title + the `{N} books · {M} reading`
    /// taupe subtitle — design `LibraryScreen` title block.
    private var titleBlock: some View {
        let counts = containerModel.subtitleCounts(for: viewModel.books)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(LibraryCardTokens.serifTitleFont(
                    size: LibraryCardTokens.titleFontSize
                ))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            Text(subtitleText(for: counts))
                .font(.system(size: LibraryCardTokens.subtitleFontSize))
                .foregroundStyle(LibraryCardTokens.subText)
                .padding(.bottom, 16)
                .accessibilityIdentifier("librarySubtitle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LibraryCardTokens.shellContentPadding)
    }

    /// The `{N} books · {M} reading` subtitle string. Pluralized so a
    /// single-book library doesn't read "1 books".
    private func subtitleText(
        for counts: LibraryContainerModel.SubtitleCounts
    ) -> String {
        let bookWord = counts.total == 1 ? "book" : "books"
        return "\(counts.total) \(bookWord) · \(counts.reading) reading"
    }

    /// The scrollable region — the optional Continue-reading rail and
    /// the "All books" sort header above the grid / list body. Grid
    /// mode scrolls via a `ScrollView` + `LazyVGrid`; list mode is a
    /// native `List` (so `.swipeActions` swipe-to-delete survives the
    /// re-skin — see `LibraryView+Body.swift`).
    @ViewBuilder
    private var scrollableBody: some View {
        switch viewModel.viewMode {
        case .grid:
            ScrollView {
                VStack(spacing: 0) {
                    continueReadingRail
                    LibrarySectionHeader(sortOrder: $viewModel.sortOrder)
                    gridBody
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        case .list:
            listBody
        }
    }

    /// The Continue-reading rail — shown only under `.allBooks` with no
    /// query (design parity) AND when at least one book is in progress.
    @ViewBuilder
    var continueReadingRail: some View {
        if containerModel.showsContinueReadingRail {
            let inProgress = containerModel
                .continueReadingBooks(in: viewModel.books)
            if !inProgress.isEmpty {
                ContinueReadingRail(
                    books: sortedContinueReading(inProgress),
                    coverVersion: coverPickCoordinator.coverVersion,
                    onOpen: openBook
                )
            }
        }
    }

    /// Continue-reading cards ordered most-recently-read first — the
    /// design sorts the rail by `lastRead`. Books with no last-read
    /// timestamp sort after those that have one.
    private func sortedContinueReading(
        _ books: [LibraryBookItem]
    ) -> [LibraryBookItem] {
        books.sorted { lhs, rhs in
            switch (lhs.lastReadAt, rhs.lastReadAt) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    == .orderedAscending
            }
        }
    }

    // MARK: - Collections

    /// Loads tags / series / collections, then presents the sidebar.
    private func openCollections() {
        Task {
            let persistence = PersistenceActor(modelContainer: modelContext.container)
            collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
            allTags = (try? await persistence.fetchAllTags()) ?? []
            allSeries = (try? await persistence.fetchAllSeriesNames()) ?? []
            isShowingCollections = true
        }
    }

    // MARK: - AI Chat

    /// Whether the AI chat button should be visible in the nav bar.
    private var isAIChatAvailable: Bool {
        AIReaderAvailability.isAvailable(
            featureFlags: FeatureFlags.shared,
            keychainService: KeychainService(),
            consentManager: AIConsentManager()
        )
    }

    /// Bug #93: lazily resolves the general-chat VM, caching it in
    /// `@State` so it survives sheet dismiss/re-present.
    private var resolvedGeneralChatVM: AIChatViewModel {
        if let existing = generalChatVM { return existing }
        let vm = makeGeneralChatViewModel()
        DispatchQueue.main.async {
            generalChatVM = vm
        }
        return vm
    }

    /// Creates an AIChatViewModel for general (non-book) chat.
    private func makeGeneralChatViewModel() -> AIChatViewModel {
        let service = AIService(
            featureFlags: FeatureFlags.shared,
            consentManager: AIConsentManager(),
            keychainService: KeychainService(),
            profileStore: ProviderProfileStore.shared
        )
        return AIChatViewModel(aiService: service, bookFingerprint: nil)
    }

    // MARK: - Update Checker (D07a)

    /// Checks enabled BookSources for new chapters on tracked books.
    private func checkForBookSourceUpdates() async {
        // TODO: Wire up once books track their source URL and chapter count.
        // For now this is a no-op infrastructure hook for pull-to-refresh.
    }

    // MARK: - Navigation (bug #72)

    /// Hides the library chrome before pushing to the reader. Feature
    /// #47 WI-5 gate: only `.local` rows open the reader; tapping a
    /// non-`.local` row posts a notification the observer listens for.
    /// Not `private` — `LibraryView+Body.swift`'s grid/list buttons call it.
    func openBook(_ book: LibraryBookItem) {
        log.info("openBook: \(book.fingerprintKey, privacy: .public) fileState=\(book.fileState.rawValue, privacy: .public) isReadable=\(book.isReadable, privacy: .public)")
        guard book.isReadable else {
            log.info("openBook: posting libraryRowTappedWhileNotLocal for \(book.fingerprintKey, privacy: .public)")
            NotificationCenter.default.post(
                name: .libraryRowTappedWhileNotLocal,
                object: nil,
                userInfo: [
                    "fingerprintKey": book.fingerprintKey,
                    "fileState": book.fileState.rawValue
                ]
            )
            return
        }
        isPushingReader = true
        navigationPath.append(book)
    }
}
