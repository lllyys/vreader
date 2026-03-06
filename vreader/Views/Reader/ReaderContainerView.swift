// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat.
// - EPUB reader is a stub until its WI is fully wired.
// - All format readers (EPUB/PDF/TXT/MD) have containers + ViewModels implemented.
// - Full wiring requires file URL resolved from BookRecord persistence layer.
// - Placeholders remain until navigation pipeline provides file URLs.
// - Provides navigation bar with back button, settings button, and annotations menu.
// - Settings panel presented as a sheet for theme/typography controls.
// - Annotations sheet provides access to bookmarks, TOC, highlights, annotations.
//
// @coordinates-with: EPUBReaderViewModel.swift, TXTReaderViewModel.swift,
//   MDReaderViewModel.swift, PDFReaderViewModel.swift, LibraryView.swift,
//   ReaderSettingsStore.swift, ReaderSettingsPanel.swift,
//   BookmarkListView.swift, TOCListView.swift, HighlightListView.swift,
//   AnnotationListView.swift

import SwiftUI

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {
    let book: LibraryBookItem

    @Environment(\.dismiss) private var dismiss
    @State private var settingsStore = ReaderSettingsStore()
    @State private var showSettings = false
    @State private var showAnnotationsPanel = false
    @State private var selectedAnnotationsTab: AnnotationsPanelTab = .bookmarks

    var body: some View {
        Group {
            switch book.format.lowercased() {
            case "epub":
                epubReaderContent
            case "pdf":
                pdfReaderContent
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showAnnotationsPanel = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Bookmarks and annotations")
                .accessibilityIdentifier("readerAnnotationsButton")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Reading settings")
                .accessibilityIdentifier("readerSettingsButton")
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(store: settingsStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAnnotationsPanel) {
            AnnotationsPanelSheet(selectedTab: $selectedAnnotationsTab)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
    private var pdfReaderContent: some View {
        // PDFReaderContainerView + PDFReaderViewModel implemented (WI-7).
        // Placeholder until navigation pipeline resolves file URLs from BookRecord.
        Text("PDF Reader: \(book.title)")
            .accessibilityIdentifier("pdfReaderPlaceholder")
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

// MARK: - Annotations Panel

/// Tabs for the annotations panel sheet.
enum AnnotationsPanelTab: String, CaseIterable, Identifiable {
    case bookmarks = "Bookmarks"
    case toc = "Contents"
    case highlights = "Highlights"
    case annotations = "Notes"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bookmarks: return "bookmark"
        case .toc: return "list.bullet"
        case .highlights: return "highlighter"
        case .annotations: return "note.text"
        }
    }
}

/// Sheet that hosts the tabbed annotations panel.
/// Placeholder panels are shown until ViewModels are wired with live persistence.
private struct AnnotationsPanelSheet: View {
    @Binding var selectedTab: AnnotationsPanelTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(AnnotationsPanelTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                Group {
                    switch selectedTab {
                    case .bookmarks:
                        placeholderView(
                            title: "Bookmarks",
                            systemImage: "bookmark",
                            description: "Bookmarks will appear here once the reader is fully wired."
                        )
                    case .toc:
                        placeholderView(
                            title: "Table of Contents",
                            systemImage: "list.bullet",
                            description: "Table of contents will appear here once the reader is fully wired."
                        )
                    case .highlights:
                        placeholderView(
                            title: "Highlights",
                            systemImage: "highlighter",
                            description: "Highlights will appear here once the reader is fully wired."
                        )
                    case .annotations:
                        placeholderView(
                            title: "Notes",
                            systemImage: "note.text",
                            description: "Notes will appear here once the reader is fully wired."
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Reader Panels")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("annotationsPanelSheet")
    }

    private func placeholderView(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        }
    }
}
