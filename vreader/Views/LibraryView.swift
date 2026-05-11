// Purpose: Main library view displaying the user's book collection.
// Supports grid/list toggle, sorting, pull-to-refresh, swipe-to-delete,
// context menu with Info/Share/Delete, empty state with onboarding CTA,
// general AI chat entry point (WI-013), and OPDS catalog browsing (WI-C04).
//
// Key decisions:
// - Uses .refreshable for pull-to-refresh (delegates to ViewModel throttle).
// - Grid uses adaptive columns for responsive layout.
// - Sort picker and view mode toggle in toolbar.
// - Empty state shown when library is empty.
// - Context menu provides Info, Share, Set Cover, Remove Cover, and Delete actions.
// - Custom covers via PhotosPicker; stored/loaded through CustomCoverStore.
// - Delete via context menu (grid) and swipe actions (list).
// - AI chat button shown conditionally (feature flag + API key).
// - OPDS catalog button opens catalog management sheet.
//
// @coordinates-with: LibraryViewModel.swift, BookCardView.swift, BookRowView.swift,
//   ReaderContainerView.swift, BookInfoSheet.swift, SettingsView.swift, AIChatView.swift,
//   CustomCoverStore.swift, OPDSCatalogListView.swift

import SwiftUI
import Combine
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "LibraryView")
import PhotosUI
import UniformTypeIdentifiers

