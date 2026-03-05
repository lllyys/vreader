// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat.
// - EPUB/PDF readers are stubs until their respective WIs are wired.
// - TXT reader dispatches to TXTReaderContainerView (WI-6A).
// - MD reader dispatches to MDReaderContainerView (WI-6B).
// - Provides navigation bar with back button.
//
// @coordinates-with: EPUBReaderViewModel.swift, TXTReaderViewModel.swift,
//   MDReaderViewModel.swift, LibraryView.swift

import SwiftUI

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {
    let book: LibraryBookItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch book.format.lowercased() {
            case "epub":
                epubReaderContent
            case "pdf":
                unsupportedFormatView(format: "PDF")
            case "txt":
                txtReaderContent
            case "md":
                mdReaderContent
            default:
                unsupportedFormatView(format: book.format.uppercased())
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back to library")
                .accessibilityIdentifier("readerBackButton")
            }
        }
    }

    @ViewBuilder
    private var epubReaderContent: some View {
        // EPUB reader will be wired here in the full implementation.
        // For now, show a placeholder that will be replaced when
        // EPUBReaderView is fully wired with WKWebView.
        Text("EPUB Reader: \(book.title)")
            .accessibilityIdentifier("epubReaderPlaceholder")
    }

    @ViewBuilder
    private var txtReaderContent: some View {
        // TXT reader ViewModel and container are implemented (WI-6A).
        // Full wiring requires file URL from BookRecord persistence layer,
        // which will be connected when the navigation pipeline is complete.
        Text("TXT Reader: \(book.title)")
            .accessibilityIdentifier("txtReaderPlaceholder")
    }

    @ViewBuilder
    private var mdReaderContent: some View {
        // MD reader ViewModel and container are implemented (WI-6B).
        // Full wiring requires file URL from BookRecord persistence layer,
        // which will be connected when the navigation pipeline is complete.
        Text("MD Reader: \(book.title)")
            .accessibilityIdentifier("mdReaderPlaceholder")
    }

    private func unsupportedFormatView(format: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(format) reader coming soon")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("unsupportedFormatView")
    }
}
