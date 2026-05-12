// Purpose: SwiftUI container for the PDF reader. Composes the PDFViewBridge
// with loading/error/password overlays, reading progress bar, session chrome,
// and PDF text selection / highlight annotation pipeline.
//
// Key decisions:
// - Owns PDFReaderViewModel lifecycle (close on disappear).
// - Bridge calls ViewModel directly (no delegate protocol needed).
// - Bridge is always mounted; loading/password/error are overlays.
// - Shows password prompt overlay for encrypted PDFs.
// - ReadingProgressBar wired via PDFProgressHelper for page-level scrubbing.
// - Page indicator and session time overlay at bottom.
// - Observes .readerTextSelected for PDF annotation creation via PDFAnnotationBridge.
// - Text selection triggers confirmationDialog with Highlight/Note/Copy actions.
// - "Add Note" opens a TextEditor sheet and persists highlight with note text.
// - Highlights stored in SwiftData (non-destructive — not written into the PDF file).
// - After persisting a highlight, passes anchor to bridge for visible annotation creation.
// - On document open, fetches saved highlights and passes to bridge for restoration.
// - Posts .readerPositionDidChange notification for AI panel live locator.
//
// @coordinates-with: PDFReaderViewModel.swift, PDFViewBridge.swift,
//   PDFPasswordPromptView.swift, ReadingProgressBar.swift, PDFProgressHelper.swift,
//   PDFAnnotationBridge.swift, HighlightPersisting.swift, PDFPageNavigator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import PDFKit
import UIKit

/// Container view for the PDF reader screen.
struct PDFReaderContainerView: View {
    let fileURL: URL
    let viewModel: PDFReaderViewModel
    var modelContainer: ModelContainer?
    var ttsService: TTSService?

    @State var password: String = ""
    @State var submittedPassword: String?
    @State var passwordAttemptId: Int = 0
    @State var restoredPage: Int?
    @State var readingProgress: Double = 0
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true
    /// Pending PDF text selection event for highlight action menu.
    @State var pendingSelectionEvent: ReaderSelectionEvent?
    /// Whether the highlight action sheet is visible.
    @State private var showHighlightSheet = false
    /// Saved highlights to restore as visible annotations when the document loads.
    @State var savedHighlightRecords: [HighlightRecord]?
    /// Pending highlight to create as a visible annotation after persist.
    @State var pendingHighlightPayload: PDFHighlightNotificationPayload?
    /// Incremented each time a new highlight is persisted, triggers updateUIView.
    @State var pendingHighlightId: Int = 0
    /// Whether the note input sheet is visible.
    @State var showNoteSheet = false
    /// Phase R4: highlight renderer and coordinator.
    @State private var highlightRenderer = PDFHighlightRenderer()
    @State var highlightCoordinator: HighlightCoordinator?
    /// Text input for the note being added.
    @State var noteText = ""
    /// Temporary search highlight text quote for navigating to search results (bug #43).
    /// Set when receiving .readerNavigateToLocator with textQuote, cleared after display.
    @State private var searchHighlightText: String?
    /// Page navigator for tap zone integration (WI-B09).
    @State private var pageNavigator = PDFPageNavigator()