/// Main library view for the book collection.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lazyDownloadCoordinator) private var lazyDownloadCoordinator
    @Environment(\.webDAVNetworkPolicy) private var webDAVNetworkPolicy
    @State private var viewModel: LibraryViewModel
    @State private var bookToDelete: LibraryBookItem?
    @State private var bookForInfo: LibraryBookItem?
    @State private var bookToShare: LibraryBookItem?
    /// Bound to BookDownloadSheet — set when the user taps a non-`.local`
    /// row, cleared on success/cancel. Feature #47 WI-6.
    @State private var bookForDownloadSheet: LibraryBookItem?
    @State private var isShowingImporter = false
    @State private var isShowingSettings = false
    @State private var isShowingAIChat = false
    /// Bug #93: cache the general-chat VM across sheet open/close cycles
    /// so multi-turn history is preserved when the user dismisses and
    /// re-opens the chat. Created lazily on first sheet open and reused
    /// for the rest of the LibraryView's lifetime. Same pattern as
    /// `ReaderAICoordinator` ownership in `ReaderContainerView`.
    @State private var generalChatVM: AIChatViewModel?
    @State private var isShowingOPDSCatalogs = false
    @State private var isShowingCollections = false
    @State private var activeFilter: LibraryFilter = .allBooks
    @State private var collectionRecords: [CollectionRecord] = []
    @State private var allTags: [String] = []
    @State private var allSeries: [String] = []
    /// Fingerprint keys of books with new chapters detected by UpdateChecker (D07a).
    @State private var booksWithUpdates: Set<String> = []
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var bookForCover: LibraryBookItem?
    @State private var isShowingCoverPicker = false
    /// Incremented when a custom cover is set or removed, to force card/row views to reload.
    @State private var coverVersion: Int = 0
    /// Tracks NavigationStack path so the library toolbar can hide during push transitions.
    @State private var navigationPath = NavigationPath()
    /// Set before appending to navigationPath so the toolbar hides before the push animation starts (bug #72).
    @State private var isPushingReader = false
    let syncMonitor: SyncStatusMonitor?

    init(viewModel: LibraryViewModel, syncMonitor: SyncStatusMonitor? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.syncMonitor = syncMonitor
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isInitialLoad {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityIdentifier("libraryLoadingIndicator")
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    bookCollection
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: LibraryBookItem.self) { book in
                ReaderContainerView(book: book)
            }
            .toolbar(isPushingReader ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !isPushingReader { toolbarContent }
            }
            .refreshable {
                await viewModel.refresh()
                await checkForBookSourceUpdates()
            }
            .task {
                await viewModel.loadBooks()
                // Load collections eagerly for context menu "Add to Collection" (bug #85)
                let persistence = PersistenceActor(modelContainer: modelContext.container)
                collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
            }
            // Feature #47 WI-6: row tap on a non-`.local` row → kick
            // off lazy download. The notification is posted from
            // `openBook(_:)` (LibraryView.swift:openBook) when the
            // user taps a remote-only / failed row. We look up the
            // matching book in viewModel.books, build a request via
            // saved Keychain credentials, and call enqueue. Errors
            // surface as the existing viewModel.errorMessage banner.
            .onReceive(NotificationCenter.default.publisher(for: .libraryRowTappedWhileNotLocal)) { notification in
                log.info("rowTap observer fired")
                guard let key = notification.userInfo?["fingerprintKey"] as? String else {
                    log.error("rowTap observer: missing fingerprintKey in userInfo")
                    return
                }
                guard let book = viewModel.books.first(where: { $0.fingerprintKey == key }) else {
                    log.error("rowTap observer: book not found in viewModel.books for key=\(key, privacy: .public)")
                    return
                }
                guard book.needsDownload else {
                    log.error("rowTap observer: book.needsDownload=false for fileState=\(book.fileState.rawValue, privacy: .public)")
                    return
                }
                guard let blobPath = book.blobPath else {
                    log.error("rowTap observer: book.blobPath is nil for \(key, privacy: .public)")
                    return
                }
                guard let coordinator = lazyDownloadCoordinator else {
                    log.error("rowTap observer: lazyDownloadCoordinator is nil from Environment")
                    return
                }
                guard let policy = webDAVNetworkPolicy else {
                    log.error("rowTap observer: webDAVNetworkPolicy is nil from Environment")
                    return
                }
                log.info("rowTap observer: all guards passed; coordinator + policy + blobPath OK")
                // fingerprintKey shape: "<format>:<sha256>:<byteCount>"
                let parts = book.fingerprintKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3,
                      let bytes = Int64(parts[2]) else { return }
                let sha = String(parts[1])
                let ext = (BookFormat(rawValue: book.format)?.fileExtensions.first) ?? book.format
                let builder: WebDAVDownloadRequestBuilder
                do {
                    builder = try WebDAVProviderFactory.makeRequestBuilder()
                } catch {
                    viewModel.setError("Cannot start download: \(error.localizedDescription)")
                    return
                }
                let result = coordinator.enqueue(
                    fingerprintKey: book.fingerprintKey,
                    blobPath: blobPath,
                    expectedSHA256: sha,
                    expectedByteCount: bytes,
                    originalExtension: ext,
                    requestBuilder: builder,
                    policy: policy
                )
                switch result {
                case .deferredWiFi:
                    viewModel.setError("Wi-Fi only — turn on the toggle in Backup settings to allow cellular.")
                case .notReady:
                    viewModel.setError("Lazy-download coordinator unavailable.")
                case .taskDescriptionEncodeFailed:
                    viewModel.setError("Internal error encoding download task.")
                case .started:
                    // Surface the sheet so the user sees progress.
                    bookForDownloadSheet = book
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerDidClose)) { notification in
                // Bug #45 v4: Update in-memory lastReadAt and re-sort immediately.
                // Do NOT call loadBooks() — it re-fetches from DB before
                // recomputeStats() commits, overwriting the in-memory fix.
                if let key = notification.object as? String {
                    viewModel.markBookAsJustRead(fingerprintKey: key)
                } else {
                    Task { await viewModel.refresh(force: true) }
                }
            }
            // Bug #115 (#47 WI-4b): when the lazy-download finalizer flips
            // a row from `.remoteOnly` to `.local`, refresh the library so
            // the row reflects the new state immediately. Without this,
            // the picker-restored row stays gray until app relaunch even
            // though the file has been downloaded and the DB row updated.
            // Force-refresh bypasses the 5s throttle — a single tap-driven
            // download isn't a polling burst.
            .onReceive(NotificationCenter.default.publisher(for: .bookFileStateDidChange)) { _ in
                Task { await viewModel.refresh(force: true) }
            }
            #if DEBUG
            // Feature #44 DebugBridge — vreader-debug://open posts this so
            // automated tests can navigate to a specific book without
            // tapping. The bridge has already verified the book exists in
            // persistence. We refresh viewModel.books FIRST so a rapid
            // seed → open sequence finds the freshly-imported book — the
            // bridge serializes its own commands but does not wait for
            // SwiftUI to propagate libraryChanged refreshes.
            .onReceive(NotificationCenter.default.publisher(for: .debugBridgeOpenBook)) { notification in
                guard let key = notification.userInfo?["fingerprintKey"] as? String else { return }
                Task {
                    await viewModel.loadBooks()
                    guard let book = viewModel.books.first(where: { $0.fingerprintKey == key })
                    else { return }
                    isPushingReader = true
                    navigationPath.append(book)
                }
            }
            // The bridge's reset/seed mutate SwiftData directly, bypassing
            // LibraryViewModel's import path. Refresh the in-memory books
            // array so the UI reflects the new state for snapshot/observe
            // consumers that don't go through .onReceive(openBook).
            .onReceive(NotificationCenter.default.publisher(for: .debugBridgeLibraryChanged)) { _ in
                Task { await viewModel.refresh(force: true) }
            }
            #endif
            // Reset toolbar visibility when returning from reader (bug #72)
            .onChange(of: navigationPath) { _, newPath in
                if newPath.isEmpty { isPushingReader = false }
            }
            .alert("Error", isPresented: hasError) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Delete Book",
                isPresented: .init(
                    get: { bookToDelete != nil },
                    set: { if !$0 { bookToDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { bookToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        let key = book.fingerprintKey
                        bookToDelete = nil
                        Task { await viewModel.deleteBook(fingerprintKey: key) }
                    }
                }
            } message: {
                if let book = bookToDelete {
                    Text("Are you sure you want to delete \"\(book.title)\"? This cannot be undone.")
                }
            }
            .sheet(item: $bookForInfo) { book in
                BookInfoSheet(book: book)
            }
            .sheet(item: $bookToShare) { book in
                ShareSheet(book: book)
            }
            .sheet(item: $bookForDownloadSheet) { book in
                BookDownloadSheet(book: book, presentedBook: $bookForDownloadSheet)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingAIChat) {
                NavigationStack {
                    AIChatView(viewModel: resolvedGeneralChatVM)
                        .navigationTitle("AI Chat")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") {
                                    isShowingAIChat = false
                                }
                                .accessibilityIdentifier("aiChatDoneButton")
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingOPDSCatalogs) {
                NavigationStack {
                    OPDSCatalogListView()
                        .navigationTitle("OPDS Catalogs")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") {
                                    isShowingOPDSCatalogs = false
                                }
                                .accessibilityIdentifier("opdsCatalogsDoneButton")
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingCollections) {
                CollectionSidebar(
                    activeFilter: $activeFilter,
                    collections: collectionRecords,
                    allTags: allTags,
                    allSeries: allSeries,
                    onCreateCollection: { name in
                        let persistence = PersistenceActor(modelContainer: modelContext.container)
                        _ = try? await persistence.createCollection(name: name)
                        collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
                    },
                    onDeleteCollection: { name in
                        // Bug #129: propagate the throw so CollectionSidebar
                        // can surface failures via its existing alert path.
                        // Refresh the records list either way (success or
                        // failure) so the sidebar reflects current SwiftData
                        // truth even on error.
                        let persistence = PersistenceActor(modelContainer: modelContext.container)
                        defer {
                            Task { @MainActor in
                                collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
                            }
                        }
                        try await persistence.deleteCollection(name: name)
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .opdsBookDownloaded)) { notification in
                if let url = notification.userInfo?["url"] as? URL {
                    Task { await viewModel.importFiles([url]) }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: Self.importableTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await viewModel.importFiles(urls) }
                case .failure(let error):
                    viewModel.setError(ErrorMessageAuditor.sanitize(error))
                }
            }
            .photosPicker(
                isPresented: $isShowingCoverPicker,
                selection: $coverPickerItem,
                matching: .images
            )
            // Present picker after bookForCover is set (waits for context menu dismiss). (bug #80)
            .onChange(of: bookForCover) { _, newBook in
                if newBook != nil {
                    isShowingCoverPicker = true
                }
            }
            .onChange(of: coverPickerItem) { _, newItem in
                guard let item = newItem, let book = bookForCover else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        try? CustomCoverStore.saveCover(image, for: book.fingerprintKey)
                        coverVersion += 1
                    }
                    coverPickerItem = nil
                    bookForCover = nil
                    isShowingCoverPicker = false
                }
            }
        }
    }

    // MARK: - Constants

    private static let importableTypes: [UTType] = {
        var types: [UTType] = [.epub, .pdf, .plainText]
        if let md = UTType("net.daringfireball.markdown") {
            types.append(md)
        }
        // AZW3/MOBI — no system UTType, use generic binary data
        // Users can import .azw3/.mobi files via "All Files" or share sheet
        if let mobi = UTType("com.amazon.mobi8-ebook") {
            types.append(mobi)
        }
        // Accept generic data so .azw3/.mobi/.azw aren't filtered out
        types.append(.data)
        return types
    }()

    // MARK: - Subviews

    @ViewBuilder
    private var bookCollection: some View {
        switch viewModel.viewMode {
        case .grid:
            gridView
        case .list:
            listView
        }
    }

    /// Bug #155: books visible under the active sidebar filter. The grid and
    /// list bodies iterate this rather than `viewModel.books` directly so that
    /// selecting a collection in `CollectionSidebar` actually narrows the
    /// shown list. Computing here (not in the view model) keeps the filter a
    /// pure view-state concern — the model still owns the full set + sort.
    private var displayedBooks: [LibraryBookItem] {
        viewModel.books.filter { activeFilter.matches($0) }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 16
            ) {
                ForEach(displayedBooks) { book in
                    Button {
                        openBook(book)
                    } label: {
                        BookCardView(book: book, coverVersion: coverVersion)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        bookContextMenu(for: book)
                    }
                    .accessibilityIdentifier("bookCard_\(book.fingerprintKey)")
                    .accessibilityLabel(AccessibilityFormatters.accessibleBookDescription(
                        title: book.title,
                        author: book.author,
                        format: book.format,
                        readingTimeSeconds: book.totalReadingSeconds
                    ))
                    .accessibilityHint("Double tap to open")
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List {
            ForEach(displayedBooks) { book in
                Button {
                    openBook(book)
                } label: {
                    BookRowView(book: book, coverVersion: coverVersion)
                }
                .contextMenu {
                    bookContextMenu(for: book)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    deleteButton(for: book)
                }
                .accessibilityIdentifier("bookRow_\(book.fingerprintKey)")
                .accessibilityLabel(AccessibilityFormatters.accessibleBookDescription(
                    title: book.title,
                    author: book.author,
                    format: book.format,
                    readingTimeSeconds: book.totalReadingSeconds
                ))
                .accessibilityHint("Double tap to open")
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Your Library is Empty")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import books to start reading. Supports EPUB, PDF, TXT, and Markdown formats.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                isShowingImporter = true
            } label: {
                Label("Import Books", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("importBooksButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyLibraryState")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsToolbarButton")
        }

        if let syncMonitor {
            ToolbarItem(placement: .topBarLeading) {
                SyncStatusView(monitor: syncMonitor)
            }
        }

        if isAIChatAvailable {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAIChat = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .accessibilityLabel("AI Chat")
                .accessibilityIdentifier("aiChatToolbarButton")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    let persistence = PersistenceActor(modelContainer: modelContext.container)
                    collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
                    allTags = (try? await persistence.fetchAllTags()) ?? []
                    allSeries = (try? await persistence.fetchAllSeriesNames()) ?? []
                    isShowingCollections = true
                }
            } label: {
                Image(systemName: "folder")
            }
            .accessibilityLabel("Collections")
            .accessibilityIdentifier("collectionsToolbarButton")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingOPDSCatalogs = true
            } label: {
                Image(systemName: "globe")
            }
            .accessibilityLabel("OPDS Catalogs")
            .accessibilityIdentifier("opdsCatalogsToolbarButton")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingImporter = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Import books")
            .accessibilityIdentifier("importBooksToolbarButton")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.toggleViewMode()
            } label: {
                Image(systemName: viewModel.viewMode == .grid
                    ? "list.bullet"
                    : "square.grid.2x2")
            }
            .accessibilityLabel(viewModel.viewMode == .grid
                ? "Switch to list view"
                : "Switch to grid view")
            .accessibilityIdentifier("viewModeToggle")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort By", selection: $viewModel.sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort books")
            .accessibilityIdentifier("sortPicker")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func bookContextMenu(for book: LibraryBookItem) -> some View {
        Button {
            bookForInfo = book
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        // Share gated by feature #47 WI-5: only `.local` rows have
        // bytes to share. Remote-only / downloading / failed / missing
        // rows omit the menu item rather than showing it disabled —
        // less noise in the menu, fewer "why is this greyed out?"
        // questions.
        if book.canShare {
            Button {
                bookToShare = book
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        Divider()

        Button {
            bookForCover = book
        } label: {
            Label("Set Cover", systemImage: "photo")
        }

        if CustomCoverStore.hasCover(for: book.fingerprintKey) {
            Button(role: .destructive) {
                try? CustomCoverStore.removeCover(for: book.fingerprintKey)
                coverVersion += 1
            } label: {
                Label("Remove Cover", systemImage: "photo.badge.minus")
            }
        }

        Divider()

        // Add to Collection submenu (bug #85)
        Menu {
            if collectionRecords.isEmpty {
                Text("No collections yet")
            } else {
                ForEach(collectionRecords, id: \.name) { collection in
                    Button {
                        Task {
                            let persistence = PersistenceActor(modelContainer: modelContext.container)
                            try? await persistence.addBookToCollection(
                                bookFingerprintKey: book.fingerprintKey,
                                collectionName: collection.name
                            )
                            collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
                            // Bug #155: also refresh viewModel.books so the
                            // in-memory `LibraryBookItem.collectionNames` is
                            // current — otherwise tapping the collection in
                            // the sidebar filter shows an empty list because
                            // the stale row still has `collectionNames: []`.
                            await viewModel.refresh(force: true)
                        }
                    } label: {
                        Label(collection.name, systemImage: "folder")
                    }
                }
            }
        } label: {
            Label("Add to Collection", systemImage: "folder.badge.plus")
        }

        Divider()

        deleteButton(for: book)
    }

    private func deleteButton(for book: LibraryBookItem) -> some View {
        Button(role: .destructive) {
            bookToDelete = book
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - AI Chat

    /// Whether the AI chat button should be visible in the toolbar.
    private var isAIChatAvailable: Bool {
        AIReaderAvailability.isAvailable(
            featureFlags: FeatureFlags.shared,
            keychainService: KeychainService(),
            consentManager: AIConsentManager()
        )
    }

    /// Bug #93: lazily resolves the general-chat VM, caching it in `@State`
    /// so it survives sheet dismiss/re-present. SwiftUI re-runs the
    /// `.sheet { ... }` closure each time the sheet is shown — the
    /// pre-fix path always produced a fresh VM with empty messages, so
    /// closing and reopening the sheet wiped multi-turn history.
    /// Mirrors the existing `resolvedAICoordinator` lazy-cache pattern
    /// in `ReaderContainerView`. The async dispatch keeps SwiftUI from
    /// observing a state mutation during view body evaluation.
    private var resolvedGeneralChatVM: AIChatViewModel {
        if let existing = generalChatVM { return existing }
        let vm = makeGeneralChatViewModel()
        DispatchQueue.main.async {
            generalChatVM = vm
        }
        return vm
    }

    /// Creates an AIChatViewModel for general (non-book) chat.
    ///
    /// Feature #50 WI-5: AIService now dispatches on the active
    /// `ProviderProfile` via `ProviderProfileStore.shared`. The shared
    /// store is mandatory in production (Gate-2 round-2 finding [2]) —
    /// constructing a separate store would re-introduce lost-update races
    /// across the Settings VM, AIService actor, and the in-reader picker.
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
    /// Populates `booksWithUpdates` with fingerprint keys of updated books.
    private func checkForBookSourceUpdates() async {
        // TODO: Wire up once books track their source URL and chapter count.
        // For now, this is a no-op infrastructure hook for pull-to-refresh.
        // When book-to-source linking is implemented, iterate over source-linked
        // books and call UpdateChecker.checkForUpdates() for each.
    }

    // MARK: - Navigation (bug #72)

    /// Hides the library toolbar before pushing to the reader,
    /// eliminating the toolbar flash during the push animation.
    /// Feature #47 WI-5 gate: only `.local` rows open the reader.
    /// Tapping a non-`.local` row posts a notification that the
    /// download sheet (WI-6) listens for; until that ships, taps on
    /// remote rows are silent so the user doesn't see a broken
    /// reader-open path.
    private func openBook(_ book: LibraryBookItem) {
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

    // MARK: - Helpers

    private var hasError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}
