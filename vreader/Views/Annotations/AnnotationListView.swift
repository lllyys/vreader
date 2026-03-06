// Purpose: List of annotations with content preview.
// Supports swipe-to-delete, tap to navigate, and edit via sheet.
//
// @coordinates-with: AnnotationListViewModel.swift, AnnotationRecord.swift,
//   AnnotationEditSheet.swift

import SwiftUI

/// Displays a list of annotations for a book.
struct AnnotationListView: View {
    @Bindable var viewModel: AnnotationListViewModel
    let onNavigate: (Locator) -> Void

    @State private var editingAnnotation: AnnotationRecord?

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                annotationList
            }
        }
        .navigationTitle("Annotations")
        .task {
            await viewModel.loadAnnotations()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $editingAnnotation) { annotation in
            AnnotationEditSheet(
                initialContent: annotation.content,
                onSave: { newContent in
                    Task {
                        await viewModel.updateAnnotation(
                            annotationId: annotation.annotationId,
                            content: newContent
                        )
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Annotations", systemImage: "note.text")
        } description: {
            Text("Add notes to remember your thoughts about the text.")
        }
        .accessibilityIdentifier("annotationEmptyState")
    }

    @ViewBuilder
    private var annotationList: some View {
        List {
            ForEach(viewModel.annotations) { annotation in
                Button {
                    onNavigate(annotation.locator)
                } label: {
                    AnnotationRowView(annotation: annotation)
                }
                .contextMenu {
                    Button("Edit") {
                        editingAnnotation = annotation
                    }
                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.removeAnnotation(annotationId: annotation.annotationId)
                        }
                    }
                }
                .accessibilityIdentifier("annotationRow-\(annotation.annotationId)")
            }
            .onDelete(perform: deleteAnnotations)
        }
    }

    private func deleteAnnotations(at offsets: IndexSet) {
        for index in offsets {
            let annotation = viewModel.annotations[index]
            Task {
                await viewModel.removeAnnotation(annotationId: annotation.annotationId)
            }
        }
    }
}

// MARK: - Annotation Row

private struct AnnotationRowView: View {
    let annotation: AnnotationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(annotation.content)
                .font(.body)
                .lineLimit(3)

            Text(formattedDate(annotation.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
