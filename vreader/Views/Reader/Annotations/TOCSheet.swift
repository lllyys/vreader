// Purpose: Feature #62 WI-3 — the navigation half of the
// annotations-panel split: Contents + Bookmarks.
//
// `TOCSheet` is the "leave the current page" sheet. It wraps the shared
// `ReaderSheetChrome` with `title` set to the book title at runtime
// (the design's `TOCSheetV2` titles with the book name), a 2-tab
// segmented control with per-tab count badges, and the design-faithful
// `TOCContentsRow` / `TOCBookmarkRow` rows (`TOCSheetRows.swift`).
//
// The sheet OWNS its bookmark loading — a `BookmarkListViewModel`
// constructed in its own `.task` — so the Bookmarks count badge is live
// the moment the sheet appears even when it opens on the Contents tab
// (Gate-2 round-2 finding 5). The current-chapter determination reuses
// `TOCListView`'s `activeEntryIndex` matching logic, lifted here.
//
// Empty states use the shared `AnnotationsEmptyStateView` (WI-2) — the
// Contents-empty state carries an "Open Search" CTA.
//
// @coordinates-with: TOCSheetRows.swift, AnnotationsEmptyStateView.swift,
//   AnnotationsEmptyStateArt.swift, AnnotationsSheetRoute.swift,
//   ReaderSheetChrome.swift, BookmarkListViewModel.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`

import SwiftUI
import SwiftData

/// The navigation annotations sheet — Contents + Bookmarks.
struct TOCSheet: View {
    let bookTitle: String
    let bookFingerprintKey: String
    let modelContainer: ModelContainer
    let tocEntries: [TOCEntry]
    let currentLocator: Locator?
    let theme: ReaderThemeV2
    /// Contents-empty CTA — opens the reader search sheet.
    let onOpenSearch: () -> Void
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    @State private var selectedTab: TOCSheetTab
    /// Sheet-owned bookmark model — loaded in `.task` so the Bookmarks
    /// badge is live on appear regardless of the initial tab.
    @State private var bookmarkVM: BookmarkListViewModel?

    init(
        bookTitle: String,
        bookFingerprintKey: String,
        modelContainer: ModelContainer,
        tocEntries: [TOCEntry],
        currentLocator: Locator?,
        theme: ReaderThemeV2,
        initialTab: TOCSheetTab = .contents,
        onNavigate: @escaping (Locator) -> Void,
        onOpenSearch: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.bookTitle = bookTitle
        self.bookFingerprintKey = bookFingerprintKey
        self.modelContainer = modelContainer
        self.tocEntries = tocEntries
        self.currentLocator = currentLocator
        self.theme = theme
        self.onNavigate = onNavigate
        self.onOpenSearch = onOpenSearch
        self.onDismiss = onDismiss
        self._selectedTab = State(initialValue: initialTab)
    }

    // MARK: - Body

