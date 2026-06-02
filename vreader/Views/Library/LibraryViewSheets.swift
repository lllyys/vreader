// Purpose: Feature #60 WI-9 — the sheet / alert / importer modifier
// chain for the re-skinned `LibraryView`. Extracted into a dedicated
// `ViewModifier` because applying all of these inline pushes the
// `LibraryView` body past the Swift type-checker's complexity ceiling.
//
// Behavior is preserved verbatim from the pre-#60 `LibraryView`: the
// delete-confirmation alert, the error alert, the Info / Share /
// Download / Settings / AI-chat / OPDS-catalog / collections sheets,
// the `.fileImporter`, the custom-cover picker (feature #61 WI-2 — now
// driven by `CoverPickCoordinator` via `.coverPicker`), and the
// OPDS-download notification observer that re-imports a downloaded
// catalog book.
//
// @coordinates-with: LibraryView.swift, LibraryViewModel.swift,
//   BookInfoSheet.swift, ShareSheet.swift, BookDownloadSheet.swift,
//   SettingsView.swift, AIChatView.swift, OPDSCatalogListView.swift,
//   CollectionSidebar.swift, CoverPickCoordinator.swift

import SwiftUI

/// The sheet / alert / importer chain for the re-skinned `LibraryView`.
struct LibraryViewSheets: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    let viewModel: LibraryViewModel

    @Binding var bookToDelete: LibraryBookItem?
    @Binding var bookForInfo: LibraryBookItem?
    @Binding var bookToShare: LibraryBookItem?
    @Binding var bookForDownloadSheet: LibraryBookItem?
    @Binding var isShowingImporter: Bool
    @Binding var isShowingSettings: Bool
    @Binding var isShowingAIChat: Bool
    @Binding var isShowingOPDSCatalogs: Bool
    @Binding var isShowingCollections: Bool
    @Binding var activeFilter: LibraryFilter
    @Binding var collectionRecords: [CollectionRecord]
    @Binding var allTags: [String]
    @Binding var allSeries: [String]
    /// Coordinates the custom-cover PhotosPicker flow (feature #61 WI-2).
    let coverPickCoordinator: CoverPickCoordinator
    /// Resolved lazily by the parent so multi-turn chat history survives
    /// sheet dismiss / re-present (bug #93).
    let resolvedGeneralChatVM: AIChatViewModel

    func body(content: Content) -> some View {
        content
            .modifier(LibraryAlerts(
                viewModel: viewModel,
                bookToDelete: $bookToDelete
            ))
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
                aiChatSheet
            }
            .sheet(isPresented: $isShowingOPDSCatalogs) {
                opdsCatalogsSheet
            }
            .sheet(isPresented: $isShowingCollections) {
                collectionsSheet
            }
            .onReceive(NotificationCenter.default.publisher(for: .opdsBookDownloaded)) { notification in
                if let url = notification.userInfo?["url"] as? URL {
                    Task { await viewModel.importFiles([url]) }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: LibraryView.importableTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await viewModel.importFiles(urls) }
                case .failure(let error):
                    viewModel.setError(ErrorMessageAuditor.sanitize(error))
                }
            }
            .coverPicker(coverPickCoordinator)
    }

    // MARK: - Sheets

    private var aiChatSheet: some View {
        NavigationStack {
            AIChatView(viewModel: resolvedGeneralChatVM, theme: Self.generalChatTheme)
                .navigationTitle("AI Chat")
                .navigationBarTitleDisplayMode(.inline)
                // Bug #310: pin the cream Paper sheet (the design's `ChatView`
                // surface) so the Paper-derived ink/sub tokens read. Without
                // this the general chat fell to the SYSTEM sheet, which is dark
                // in Dark Mode — making the (now theme-tokened) empty-state /
                // placeholder dark-on-dark. The reader AI panel already pins its
                // theme surface; this brings the Library general chat in line.
                .background(Color(Self.generalChatTheme.sheetSurfaceColor).ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            isShowingAIChat = false
                        }
                        .accessibilityIdentifier("aiChatDoneButton")
                    }
                }
        }
        .preferredColorScheme(Self.generalChatTheme.isDark ? .dark : .light)
    }

    /// Bug #310: the general (no-book) AI chat has no reader theme to inherit,
    /// so it pins the default Paper identity — matching the design's cream
    /// `ChatView` surface and the per-book reader AI panel. `static` (not
    /// `private`) so a presenter-level regression test can pin the choice: a
    /// host that lets this fall to a dark-family surface would re-hide the
    /// dark-`sub` empty-state in Dark Mode (Codex Gate-4 Low).
    static var generalChatTheme: ReaderThemeV2 { .paper }

    private var opdsCatalogsSheet: some View {
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

    private var collectionsSheet: some View {
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
                // Bug #129: propagate the throw so CollectionSidebar can
                // surface failures via its existing alert path. Refresh
                // the records list either way (success or failure).
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
}

/// The delete-confirmation + error alerts — split into its own
/// modifier so the sheet chain above stays under the type-check ceiling.
private struct LibraryAlerts: ViewModifier {
    let viewModel: LibraryViewModel
    @Binding var bookToDelete: LibraryBookItem?

    func body(content: Content) -> some View {
        content
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
    }

    private var hasError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}
