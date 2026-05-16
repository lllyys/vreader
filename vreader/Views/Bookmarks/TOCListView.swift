// Purpose: Hierarchical table of contents display with navigation.
// Shows absent state for formats without TOC (TXT).
// Scrolls to and highlights the active chapter on appear.
//
// Rendered as the Contents tab inside `AnnotationsPanelView`'s
// `ReaderSheetChrome` (feature #60 WI-10) — the `List` background is
// hidden so the design's sheet surface tint shows through.
//
// @coordinates-with: TOCProvider.swift, TOCEntry.swift,
//   AnnotationsPanelView.swift

import SwiftUI

/// Displays a table of contents with hierarchical indentation.
struct TOCListView: View {
    let entries: [TOCEntry]
    let currentLocator: Locator?
    let onNavigate: (Locator) -> Void

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                tocList
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Table of Contents", systemImage: "list.bullet")
        } description: {
            Text("No table of contents available for this document.")
        }
        .accessibilityIdentifier("tocEmptyState")
    }

    /// Index of the active TOC entry based on the current reading position.
    /// Matches by charOffsetUTF16 (TXT/MD), href (EPUB), or page (PDF).
    /// Picks the last entry whose position is at or before the current locator.
    private var activeEntryIndex: Int? {
        guard let loc = currentLocator else { return nil }

        // TXT / MD — compare charOffsetUTF16
        if let currentOffset = loc.charOffsetUTF16 {
            var bestIndex: Int?
            for (i, entry) in entries.enumerated() {
                if let entryOffset = entry.locator.charOffsetUTF16, entryOffset <= currentOffset {
                    bestIndex = i
                }
            }
            return bestIndex
        }

        // PDF — compare page
        if let currentPage = loc.page {
            var bestIndex: Int?
            for (i, entry) in entries.enumerated() {
                if let entryPage = entry.locator.page, entryPage <= currentPage {
                    bestIndex = i
                }
            }
            return bestIndex
        }

        // EPUB — compare href (match the last entry with the same href)
        if let currentHref = loc.href {
            var bestIndex: Int?
            for (i, entry) in entries.enumerated() {
                if entry.locator.href == currentHref {
                    bestIndex = i
                }
            }
            return bestIndex
        }

        return nil
    }

    @ViewBuilder
    private var tocList: some View {
        let activeIndex = activeEntryIndex
        ScrollViewReader { proxy in
            List {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let isActive = index == activeIndex
                    Button {
                        onNavigate(entry.locator)
                    } label: {
                        TOCRowView(entry: entry, isActive: isActive)
                    }
                    .id(entry.id)
                    .listRowBackground(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
                    .accessibilityIdentifier("tocRow-\(entry.id)")
                }
            }
            // Hide the grouped-List backdrop so the design's sheet
            // surface tint (`ReaderSheetChrome`) shows through.
            .scrollContentBackground(.hidden)
            .task(id: activeIndex) {
                guard let activeIndex, entries.indices.contains(activeIndex) else { return }
                let targetID = entries[activeIndex].id
                // Retry scroll with increasing delays to handle lazy List rendering.
                // For short lists the first attempt succeeds; for 1000+ entries
                // later attempts catch rows that haven't been materialized yet.
                for delay in [100, 300, 600] {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - TOC Row

private struct TOCRowView: View {
    let entry: TOCEntry
    let isActive: Bool

    /// Indentation per nesting level.
    private static let indentPerLevel: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.title)
                .font(entry.level == 0 ? .body : .subheadline)
                .fontWeight(isActive ? .semibold : (entry.level == 0 ? .medium : .regular))
                .foregroundStyle(isActive ? Color.accentColor : (entry.level == 0 ? .primary : .secondary))
                .lineLimit(2)
        }
        .padding(.leading, CGFloat(entry.level) * Self.indentPerLevel)
        .padding(.vertical, 4)
    }
}
