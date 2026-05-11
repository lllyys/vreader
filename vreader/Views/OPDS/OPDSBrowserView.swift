// Purpose: SwiftUI view for browsing OPDS catalog feeds.
// Supports navigation feeds (category browsing), acquisition feeds (book listings),
// search, pagination, and book download.
//
// Key decisions:
// - Uses NavigationStack for drill-down into subcategories.
// - Async loading with ProgressView during fetch.
// - Error state with retry button.
// - Download triggers import through BookImporter.
//
// @coordinates-with: OPDSClient.swift, OPDSModels.swift, OPDSEntryView.swift,
//   BookImporter.swift

import SwiftUI

/// Browsable OPDS catalog feed view.
struct OPDSBrowserView: View {
    let catalogURL: URL
    let catalogName: String
    let credentials: OPDSCredentials?

    @State private var feed: OPDSFeed?
    // Bug #170 / GH #529 — Seed `isLoading = true` so the spinner renders
    // on the very first body evaluation, before `loadFeed` actually flips
    // the flag. Without this, the body's empty-Group branch (isLoading ==
    // false && feed == nil && errorMessage == nil) renders a blank view in
    // the window between view-appear and the load task starting.
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    // Bug #170 / GH #529 — Fire-once flag for the initial fetch. Flipped
    // synchronously in `.onAppear` BEFORE the Task launches, so a second
    // `.onAppear` (e.g., the user pushes a sub-feed then backs out, or
    // SwiftUI re-runs onAppear during a layout pass) cannot start a
    // duplicate page-1 fetch that would race the explicit `loadMoreRow`
    // append=true path and overwrite the merged feed (Gate-4 round-1
    // audit finding [1]).
    @State private var hasStartedInitialLoad = false

    private let client = OPDSClient()

    init(
        catalogURL: URL,
        catalogName: String,
        credentials: OPDSCredentials? = nil
    ) {
        self.catalogURL = catalogURL
        self.catalogName = catalogName
        self.credentials = credentials
    }

    var body: some View {
        Group {
            if isLoading && feed == nil {
                ProgressView("Loading catalog...")
                    .accessibilityIdentifier("opdsCatalogLoading")
            } else if let error = errorMessage {
                errorState(error)
            } else if let feed = feed {
                feedContent(feed)
            }
        }
        .navigationTitle(feed?.title ?? catalogName)
        .navigationBarTitleDisplayMode(.inline)
        // Bug #170 / GH #529 — `.onAppear` instead of `.task`. In the nested
        // presentation chain `.sheet → NavigationStack → NavigationLink
        // destination` (LibraryView → OPDSCatalogListView → OPDSBrowserView),
        // `.task` was firing-and-immediately-cancelling on iOS 26, leaving
        // the view in its initial state (no spinner, no entries, no error).
        // `.onAppear` is unaffected; the wrapped `Task` outlives the
        // dispatching frame and runs `loadFeed` to completion. The OPDS
        // catalog fetch is short-lived, so we don't need `.task`'s
        // auto-cancel-on-disappear behaviour.
        //
        // Fire-once via `hasStartedInitialLoad` (flipped synchronously
        // before the Task launches). Retries on error must come from the
        // explicit Retry button in `errorState` — `.onAppear` does NOT
        // auto-retry, which prevents infinite-retry loops on a permanently
        // broken catalog URL and matches what the user would expect after
        // seeing an explicit error UI. (Gate-4 round-1 audit finding [1].)
        .onAppear {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            Task { await loadFeed(url: catalogURL) }
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private func feedContent(_ feed: OPDSFeed) -> some View {
        List {
            ForEach(Array(feed.entries.enumerated()), id: \.element.id) { _, entry in
                if feed.kind == .navigation {
                    navigationRow(entry: entry, feed: feed)
                } else {
                    acquisitionRow(entry: entry, feed: feed)
                }
            }

            if feed.nextPageURL != nil {
                loadMoreRow(feed: feed)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("opdsFeedList")
    }

    private func navigationRow(entry: OPDSEntry, feed: OPDSFeed) -> some View {
        Group {
            if let navURL = entry.navigationURL(against: feed.baseURL) {
                NavigationLink {
                    OPDSBrowserView(
                        catalogURL: navURL,
                        catalogName: entry.title,
                        credentials: credentials
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.body)
                        if let summary = entry.summary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("opdsNavEntry_\(entry.id)")
            } else {
                Text(entry.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func acquisitionRow(entry: OPDSEntry, feed: OPDSFeed) -> some View {
        NavigationLink {
            OPDSEntryView(
                entry: entry,
                baseURL: feed.baseURL,
                credentials: credentials
            )
        } label: {
            HStack(spacing: 12) {
                // Cover thumbnail
                if let coverURL = entry.coverURL(against: feed.baseURL) {
                    AsyncImage(url: coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                    }
                    .frame(width: 48, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.body)
                        .lineLimit(2)
                    if let author = entry.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.acquisitionLinks.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(
                                Array(entry.acquisitionLinks.enumerated()),
                                id: \.offset
                            ) { _, link in
                                if let label = link.formatLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.fill.tertiary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("opdsAcqEntry_\(entry.id)")
    }

    private func loadMoreRow(feed: OPDSFeed) -> some View {
        Button {
            if let nextURL = feed.nextPageURL {
                Task { await loadFeed(url: nextURL, append: true) }
            }
        } label: {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text("Load More")
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("opdsLoadMore")
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Failed to Load Catalog")
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                Task { await loadFeed(url: catalogURL) }
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("opdsErrorState")
    }

    // MARK: - Loading

    private func loadFeed(url: URL, append: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await client.fetchFeed(
                url: url,
                credentials: credentials
            )
            if append, let existing = feed {
                // Merge entries for pagination
                let merged = existing.entries + loaded.entries
                let deduped = OPDSFeed.deduplicated(merged)
                feed = OPDSFeed(
                    title: existing.title,
                    id: existing.id,
                    links: loaded.links,
                    entries: deduped,
                    baseURL: loaded.baseURL
                )
            } else {
                feed = loaded
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