    var body: some View {
        ZStack {
            // Bridge is always mounted so PDFDocument stays loaded
            PDFViewBridge(
                url: fileURL,
                restorePage: restoredPage,
                password: submittedPassword,
                passwordAttemptId: passwordAttemptId,
                viewModel: viewModel,
                highlightRecords: savedHighlightRecords,
                pendingHighlight: pendingHighlightPayload,
                pendingHighlightId: pendingHighlightId,
                searchHighlightText: searchHighlightText,
                highlightRenderer: highlightRenderer
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

            // Bottom overlay for progress bar, page indicator, and session time
            // Hidden when TTS is active to avoid overlap (bug #97)
            if viewModel.isDocumentLoaded && isChromeVisible
                && (ttsService?.state ?? .idle) == .idle {
                VStack(spacing: 0) {
                    Spacer()
                    progressBar
                    bottomOverlay
                }
            }
        }
        .task {
            viewModel.beginLoading()
        }
        .onDisappear {
            let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await viewModel.close()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                Task {
                    await viewModel.onBackground()
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                }
            case .active:
                viewModel.onForeground()
            @unknown default:
                break
            }
        }
        .task(id: viewModel.isDocumentLoaded) {
            if viewModel.isDocumentLoaded {
                // PERF: Restore position first (needed for display), defer the rest
                restoredPage = await viewModel.restorePosition()
                pageNavigator.totalPages = viewModel.totalPages
                if let page = restoredPage {
                    pageNavigator.syncCurrentPage(page)
                }
                // Defer: session, lastOpened, highlights — don't block content
                Task {
                    try? viewModel.startSession()
                    await viewModel.updateLastOpened()
                    if let container = modelContainer {
                        let persistence = PersistenceActor(modelContainer: container)
                        highlightCoordinator = HighlightCoordinator(
                            renderer: highlightRenderer,
                            persistence: persistence,
                            bookFingerprintKey: viewModel.bookFingerprintKey
                        )
                        let records = try? await persistence.fetchHighlights(
                            forBookWithKey: viewModel.bookFingerprintKey
                        )
                        if let records, !records.isEmpty {
                            savedHighlightRecords = records
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let container = modelContainer, viewModel.isDocumentLoaded else { return }
            let persistence = PersistenceActor(modelContainer: container)
            let locator = viewModel.makeCurrentLocator()
            Task {
                do {
                    try await persistence.addBookmark(
                        locator: locator,
                        title: nil,
                        toBookWithKey: viewModel.bookFingerprintKey
                    )
                    HapticFeedbackProvider().triggerLightImpact()
                } catch {}
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            guard viewModel.isDocumentLoaded else { return }
            pageNavigator.nextPage()
            let page = pageNavigator.currentPage
            restoredPage = page
            viewModel.pageDidChange(to: page)
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard viewModel.isDocumentLoaded else { return }
            pageNavigator.previousPage()
            let page = pageNavigator.currentPage
            restoredPage = page
            viewModel.pageDidChange(to: page)
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let page = locator.page else { return }
            restoredPage = page
            viewModel.pageDidChange(to: page)
            // Show search highlight at the match location (bug #43)
            if let textQuote = locator.textQuote,
               !textQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchHighlightText = textQuote
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, newPage in
            readingProgress = PDFProgressHelper.progressForPage(
                currentPageIndex: newPage,
                totalPages: viewModel.totalPages
            )
            // Keep page navigator in sync with PDFView scroll (WI-B09)
            pageNavigator.syncCurrentPage(newPage)
            // Notify ReaderContainerView of the live position for AI panel.
            let locator = viewModel.makeCurrentLocator()
            NotificationCenter.default.post(
                name: .readerPositionDidChange, object: locator
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerTextSelected)) { notification in
            guard let event = notification.object as? ReaderSelectionEvent else { return }
            pendingSelectionEvent = event
            showHighlightSheet = true
        }
        // Bug #88: re-render highlights after annotation import
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightsDidImport)) { _ in
            if let coordinator = highlightCoordinator {
                Task { await coordinator.restoreAll() }
            }
        }
        // Phase R4b: delegate highlight removal to coordinator (fixes bug #87)
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRemoved)) { notification in
            guard let idString = notification.object as? String,
                  let highlightId = UUID(uuidString: idString) else { return }
            if let coordinator = highlightCoordinator {
                Task { await coordinator.handleRemoval(highlightId: highlightId) }
            } else {
                // Fallback: direct renderer removal
                highlightRenderer.remove(id: highlightId)
            }
            savedHighlightRecords?.removeAll { $0.highlightId == highlightId }
        }
        .confirmationDialog(
            "Text Selection",
            isPresented: $showHighlightSheet,
            titleVisibility: .visible
        ) {
            Button("Highlight") {
                guard let event = pendingSelectionEvent,
                      let container = modelContainer else { return }
                handleHighlightAction(event: event, container: container)
            }
            Button("Add Note") {
                noteText = ""
                showNoteSheet = true
            }
            Button("Copy") {
                guard let event = pendingSelectionEvent else { return }
                UIPasteboard.general.string = event.selectedText
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionEvent = nil
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            pdfNoteInputSheet
        }
        .accessibilityIdentifier("pdfReaderContainer")
    }

}
#endif
