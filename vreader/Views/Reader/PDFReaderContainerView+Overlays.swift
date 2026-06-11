// Purpose: Password, loading, error overlays, progress bar, and bottom overlay
// for PDFReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: PDFReaderContainerView.swift, PDFPasswordPromptView.swift,
//   ReadingProgressBar.swift, PDFProgressHelper.swift, PDFReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI

extension PDFReaderContainerView {

    // MARK: - Overlays

    @ViewBuilder
    var passwordOverlay: some View {
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
    var loadingOverlay: some View {
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

    func errorOverlay(message: String) -> some View {
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

    /// Feature #60 WI-6b: shared bottom chrome (scrubber + labels +
    /// Contents/Notes/Display/AI toolbar) replaces the legacy PDF
    /// progress bar + page-indicator overlay. Page-snap seek and the
    /// "Page X of Y" label are preserved; the pages/hour stat is
    /// dropped — the v2 design's two-label row has no slot for it.
    @ViewBuilder
    var bottomOverlay: some View {
        // Bug #214 / GH #834: do NOT apply a container `.accessibilityIdentifier`
        // here. A container identifier on `ReaderBottomChrome` propagates
        // onto every descendant accessibility element, overriding the
        // toolbar buttons' own identifiers (`readerDisplayButton` /
        // `readerNotesButton` — set inside `ReaderBottomChrome`) so XCUITest
        // cannot resolve them. TXT/MDReaderContainerView mount the same
        // chrome with no wrapping identifier; EPUB/PDF now match. The
        // former `pdfBottomOverlay` identifier had no test consumer.
        ReaderBottomChrome(
            theme: settingsStore?.theme ?? .paper,
            progress: $readingProgress,
            onSeek: { seekValue in
                let targetPage = PDFProgressHelper.pageForSeekValue(
                    seekValue: seekValue, totalPages: viewModel.totalPages
                )
                restoredPage = targetPage
                viewModel.pageDidChange(to: targetPage)
            },
            discreteSteps: PDFProgressHelper.discreteSteps(totalPages: viewModel.totalPages),
            leadingLabel: PDFProgressHelper.pageLabel(
                currentPageIndex: viewModel.currentPageIndex,
                totalPages: viewModel.totalPages
            ),
            // Feature #101: the trailing slot is the pages readout — the
            // design's canonical "N pages left in book"; session time lives
            // inside the time readout.
            trailingLabel: pdfPagesLeftReadout,
            timeTrailingLabel: viewModel.timeReadoutDisplay,
            bookFingerprintKey: viewModel.bookFingerprintKey,
            perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
        )
    }

    /// Feature #101: "N pages left in book" — the design's canonical pages
    /// readout. The string form stays uniform for every count (Gate-4 r1
    /// Medium: no "Last page" substitution); only singular grammar varies.
    private var pdfPagesLeftReadout: String {
        let left = max(0, viewModel.totalPages - viewModel.currentPageIndex - 1)
        return left == 1 ? "1 page left in book" : "\(left) pages left in book"
    }
}
#endif
