// Purpose: Feature #60 WI-9 — the grid / list body, empty state, and
// per-book context menu for the re-skinned `LibraryView`. Split out of
// `LibraryView.swift` to keep each file near the ~300-line guideline
// (rule 50 §9). The split mirrors `ReaderContainerView` ↔
// `ReaderContainerView+Sheets.swift`.
//
// Behavior is preserved verbatim from the pre-#60 `LibraryView`: the
// 3-column grid, the rounded list card, list-mode swipe-to-delete, the
// empty-state CTA, and the Info / Share / Set-Cover / Remove-Cover /
// Add-to-Collection / Delete context menu (feature #47 share gating +
// bug #85 collections submenu + bug #155 in-memory refresh).
//
// Key decision: list mode is a native `List` (insetGrouped style) so
// `.swipeActions` swipe-to-delete survives the re-skin. `List` cannot
// nest inside a `ScrollView`, so the Continue-reading rail + the "All
// books" sort header are list rows at the top of the `List` in list
// mode. Grid mode keeps a `ScrollView` + `LazyVGrid`.
//
// @coordinates-with: LibraryView.swift, BookCardView.swift,
//   BookRowView.swift, LibrarySectionHeader.swift, ContinueReadingRail.swift,
//   LibraryCardTokens.swift, CustomCoverStore.swift,
//   AccessibilityFormatters.swift, PersistenceActor+Collections.swift

import SwiftUI

extension LibraryView {

    // MARK: - Grid body

    /// 3-column generative-cover grid — design `GridView`'s
    /// `repeat(3, 1fr)` with the design's `22px 14px` gaps.
    var gridBody: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 14),
                count: 3
            ),
            spacing: 22
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
        .padding(.horizontal, LibraryCardTokens.shellContentPadding)
    }

    // MARK: - List body

    /// Rounded white list card — design `ListView`. A native `List`
    /// with the inset-grouped style gives the design's 20pt-radius
    /// `#fff` card + hairline dividers natively, and — unlike a
    /// `LazyVStack` — keeps `.swipeActions` swipe-to-delete working.
    /// The rail + sort header ride as leading rows because `List`
    /// cannot nest inside a `ScrollView`.
    var listBody: some View {
        List {
            if hasContinueReadingRail {
                continueReadingRail
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            LibrarySectionHeader(sortOrder: $viewModel.sortOrder)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section {
                ForEach(displayedBooks) { book in
                    listRow(for: book)
                }
            }
            .listRowBackground(LibraryCardTokens.listCardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// One list row — the WI-8 `BookRowView` wrapped with the open tap,
    /// the context menu, and the trailing swipe-to-delete action.
    private func listRow(for book: LibraryBookItem) -> some View {
        Button {
            openBook(book)
        } label: {
            BookRowView(book: book, coverVersion: coverVersion)
        }
        .buttonStyle(.plain)
        .contextMenu {
            bookContextMenu(for: book)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                bookToDelete = book
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("bookRowDelete_\(book.fingerprintKey)")
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

    /// Whether the Continue-reading rail should render — used by
    /// `listBody` to decide whether to emit the rail row.
    private var hasContinueReadingRail: Bool {
        guard containerModel.showsContinueReadingRail else { return false }
        return !containerModel.continueReadingBooks(in: viewModel.books).isEmpty
    }

    // MARK: - Empty state

    /// Empty-library onboarding CTA — re-skinned to the warm-paper
    /// palette + Source Serif 4 headline.
    var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(LibraryCardTokens.subText)
                .accessibilityHidden(true)

            Text("Your Library is Empty")
                .font(LibraryCardTokens.serifTitleFont(size: 22))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)

            Text("Import books to start reading. Supports EPUB, PDF, TXT, and Markdown formats.")
                .font(.body)
                .foregroundStyle(LibraryCardTokens.subText)
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
            .tint(LibraryCardTokens.accent)
            .accessibilityIdentifier("importBooksButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyLibraryState")
    }

    // MARK: - Context menu

    /// Per-book long-press context menu — Info / Share / Set Cover /
    /// Remove Cover / Add to Collection / Delete. Preserved verbatim
    /// from the pre-#60 `LibraryView`.
    @ViewBuilder
    func bookContextMenu(for book: LibraryBookItem) -> some View {
        Button {
            bookForInfo = book
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        // Share gated by feature #47 WI-5: only `.local` rows have
        // bytes to share. Non-`.local` rows omit the item rather than
        // showing it disabled.
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
                        addBook(book, toCollection: collection.name)
                    } label: {
                        Label(collection.name, systemImage: "folder")
                    }
                }
            }
        } label: {
            Label("Add to Collection", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            bookToDelete = book
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Adds a book to a collection, then refreshes both the collection
    /// records and `viewModel.books` so the in-memory
    /// `LibraryBookItem.collectionNames` is current (bug #155).
    private func addBook(_ book: LibraryBookItem, toCollection name: String) {
        Task {
            let persistence = PersistenceActor(modelContainer: modelContext.container)
            try? await persistence.addBookToCollection(
                bookFingerprintKey: book.fingerprintKey,
                collectionName: name
            )
            collectionRecords = (try? await persistence.fetchAllCollections()) ?? []
            await viewModel.refresh(force: true)
        }
    }
}
