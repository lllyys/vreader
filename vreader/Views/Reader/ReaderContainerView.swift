// Purpose: Navigation container that dispatches to format-specific reader views.
// Determines reader type from book format and provides shared chrome.
//
// Key decisions:
// - Dispatches to format-specific reader based on BookFormat.
// - EPUB reader wired with production EPUBParser (ZIP extraction + OPF parsing).
// - TXT, PDF, MD readers are fully wired with real ViewModels and containers.
// - File URL resolved from fingerprintKey using the sandbox import convention.
// - DocumentFingerprint parsed from the canonical key string.
// - Each format host view owns its ViewModel via @State for stable lifecycle.
// - Provides navigation bar with back button, search button, settings button, and annotations menu.
// - Settings panel presented as a sheet for theme/typography controls.
// - Annotations sheet provides access to bookmarks, TOC, highlights, annotations.
// - Search sheet placeholder until SearchService is instantiated in reader pipeline.
//
// @coordinates-with: EPUBReaderViewModel.swift, TXTReaderViewModel.swift,
//   MDReaderViewModel.swift, PDFReaderViewModel.swift, LibraryView.swift,
//   ReaderSettingsStore.swift, ReaderSettingsPanel.swift,
//   TXTReaderContainerView.swift, PDFReaderContainerView.swift,
//   MDReaderContainerView.swift, DocumentFingerprint.swift

import SwiftUI
import SwiftData

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {
    let book: LibraryBookItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settingsStore = ReaderSettingsStore()
    @State private var showSettings = false
    @State private var showAnnotationsPanel = false
    @State private var showSearch = false
    @State private var selectedAnnotationsTab: AnnotationsPanelTab = .bookmarks

    var body: some View {
        Group {
            if let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) {
                switch book.format.lowercased() {
                case "epub":
                    EPUBReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container
                    )
                case "pdf":
                    PDFReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container
                    )
                case "txt":
                    TXTReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container
                    )
                case "md":
                    MDReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container
                    )
                default:
                    unsupportedFormatView(format: book.format.uppercased())
                }
            } else {
                fingerprintErrorView
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
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search in book")
                .accessibilityIdentifier("readerSearchButton")

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
        .sheet(isPresented: $showSearch) {
            searchSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - File URL Resolution

    /// Resolves the sandbox file URL using the same convention as BookImporter.
    private var resolvedFileURL: URL {
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        let safeName = book.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let bookFormat = BookFormat(rawValue: book.format.lowercased())
        let ext = bookFormat?.fileExtensions.first ?? book.format.lowercased()
        return booksDir
            .appendingPathComponent(safeName)
            .appendingPathExtension(ext)
    }

    // MARK: - Device ID

    /// Stable device identifier for reading position and session tracking.
    static let deviceId: String = {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }()

    // MARK: - Sheets & Placeholders

    /// Search sheet placeholder — wired when SearchService is available.
    @ViewBuilder
    private var searchSheet: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Search will be available once the book is indexed.")
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        showSearch = false
                    }
                }
            }
        }
        .accessibilityIdentifier("searchSheet")
    }

    private var fingerprintErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to open this book.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("fingerprintErrorView")
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

// MARK: - Format-Specific Host Views

/// Owns TXTReaderViewModel lifecycle via @State.
private struct TXTReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer

    @State private var viewModel: TXTReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TXTReaderContainerView(fileURL: fileURL, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: NoOpSessionStore(),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = TXTReaderViewModel(
                bookFingerprint: fingerprint,
                txtService: TXTService(),
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns PDFReaderViewModel lifecycle via @State.
private struct PDFReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer

    @State private var viewModel: PDFReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                PDFReaderContainerView(fileURL: fileURL, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: NoOpSessionStore(),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = PDFReaderViewModel(
                bookFingerprint: fingerprint,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns MDReaderViewModel lifecycle via @State.
private struct MDReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer

    @State private var viewModel: MDReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MDReaderContainerView(fileURL: fileURL, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: NoOpSessionStore(),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = MDReaderViewModel(
                bookFingerprint: fingerprint,
                parser: MDParser(),
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns EPUBReaderViewModel lifecycle via @State.
private struct EPUBReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer

    @State private var viewModel: EPUBReaderViewModel?
    @State private var parser: EPUBParser?

    var body: some View {
        Group {
            if let viewModel, let parser {
                EPUBReaderContainerView(
                    fileURL: fileURL,
                    viewModel: viewModel,
                    parser: parser
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: NoOpSessionStore(),
                deviceId: ReaderContainerView.deviceId
            )
            let epubParser = EPUBParser()
            parser = epubParser
            viewModel = EPUBReaderViewModel(
                bookFingerprint: fingerprint,
                parser: epubParser,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
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