    var body: some View {
        ReaderSheetChrome(theme: theme, title: bookTitle, onClose: onDismiss) {
            VStack(spacing: 0) {
                segmentedControl
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                ScrollView {
                    switch selectedTab {
                    case .contents:  contentsBody
                    case .bookmarks: bookmarksBody
                    }
                }
            }
        }
        .task {
            guard bookmarkVM == nil else { return }
            let vm = BookmarkListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: PersistenceActor(modelContainer: modelContainer)
            )
            await vm.loadBookmarks()
            bookmarkVM = vm
        }
    }

    // MARK: - Segmented control

    @ViewBuilder
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(TOCSheetTab.allCases) { tab in
                segmentButton(tab)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(theme.isDark ? 0.06 : 0.05))
        )
    }

    @ViewBuilder
    private func segmentButton(_ tab: TOCSheetTab) -> some View {
        let isSelected = tab == selectedTab
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(theme.inkColor))
                Text("\(badgeCount(tab))")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.primary.opacity(theme.isDark ? 0.06 : 0.05))
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? (theme.isDark
                             ? Color(red: 0x3a / 255, green: 0x35 / 255, blue: 0x30 / 255)
                             : Color.white)
                          : Color.clear)
                    .shadow(
                        color: .black.opacity(isSelected ? 0.08 : 0),
                        radius: 1, y: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            tab == .contents ? "tocSheetContentsTab" : "tocSheetBookmarksTab"
        )
    }

    private func badgeCount(_ tab: TOCSheetTab) -> Int {
        switch tab {
        case .contents:  return contentsBadgeCount
        case .bookmarks: return bookmarksBadgeCount
        }
    }

    // MARK: - Contents body

    @ViewBuilder
    private var contentsBody: some View {
        if tocEntries.isEmpty {
            AnnotationsEmptyStateView(
                theme: theme,
                accessibilityIdentifier: "tocEmptyState",
                art: AnyView(EmptyTOCArt(theme: theme)),
                title: "No table of contents",
                body: "This book doesn't ship a TOC. Use the scrubber to flip pages, or Search to jump to a passage.",
                ctaLabel: "Open Search",
                ctaSystemImage: "magnifyingglass",
                onCTA: { onDismiss(); onOpenSearch() }
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(tocEntries.enumerated()), id: \.element.id) { index, entry in
                    TOCContentsRow(
                        theme: theme,
                        chapterOrdinal: index + 1,
                        title: entry.title,
                        page: entry.locator.page,
                        isCurrent: index == activeEntryIndex,
                        onTap: { onNavigate(entry.locator); onDismiss() }
                    )
                    .accessibilityIdentifier("tocRow-\(entry.id)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Bookmarks body

    @ViewBuilder
    private var bookmarksBody: some View {
        let bookmarks = bookmarkVM?.bookmarks ?? []
        if bookmarks.isEmpty {
            AnnotationsEmptyStateView(
                theme: theme,
                accessibilityIdentifier: "bookmarkEmptyState",
                art: AnyView(EmptyBookmarkArt(theme: theme)),
                title: "No bookmarks yet",
                body: "Tap the bookmark icon in the top bar to save your place. Bookmarks let you jump back instantly."
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                    TOCBookmarkRow(
                        theme: theme,
                        preview: bookmarkPreview(bookmark),
                        subtitle: bookmarkSubtitle(bookmark),
                        showsSeparator: index < bookmarks.count - 1,
                        onTap: { onNavigate(bookmark.locator); onDismiss() }
                    )
                    .accessibilityIdentifier("tocBookmarkRow-\(bookmark.bookmarkId)")
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Bookmark display helpers

    /// The 1-line italic preview — the bookmark title, the quoted text,
    /// or a generic fallback.
    private func bookmarkPreview(_ bookmark: BookmarkRecord) -> String {
        if let title = bookmark.title, !title.isEmpty { return title }
        if let quote = bookmark.locator.textQuote, !quote.isEmpty { return quote }
        return "Bookmark"
    }

    /// The `· p. N · date` sub-line. Page is included only when the
    /// locator carries one (degrades for EPUB/TXT).
    private func bookmarkSubtitle(_ bookmark: BookmarkRecord) -> String {
        var parts: [String] = []
        if let page = bookmark.locator.page { parts.append("p. \(page + 1)") }
        parts.append(Self.dateFormatter.string(from: bookmark.createdAt))
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - Current-chapter matching (lifted from TOCListView)

    /// Index of the active TOC entry for `currentLocator` — matched by
    /// `charOffsetUTF16` (TXT/MD), `page` (PDF), or `href` (EPUB).
    /// Picks the last entry at or before the current position. Lifted
    /// verbatim from `TOCListView.activeEntryIndex` (the logic is
    /// correct; only the row rendering is new — Gate-2 round-2 finding 1).
    private var activeEntryIndex: Int? {
        guard let loc = currentLocator else { return nil }

        if let currentOffset = loc.charOffsetUTF16 {
            var best: Int?
            for (i, entry) in tocEntries.enumerated() {
                if let o = entry.locator.charOffsetUTF16, o <= currentOffset { best = i }
            }
            return best
        }
        if let currentPage = loc.page {
            var best: Int?
            for (i, entry) in tocEntries.enumerated() {
                if let p = entry.locator.page, p <= currentPage { best = i }
            }
            return best
        }
        if let currentHref = loc.href {
            var best: Int?
            for (i, entry) in tocEntries.enumerated() {
                if entry.locator.href == currentHref { best = i }
            }
            return best
        }
        return nil
    }

    // MARK: - Badge counts

    /// The Contents tab badge — the TOC entry count.
    var contentsBadgeCount: Int { tocEntries.count }

    /// The Bookmarks tab badge — the loaded bookmark count (0 before
    /// the sheet-owned load resolves).
    var bookmarksBadgeCount: Int { bookmarkVM?.bookmarks.count ?? 0 }
}

// MARK: - Testing hooks

#if DEBUG
extension TOCSheet {
    /// The title `ReaderSheetChrome` is built with — the book title.
    var sheetChromeTitleForTesting: String { bookTitle }

    /// The seeded / currently-selected tab.
    var selectedTabForTesting: TOCSheetTab { selectedTab }

    /// The lifted `activeEntryIndex` result, for the current-chapter test.
    var activeEntryIndexForTesting: Int? { activeEntryIndex }

    /// True when the Contents body renders the empty state.
    var contentsIsEmpty: Bool { tocEntries.isEmpty }

    /// True when the Bookmarks body renders the empty state.
    var bookmarksIsEmpty: Bool { (bookmarkVM?.bookmarks ?? []).isEmpty }

    /// Runs the exact bookmark-load the sheet's `.task` runs and returns
    /// the loaded count — for the Bookmarks-count-badge test. Returns the
    /// count rather than mutating `@State` because `@State` is not
    /// observable outside a render tree; the sheet's `.task` + render
    /// path is what feeds the live badge in the app.
    func loadBookmarkCountForTesting() async -> Int {
        let vm = BookmarkListViewModel(
            bookFingerprintKey: bookFingerprintKey,
            store: PersistenceActor(modelContainer: modelContainer)
        )
        await vm.loadBookmarks()
        return vm.bookmarks.count
    }

    /// Invokes the Contents-empty "Open Search" CTA — dismiss then search.
    func invokeContentsEmptyCTAForTesting() {
        onDismiss()
        onOpenSearch()
    }
}
#endif
