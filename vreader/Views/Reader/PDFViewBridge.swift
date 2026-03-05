// Purpose: UIViewRepresentable wrapping PDFKit's PDFView for PDF rendering.
// Provides page change notifications, page navigation, zoom control,
// and password unlock delegation back to the ViewModel.
//
// Key decisions:
// - Uses PDFKit (system framework) for rendering — no third-party dependencies.
// - Coordinator calls ViewModel directly (avoids protocol conformance issues on struct).
// - Page change notification via NotificationCenter (PDFViewPageChanged).
// - Zoom level configurable; defaults to autoScale for fit-width.
// - Non-editable: read-only display mode.
// - restorePage applied once after document loads.
//
// @coordinates-with: PDFReaderViewModel.swift, PDFReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI
import PDFKit

/// SwiftUI wrapper for PDFKit's PDFView.
struct PDFViewBridge: UIViewRepresentable {
    let url: URL
    var restorePage: Int?
    var password: String?
    /// Incremented on each password submission to trigger re-unlock even with same password.
    var passwordAttemptId: Int = 0
    let viewModel: PDFReaderViewModel

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Accessibility
        pdfView.accessibilityIdentifier = "pdfView"

        context.coordinator.pdfView = pdfView
        context.coordinator.viewModel = viewModel

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        loadDocument(into: pdfView, coordinator: context.coordinator)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Handle password retry: if attempt ID changed, try unlocking
        if let password,
           passwordAttemptId != context.coordinator.lastPasswordAttemptId,
           let document = pdfView.document, document.isLocked {
            context.coordinator.lastPasswordAttemptId = passwordAttemptId
            let unlocked = document.unlock(withPassword: password)
            if unlocked {
                let totalPages = document.pageCount
                viewModel.passwordAccepted(totalPages: totalPages)
                // Restore page after unlock
                if let page = restorePage,
                   page < document.pageCount,
                   let pdfPage = document.page(at: page) {
                    pdfView.go(to: pdfPage)
                }
            } else {
                viewModel.passwordRejected()
            }
        }

        // Navigate to page if requested and not yet applied
        if let page = restorePage,
           context.coordinator.lastRestoredPage != page,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.lastRestoredPage = page
            if page < document.pageCount, let pdfPage = document.page(at: page) {
                pdfView.go(to: pdfPage)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private func loadDocument(into pdfView: PDFView, coordinator: Coordinator) {
        let fileURL = url
        let pwd = password
        let restorePage = restorePage
        let viewModel = viewModel

        Task.detached {
            guard let document = PDFDocument(url: fileURL) else {
                await MainActor.run {
                    viewModel.documentDidFailToLoad(error: "Failed to load PDF document.")
                }
                return
            }

            await MainActor.run {
                pdfView.document = document

                if document.isLocked {
                    if let pwd, document.unlock(withPassword: pwd) {
                        viewModel.documentDidLoad(totalPages: document.pageCount)
                    } else {
                        viewModel.documentNeedsPassword()
                    }
                } else {
                    let totalPages = document.pageCount
                    viewModel.documentDidLoad(totalPages: totalPages)

                    if let page = restorePage, page < totalPages,
                       let pdfPage = document.page(at: page) {
                        coordinator.lastRestoredPage = page
                        pdfView.go(to: pdfPage)
                    }
                }
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var viewModel: PDFReaderViewModel?
        weak var pdfView: PDFView?
        /// Tracks the last restored page to avoid re-applying on every updateUIView.
        var lastRestoredPage: Int?
        /// Tracks the last password attempt ID to detect retries (including same password).
        var lastPasswordAttemptId: Int = 0

        @objc func pageDidChange(_ notification: Notification) {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }
            let pageIndex = document.index(for: currentPage)
            viewModel?.pageDidChange(to: pageIndex)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
