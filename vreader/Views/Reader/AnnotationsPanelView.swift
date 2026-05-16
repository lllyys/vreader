// Purpose: Tabbed panel for bookmarks, TOC, highlights, and annotations.
// Extracted from ReaderContainerView (WI-004) to reduce its size.
//
// Key decisions:
// - Owns @State selectedTab (parent does not need to track tab selection).
// - Uses closure-based interface: onNavigate + onDismiss.
// - Creates list ViewModels internally from modelContainer + bookFingerprintKey.
// - Does NOT own sheet presentation — parent controls .sheet(isPresented:).
//
// @coordinates-with ReaderContainerView.swift, BookmarkListView.swift,
//   HighlightListView.swift, AnnotationListView.swift, TOCListView.swift

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Tab Enum

/// Tabs for the annotations panel.
enum AnnotationsPanelTab: String, CaseIterable, Identifiable {
    case toc = "Contents"
    case bookmarks = "Bookmarks"
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

// MARK: - Panel View

/// Sheet content for the tabbed reader annotations panel.
/// Parent wires this into a `.sheet` modifier and provides navigation/dismiss closures.
struct AnnotationsPanelView: View {
    let bookFingerprintKey: String
    let modelContainer: ModelContainer
    let tocEntries: [TOCEntry]
    let currentLocator: Locator?
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    @State private var selectedTab: AnnotationsPanelTab
    @State private var bookmarkVM: BookmarkListViewModel?
    @State private var highlightVM: HighlightListViewModel?
    @State private var annotationVM: AnnotationListViewModel?
    @State private var isShowingExportShare = false
    @State private var exportedFileURL: URL?
    @State private var isShowingImporter = false
    @State private var importMessage: String?

    /// `initialTab` (Feature #60 WI-6b) seeds which segment the panel
    /// opens on — the reader bottom chrome's Contents button opens
    /// `.toc`, Notes opens `.highlights`. Defaults to `.toc` so the
    /// previous behavior is preserved for any future caller that omits
    /// it.
    init(
        bookFingerprintKey: String,
        modelContainer: ModelContainer,
        tocEntries: [TOCEntry],
        currentLocator: Locator?,
        initialTab: AnnotationsPanelTab = .toc,
        onNavigate: @escaping (Locator) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.modelContainer = modelContainer
        self.tocEntries = tocEntries
        self.currentLocator = currentLocator
        self.onNavigate = onNavigate
        self.onDismiss = onDismiss
        self._selectedTab = State(initialValue: initialTab)
    }

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
                            BookmarkListView(viewModel: vm, onNavigate: handleNavigate)
                        } else {
                            ProgressView()
                        }
                    case .toc:
                        TOCListView(entries: tocEntries, currentLocator: currentLocator, onNavigate: handleNavigate)
                    case .highlights:
                        if let vm = highlightVM {
                            HighlightListView(viewModel: vm, onNavigate: handleNavigate)
                        } else {
                            ProgressView()
                        }
                    case .annotations:
                        if let vm = annotationVM {
                            AnnotationListView(viewModel: vm, onNavigate: handleNavigate)
                        } else {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Reader Panels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await exportAnnotations() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export annotations")
                    .accessibilityIdentifier("annotationsExportButton")

                    Button {
                        isShowingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import annotations")
                    .accessibilityIdentifier("annotationsImportButton")
                }
            }
        }
        .sheet(isPresented: $isShowingExportShare) {
            if let url = exportedFileURL {
                ShareActivityView(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importAnnotationsFrom(url: url) }
            case .failure:
                break
            }
        }
        .alert("Import Result", isPresented: .init(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .task {
            guard bookmarkVM == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let bVM = BookmarkListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
            let hVM = HighlightListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence,
                totalTextLengthUTF16: nil
            )
            let aVM = AnnotationListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
            // Assign all at once to avoid partial init on task cancellation
            bookmarkVM = bVM
            highlightVM = hVM
            annotationVM = aVM
        }
        .accessibilityIdentifier("annotationsPanelSheet")
    }

    private func handleNavigate(_ locator: Locator) {
        onNavigate(locator)
        onDismiss()
    }

    // MARK: - Export (C02)

    private func exportAnnotations() async {
        // Bug #130: every step propagates errors so failures surface via
        // the existing `importMessage` alert path (renamed semantically as
        // a generic "export/import status" channel — both flows are
        // mutually exclusive in this view).
        let persistence = PersistenceActor(modelContainer: modelContainer)

        var fetchErrors: [String] = []
        let highlights: [HighlightRecord]
        do {
            highlights = try await persistence.fetchHighlights(forBookWithKey: bookFingerprintKey)
        } catch {
            fetchErrors.append("highlights")
            highlights = []
        }
        let bookmarks: [BookmarkRecord]
        do {
            bookmarks = try await persistence.fetchBookmarks(forBookWithKey: bookFingerprintKey)
        } catch {
            fetchErrors.append("bookmarks")
            bookmarks = []
        }
        let notes: [AnnotationRecord]
        do {
            notes = try await persistence.fetchAnnotations(forBookWithKey: bookFingerprintKey)
        } catch {
            fetchErrors.append("notes")
            notes = []
        }

        let payload = AnnotationExporter.buildPayload(
            highlights: highlights,
            bookmarks: bookmarks,
            notes: notes,
            bookTitle: bookFingerprintKey,
            bookAuthor: nil
        )

        let data: Data
        do {
            data = try AnnotationExporter.export(payload: payload, format: .json)
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("annotations-export.json")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            importMessage = "Export failed: could not write temp file (\(error.localizedDescription))."
            return
        }

        exportedFileURL = tempURL
        if !fetchErrors.isEmpty {
            importMessage = "Exported with warnings: skipped \(fetchErrors.joined(separator: ", ")) (fetch failed)."
        }
        isShowingExportShare = true
    }

    // MARK: - Import (C03)

    private func importAnnotationsFrom(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            importMessage = "Could not read file."
            return
        }

        let persistence = PersistenceActor(modelContainer: modelContainer)
        let importer = AnnotationImporter(
            highlightStore: persistence,
            bookmarkStore: persistence,
            annotationStore: persistence
        )

        do {
            let result = try await importer.importJSON(
                data: data,
                bookFingerprintKey: bookFingerprintKey
            )
            importMessage = "Imported \(result.importedCount), skipped \(result.skippedCount)."
            // Refresh view models after import
            await bookmarkVM?.loadBookmarks()
            await highlightVM?.loadHighlights()
            await annotationVM?.loadAnnotations()
            // Bug #88: Notify reader to refresh visual highlights
            if result.importedCount > 0 {
                NotificationCenter.default.post(name: .readerHighlightsDidImport, object: nil)
            }
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
