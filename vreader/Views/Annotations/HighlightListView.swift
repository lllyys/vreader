// Purpose: List of highlights with color indicator, text preview, and note preview.
// Supports swipe-to-delete and tap-to-navigate.
//
// @coordinates-with: HighlightListViewModel.swift, HighlightRecord.swift

import SwiftUI

/// Displays a list of highlights for a book.
struct HighlightListView: View {
    @Bindable var viewModel: HighlightListViewModel
    let onNavigate: (Locator) -> Void

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                highlightList
            }
        }
        .navigationTitle("Highlights")
        .task {
            await viewModel.loadHighlights()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Highlights", systemImage: "highlighter")
        } description: {
            Text("Highlight text in the reader to save important passages.")
        }
        .accessibilityIdentifier("highlightEmptyState")
    }

    @ViewBuilder
    private var highlightList: some View {
        List {
            if viewModel.hasOutOfBoundsHighlights {
                Section {
                    Label(
                        "Some highlights may be inaccurate — the document content may have changed.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            ForEach(viewModel.highlights) { highlight in
                Button {
                    onNavigate(highlight.locator)
                } label: {
                    HighlightRowView(
                        highlight: highlight,
                        isOutOfBounds: viewModel.outOfBoundsHighlightIds.contains(highlight.highlightId)
                    )
                }
                .accessibilityIdentifier("highlightRow-\(highlight.highlightId)")
            }
            .onDelete(perform: deleteHighlights)
        }
    }

    private func deleteHighlights(at offsets: IndexSet) {
        for index in offsets {
            let highlight = viewModel.highlights[index]
            Task {
                await viewModel.removeHighlight(highlightId: highlight.highlightId)
            }
        }
    }
}

// MARK: - Highlight Row

private struct HighlightRowView: View {
    let highlight: HighlightRecord
    let isOutOfBounds: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(highlightColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.selectedText)
                    .font(.body)
                    .lineLimit(2)
                    .italic()

                if let note = highlight.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if isOutOfBounds {
                    Label("May be inaccurate", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var highlightColor: Color {
        switch highlight.color.lowercased() {
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "red": return .red
        case "orange": return .orange
        case "purple": return .purple
        default: return .yellow
        }
    }
}
