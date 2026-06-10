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
// `TOCListView`'s `activeEntryIndex` matching logic, lifted here. The
// Contents list wraps a `ScrollViewReader` and auto-scrolls the active
// chapter into view on appear (Bug #248 restored what feature #62 WI-5
// dropped when it replaced the legacy `TOCListView`).
//
// Empty states use the shared `AnnotationsEmptyStateView` (WI-2) — the
// Contents-empty state carries an "Open Search" CTA. Both the Contents
// and Bookmarks empty states are gated on a load-completed flag
// (`tocDidLoad` / `bookmarksDidLoad`) so a tab tap during the
// still-in-flight load shows a neutral body, never a false empty state.
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
    /// True once the host's eager TOC build has completed. The Contents
    /// tab withholds its "No table of contents" empty state until this
    /// is set, so a Contents tap during the build does not flash a
    /// false empty state (mirrors `bookmarksDidLoad`).
    let tocDidLoad: Bool
    let currentLocator: Locator?
    /// Bug #313 r2: the book's full spine href order (EPUB only; empty for
    /// other formats) — lets the current-chapter match fall back to the
    /// nearest PRECEDING entry when the current spine item has no TOC entry.
    let spineHrefs: [String]
    let theme: ReaderThemeV2
    /// Contents-empty CTA — opens the reader search sheet.
    let onOpenSearch: () -> Void
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    // `@State` kept `internal` (not `private`) so `TOCSheet+Support.swift`
    // — the helpers / badge counts / DEBUG hooks extension — can read it.
    // Same cross-file-extension pattern `ReaderContainerView` uses for
    // its `+Sheets.swift` split.
    @State var selectedTab: TOCSheetTab
    /// Sheet-owned bookmark model — loaded in `.task` so the Bookmarks
    /// badge is live on appear regardless of the initial tab.
    @State var bookmarkVM: BookmarkListViewModel?
    /// True once the sheet-owned bookmark load has completed. Tracked
    /// separately from emptiness so the Bookmarks tab does not flash a
    /// false "No bookmarks yet" empty state on first paint while the
    /// load is still in flight (Gate-4 finding).
    @State var bookmarksDidLoad = false
    /// Feature #94 — the Contents-tab title filter query. Kept `internal`
    /// (not `private`) so the `TOCSheet+Filter.swift` extension can read
    /// it, same as `selectedTab` / `bookmarkVM` (Gate-2 round-2 Medium).
    @State var filterQuery = ""

    init(
        bookTitle: String,
        bookFingerprintKey: String,
        modelContainer: ModelContainer,
        tocEntries: [TOCEntry],
        tocDidLoad: Bool = true,
        currentLocator: Locator?,
        spineHrefs: [String] = [],
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
        self.tocDidLoad = tocDidLoad
        self.currentLocator = currentLocator
        self.spineHrefs = spineHrefs
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

                // Feature #94 Gate-2 H2 — the scroll is split BY TAB so the
                // Contents filter field can be PINNED (placed outside the
                // contents list's own scroll) while the Bookmarks tab keeps
                // its own scroll. The previous single outer `ScrollView`
                // wrapping both tabs would have scrolled the field away.
                switch selectedTab {
                case .contents:  contentsBody
                case .bookmarks: ScrollView { bookmarksBody }
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
            bookmarksDidLoad = true
        }
        // Root sheet identity — the migrated XCUITests query
        // `app.otherElements["tocSheet"]` to detect, audit, and dismiss
        // the sheet. Mirrors `HighlightsSheet`'s root identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tocSheet")
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
        if !tocEntries.isEmpty {
            // Feature #94 — the filter field is PINNED above the list
            // (outside `tocEntryList`'s inner `ScrollView`) so it stays put
            // while the chapter list scrolls (Gate-2 H2). It is shown only
            // when the book ships a TOC (per the design's no-TOC suppress).
            VStack(spacing: 0) {
                TOCFilterField(
                    theme: theme,
                    query: $filterQuery,
                    visibleCount: visibleEntries.count,
                    totalCount: tocEntries.count
                )
                // Feature #94 Gate-4: keep the current chapter reachable when
                // the query filters it out — the design's pinned "Reading" row.
                if let pinned = pinnedCurrentEntry {
                    PinnedCurrentRow(
                        theme: theme,
                        title: pinned.title,
                        page: Self.displayPage(pinned.locator.page),
                        onTap: { onDismiss(); onNavigate(pinned.locator) }
                    )
                }
                if isFilterNoMatch {
                    filterNoMatchBody
                } else {
                    tocEntryList
                }
            }
        } else if tocDidLoad {
            // Empty state shown only once the host's TOC build has
            // completed — a Contents tap during the build must not
            // flash a false "No table of contents" (mirrors the
            // bookmark `bookmarksDidLoad` gate).
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
            // Pre-load neutral body — the TOC build is in flight; the
            // design shows no loading affordance.
            Color.clear.frame(height: 1)
        }
    }

    // Feature #94: `tocEntryList` (the filtered chapter list + its inner
    // ScrollView + the auto-scroll ladder) lives in `TOCSheet+Filter.swift`
    // to keep this file under the ~300-line guideline (Gate-4 file-size fix).

    // MARK: - Bookmarks body

    @ViewBuilder
    private var bookmarksBody: some View {
        let bookmarks = bookmarkVM?.bookmarks ?? []
        if !bookmarks.isEmpty {
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
        } else if bookmarksDidLoad {
            // Empty state shown only once the sheet-owned load has
            // completed — avoids flashing a false "No bookmarks yet" on
            // first paint while the load is still in flight (Gate-4
            // finding).
            AnnotationsEmptyStateView(
                theme: theme,
                accessibilityIdentifier: "bookmarkEmptyState",
                art: AnyView(EmptyBookmarkArt(theme: theme)),
                title: "No bookmarks yet",
                body: "Tap the bookmark icon in the top bar to save your place. Bookmarks let you jump back instantly."
            )
        } else {
            // Pre-load neutral body — no empty state, no spinner (the
            // bookmark fetch is a fast indexed query; the design shows
            // no loading affordance).
            Color.clear.frame(height: 1)
        }
    }

    // Bookmark display helpers, current-chapter matching, badge counts,
    // and the DEBUG testing hooks live in `TOCSheet+Support.swift`.
}
