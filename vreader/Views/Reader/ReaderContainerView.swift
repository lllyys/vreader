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
// - Search sheet wired with SearchService, SearchViewModel, and SearchView.
// - Book content is indexed for search on first open using format-specific extractors.
//
// @coordinates-with: EPUBReaderViewModel.swift, TXTReaderViewModel.swift,
//   MDReaderViewModel.swift, PDFReaderViewModel.swift, LibraryView.swift,
//   ReaderSettingsStore.swift, ReaderSettingsPanel.swift,
//   TXTReaderContainerView.swift, PDFReaderContainerView.swift,
//   MDReaderContainerView.swift, DocumentFingerprint.swift,
//   SearchView.swift, SearchViewModel.swift, SearchService.swift, SearchIndexStore.swift,
//   TXTTextExtractor.swift, PDFTextExtractor.swift, EPUBTextExtractor.swift, MDTextExtractor.swift

import SwiftUI
import SwiftData
import os

/// Container view that dispatches to the correct format-specific reader.
struct ReaderContainerView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "Search"
    )

    let book: LibraryBookItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settingsStore = ReaderSettingsStore()
    @State private var showSettings = false
    @State private var showAnnotationsPanel = false
    @State private var showSearch = false
    @State private var selectedAnnotationsTab: AnnotationsPanelTab = .bookmarks
    @State private var searchViewModel: SearchViewModel?
    @State private var searchService: SearchService?

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
                        modelContainer: modelContext.container,
                        settingsStore: settingsStore
                    )
                case "md":
                    MDReaderHost(
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        modelContainer: modelContext.container,
                        settingsStore: settingsStore
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
            AnnotationsPanelSheet(
                selectedTab: $selectedAnnotationsTab,
                bookFingerprintKey: book.fingerprintKey,
                modelContainer: modelContext.container
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearch) {
            searchSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            guard searchService == nil,
                  let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else {
                return
            }
            do {
                let store = try SearchIndexStore()
                let service = SearchService(store: store)
                searchService = service

                // Create ViewModel immediately so the search panel opens instantly.
                // Searching before indexing returns empty results (acceptable UX).
                let vm = SearchViewModel(
                    searchService: service,
                    bookFingerprint: fingerprint
                )
                searchViewModel = vm

                let alreadyIndexed = await service.isIndexed(fingerprint: fingerprint)
                if !alreadyIndexed {
                    await Self.indexBookContent(
                        service: service,
                        fileURL: resolvedFileURL,
                        fingerprint: fingerprint,
                        format: book.format.lowercased()
                    )
                    // Re-trigger search if user typed a query while indexing
                    vm.retriggerIfNeeded()
                }
            } catch {
                Self.logger.error("Search setup failed: \(error.localizedDescription)")
            }
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

    // MARK: - Search Indexing

    /// Extracts text from the book and indexes it for search.
    /// Runs on the calling task — use from a `.task` modifier for background execution.
    private static func indexBookContent(
        service: SearchService,
        fileURL: URL,
        fingerprint: DocumentFingerprint,
        format: String
    ) async {
        do {
            switch format {
            case "txt":
                let extractor = TXTTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )

            case "md":
                let extractor = MDTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )

            case "pdf":
                let extractor = PDFTextExtractor()
                let units = try await extractor.extractTextUnits(
                    from: fileURL, fingerprint: fingerprint
                )
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: units,
                    segmentBaseOffsets: nil
                )

            case "epub":
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: fileURL)
                    let extractor = EPUBTextExtractor()
                    let units = try await extractor.extractFromParser(
                        parser, metadata: metadata
                    )
                    await parser.close()
                    try await service.indexBook(
                        fingerprint: fingerprint,
                        textUnits: units,
                        segmentBaseOffsets: nil
                    )
                } catch {
                    await parser.close()
                    throw error
                }

            default:
                break
            }
        } catch {
            Self.logger.error("Search indexing failed for \(format): \(error.localizedDescription)")
        }
    }

    // MARK: - Sheets & Placeholders

    /// Search sheet — uses SearchView when search pipeline is ready.
    @ViewBuilder
    private var searchSheet: some View {
        if let searchViewModel {
            SearchView(
                viewModel: searchViewModel,
                onNavigate: { _ in
                    // Navigation to search result location — format-specific
                    // readers will wire this when they support search navigation.
                    showSearch = false
                },
                onDismiss: {
                    showSearch = false
                }
            )
            .accessibilityIdentifier("searchSheet")
        } else {
            NavigationStack {
                ProgressView("Preparing search…")
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
    let settingsStore: ReaderSettingsStore

    @State private var viewModel: TXTReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TXTReaderContainerView(fileURL: fileURL, viewModel: viewModel, settingsStore: settingsStore)
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
    let settingsStore: ReaderSettingsStore

    @State private var viewModel: MDReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MDReaderContainerView(fileURL: fileURL, viewModel: viewModel, settingsStore: settingsStore)
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
/// Wires real list views for bookmarks, TOC, highlights, and annotations.
private struct AnnotationsPanelSheet: View {
    @Binding var selectedTab: AnnotationsPanelTab
    let bookFingerprintKey: String
    let modelContainer: ModelContainer

    @State private var bookmarkVM: BookmarkListViewModel?
    @State private var highlightVM: HighlightListViewModel?
    @State private var annotationVM: AnnotationListViewModel?

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
                        if let vm = bookmarkVM {
                            BookmarkListView(viewModel: vm, onNavigate: { _ in })
                        } else {
                            ProgressView()
                        }
                    case .toc:
                        TOCListView(entries: [], onNavigate: { _ in })
                    case .highlights:
                        if let vm = highlightVM {
                            HighlightListView(viewModel: vm, onNavigate: { _ in })
                        } else {
                            ProgressView()
                        }
                    case .annotations:
                        if let vm = annotationVM {
                            AnnotationListView(viewModel: vm, onNavigate: { _ in })
                        } else {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Reader Panels")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard bookmarkVM == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            bookmarkVM = BookmarkListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
            highlightVM = HighlightListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence,
                totalTextLengthUTF16: nil
            )
            annotationVM = AnnotationListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
        }
        .accessibilityIdentifier("annotationsPanelSheet")
    }
}
