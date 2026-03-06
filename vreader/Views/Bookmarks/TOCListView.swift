// Purpose: Hierarchical table of contents display with navigation.
// Shows absent state for formats without TOC (TXT).
//
// @coordinates-with: TOCProvider.swift, TOCEntry.swift

import SwiftUI

/// Displays a table of contents with hierarchical indentation.
struct TOCListView: View {
    let entries: [TOCEntry]
    let onNavigate: (Locator) -> Void

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                tocList
            }
        }
        .navigationTitle("Table of Contents")
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

    @ViewBuilder
    private var tocList: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    onNavigate(entry.locator)
                } label: {
                    TOCRowView(entry: entry)
                }
                .accessibilityIdentifier("tocRow-\(entry.id)")
            }
        }
    }
}

// MARK: - TOC Row

private struct TOCRowView: View {
    let entry: TOCEntry

    /// Indentation per nesting level.
    private static let indentPerLevel: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.title)
                .font(entry.level == 0 ? .body : .subheadline)
                .fontWeight(entry.level == 0 ? .medium : .regular)
                .foregroundStyle(entry.level == 0 ? .primary : .secondary)
                .lineLimit(2)
        }
        .padding(.leading, CGFloat(entry.level) * Self.indentPerLevel)
        .padding(.vertical, 4)
    }
}
