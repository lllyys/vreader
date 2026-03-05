// Purpose: SwiftUI container for the PDF reader. Composes the PDFViewBridge
// with loading/error/password overlays and reading session chrome.
//
// Key decisions:
// - Owns PDFReaderViewModel lifecycle (close on disappear).
// - Bridge calls ViewModel directly (no delegate protocol needed).
// - Bridge is always mounted; loading/password/error are overlays.
// - Shows password prompt overlay for encrypted PDFs.
// - Page indicator and session time overlay at bottom.
//
// @coordinates-with: PDFReaderViewModel.swift, PDFViewBridge.swift,
//   PDFPasswordPromptView.swift

import SwiftUI

/// Container view for the PDF reader screen.
struct PDFReaderContainerView: View {
    let fileURL: URL
    let viewModel: PDFReaderViewModel

    @State private var password: String = ""
    @State private var submittedPassword: String?
    @State private var passwordAttemptId: Int = 0
    @State private var restoredPage: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Bridge is always mounted so PDFDocument stays loaded
            PDFViewBridge(
                url: fileURL,
                restorePage: restoredPage,
                password: submittedPassword,
                passwordAttemptId: passwordAttemptId,
                viewModel: viewModel
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier("pdfReaderContent")

            // Overlays on top of the bridge
            if viewModel.needsPassword {
                passwordOverlay
            }

            if viewModel.isLoading {
                loadingOverlay
            }

            if let errorMessage = viewModel.errorMessage, !viewModel.isDocumentLoaded {
                errorOverlay(message: errorMessage)
            }

            // Bottom overlay for page indicator and session time
            if viewModel.isDocumentLoaded {
                VStack {
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .task {
            viewModel.beginLoading()
        }
        .onDisappear {
            Task { await viewModel.close() }
        }
        .task(id: viewModel.isDocumentLoaded) {
            if viewModel.isDocumentLoaded {
                try? viewModel.startSession()
                restoredPage = await viewModel.restorePosition()
                await viewModel.updateLastOpened()
            }
        }
        .accessibilityIdentifier("pdfReaderContainer")
    }

    // MARK: - Overlays

    @ViewBuilder
    private var passwordOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
        PDFPasswordPromptView(
            password: $password,
            errorMessage: viewModel.errorMessage,
            onSubmit: {
                passwordAttemptId += 1
                submittedPassword = password
            },
            onCancel: {
                dismiss()
            }
        )
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        Color(.systemBackground).opacity(0.9)
            .ignoresSafeArea()
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("pdfReaderLoading")
    }

    private func errorOverlay(message: String) -> some View {
        ZStack {
            Color(.systemBackground).opacity(0.9)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .accessibilityIdentifier("pdfReaderError")
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        HStack {
            Text(viewModel.pageIndicator)
                .font(.caption)
                .monospacedDigit()
                .accessibilityLabel("Page \(viewModel.currentPageIndex + 1) of \(viewModel.totalPages)")
                .accessibilityIdentifier("pdfPageIndicator")

            Spacer()

            if let sessionTime = viewModel.sessionTimeDisplay {
                Text(sessionTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdfSessionTime")
            }

            if let pph = viewModel.pagesPerHour {
                Text("~\(Int(pph.rounded())) pages/hr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdfPagesPerHour")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("pdfBottomOverlay")
    }
}
