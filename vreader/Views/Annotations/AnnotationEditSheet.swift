// Purpose: Sheet for editing annotation content.
// Provides TextEditor with Save/Cancel actions.
//
// @coordinates-with: AnnotationListView.swift

import SwiftUI

/// Sheet for editing an annotation's content.
struct AnnotationEditSheet: View {
    let initialContent: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $content)
                .padding()
                .navigationTitle("Edit Annotation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .accessibilityIdentifier("annotationEditCancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(content)
                            dismiss()
                        }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("annotationEditSave")
                    }
                }
        }
        .onAppear {
            content = initialContent
        }
    }
}
