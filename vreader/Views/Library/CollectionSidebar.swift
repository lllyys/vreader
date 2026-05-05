// Purpose: Sidebar view for filtering library by collection, tag, or series.
// Provides a compact sidebar that can be toggled from the library toolbar.
//
// Key decisions:
// - Uses a sheet presentation rather than a split view for simplicity on iPhone.
// - Fetches collections/tags/series lazily on appear.
// - Selection communicates back via a binding or callback.
// - Supports "All Books" as the default (nil filter).
//
// @coordinates-with: LibraryView.swift, PersistenceActor+Collections.swift

import SwiftUI

/// Represents the active filter for the library.
enum LibraryFilter: Equatable, Hashable, Sendable {
    case allBooks
    case collection(String)
    case tag(String)
    case series(String)

    var displayName: String {
        switch self {
        case .allBooks: return "All Books"
        case .collection(let name): return name
        case .tag(let name): return name
        case .series(let name): return name
        }
    }
}

/// Sidebar for filtering library by collection, tag, or series.
struct CollectionSidebar: View {
    @Binding var activeFilter: LibraryFilter
    let collections: [CollectionRecord]
    let allTags: [String]
    let allSeries: [String]
    let onCreateCollection: (String) async -> Void
    let onDeleteCollection: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newCollectionName = ""
    @State private var isAddingCollection = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - All Books
                Section {
                    Button {
                        activeFilter = .allBooks
                        dismiss()
                    } label: {
                        Label("All Books", systemImage: "books.vertical")
                    }
                    .foregroundStyle(
                        activeFilter == .allBooks
                            ? .primary : .secondary
                    )
                    .accessibilityIdentifier("filterAllBooks")
                }

                // MARK: - Collections
                Section("Collections") {
                    ForEach(collections, id: \.name) { collection in
                        Button {
                            activeFilter = .collection(collection.name)
                            dismiss()
                        } label: {
                            HStack {
                                Label(
                                    collection.name,
                                    systemImage: "folder"
                                )
                                Spacer()
                                Text("\(collection.bookCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(
                            activeFilter == .collection(collection.name)
                                ? .primary : .secondary
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await onDeleteCollection(collection.name)
                                    } catch {
                                        // Bug #129: surface the failure rather
                                        // than silently swallowing via `try?`.
                                        // The alert is already wired below.
                                        errorMessage = "Failed to delete \"\(collection.name)\": \(error.localizedDescription)"
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if isAddingCollection {
                        HStack {
                            TextField(
                                "Collection name",
                                text: $newCollectionName
                            )
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await createCollection() }
                            }
                            .accessibilityIdentifier(
                                "newCollectionTextField"
                            )
                            Button("Add") {
                                Task { await createCollection() }
                            }
                            .disabled(newCollectionName
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty)
                            .accessibilityIdentifier("addCollectionButton")
                        }
                    } else {
                        Button {
                            isAddingCollection = true
                        } label: {
                            Label(
                                "New Collection",
                                systemImage: "plus.circle"
                            )
                        }
                        .accessibilityIdentifier("newCollectionButton")
                    }
                }

                // MARK: - Tags
                if !allTags.isEmpty {
                    Section("Tags") {
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                activeFilter = .tag(tag)
                                dismiss()
                            } label: {
                                Label(tag, systemImage: "tag")
                            }
                            .foregroundStyle(
                                activeFilter == .tag(tag)
                                    ? .primary : .secondary
                            )
                        }
                    }
                }

                // MARK: - Series
                if !allSeries.isEmpty {
                    Section("Series") {
                        ForEach(allSeries, id: \.self) { series in
                            Button {
                                activeFilter = .series(series)
                                dismiss()
                            } label: {
                                Label(
                                    series,
                                    systemImage: "books.vertical"
                                )
                            }
                            .foregroundStyle(
                                activeFilter == .series(series)
                                    ? .primary : .secondary
                            )
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("filterDoneButton")
                }
            }
            .alert(
                "Error",
                isPresented: .init(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Actions

    private func createCollection() async {
        let name = newCollectionName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !name.isEmpty else { return }
        await onCreateCollection(name)
        newCollectionName = ""
        isAddingCollection = false
    }
}
