// Purpose: SwiftUI container for the TXT reader. Composes the TXTTextViewBridge
// with loading/error overlays and reading session chrome.
//
// Key decisions:
// - Owns TXTReaderViewModel lifecycle (open on appear, close on disappear).
// - Delegates scroll/selection events from bridge to ViewModel.
// - Shows loading spinner during file open.
// - Shows error message on failure.
// - Passes theme config to bridge (font size, line spacing).
//
// @coordinates-with: TXTReaderViewModel.swift, TXTTextViewBridge.swift

import SwiftUI

/// Container view for the TXT reader screen.
struct TXTReaderContainerView: View {
    let fileURL: URL
    let viewModel: TXTReaderViewModel

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.textContent == nil {
                errorView(message: errorMessage)
            } else if let text = viewModel.textContent {
                readerContent(text: text)
            } else {
                // Not yet opened
                Color.clear
            }
        }
        .task {
            await viewModel.open(url: fileURL)
        }
        .onDisappear {
            Task { await viewModel.close() }
        }
        .accessibilityIdentifier("txtReaderContainer")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("txtReaderLoading")
    }

    private func errorView(message: String) -> some View {
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
        .accessibilityIdentifier("txtReaderError")
    }

    @ViewBuilder
    private func readerContent(text: String) -> some View {
        TXTTextViewBridge(
            text: text,
            config: TXTViewConfig(),
            restoreOffset: viewModel.currentOffsetUTF16,
            delegate: nil // Delegate wiring deferred to WI-6B bridge integration
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderContent")
    }
}
