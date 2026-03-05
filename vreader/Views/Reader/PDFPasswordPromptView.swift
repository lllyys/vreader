// Purpose: Password entry UI for encrypted PDF documents.
// Presents a secure text field and submit button.
//
// Key decisions:
// - SecureField for password input (no plaintext display).
// - Submit on button tap or keyboard return.
// - Error message display for rejected passwords.
// - Centered layout with padding for readability.
// - Accessibility identifiers for UI testing.
//
// @coordinates-with: PDFReaderContainerView.swift, PDFReaderViewModel.swift

import SwiftUI

/// Password entry view for encrypted PDFs.
struct PDFPasswordPromptView: View {
    @Binding var password: String
    let errorMessage: String?
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("This PDF is password protected")
                .font(.headline)

            VStack(spacing: 12) {
                SecureField("Enter password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPasswordFocused)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier("pdfPasswordField")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("pdfPasswordError")
                }
            }
            .frame(maxWidth: 300)

            HStack(spacing: 16) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("pdfPasswordCancel")

                Button("Unlock", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
                    .accessibilityIdentifier("pdfPasswordSubmit")
            }
        }
        .padding(32)
        .onAppear {
            isPasswordFocused = true
        }
        .accessibilityIdentifier("pdfPasswordPrompt")
    }
}
