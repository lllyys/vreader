// Purpose: Bottom chrome, progress-bar helpers, and seek handling for
// EPUBReaderContainerView. Feature #60 WI-6b swapped the legacy
// ReadingProgressBar + chapter-nav row for the shared `ReaderBottomChrome`.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBProgressCalculator.swift,
//   ReaderBottomChrome.swift, EPUBReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    /// Feature #60 WI-6b: shared bottom chrome (scrubber + labels +
    /// Contents/Notes/Display/AI toolbar) replaces the legacy
    /// ReadingProgressBar + chapter-navigation row. Chapter prev/next
    /// relocates to the Contents (TOC) toolbar button per the v2
    /// design; the "Chapter X of Y" position shows in the leading
    /// label. The offset-based `navigateChapter` / `currentChapterTitle`
    /// helpers were removed with the prev/next buttons — they had no
    /// other caller (scrubber seeks go through `handleProgressSeek`).
    @ViewBuilder
    var bottomOverlay: some View {
        // Bug #214 / GH #834: do NOT apply a container `.accessibilityIdentifier`
        // here. A container identifier on `ReaderBottomChrome` propagates
        // onto every descendant accessibility element, overriding the
        // toolbar buttons' own identifiers (`readerDisplayButton` /
        // `readerNotesButton` — set inside `ReaderBottomChrome`) so XCUITest
        // cannot resolve them. TXT/MDReaderContainerView mount the same
        // chrome with no wrapping identifier; EPUB/PDF now match. The
        // former `epubBottomOverlay` identifier had no test consumer.
        ReaderBottomChrome(
            theme: settingsStore?.theme ?? .paper,
            progress: $readingProgress,
            onSeek: { handleProgressSeek($0) },
            discreteSteps: epubDiscreteSteps,
            leadingLabel: epubProgressLabel ?? "",
            trailingLabel: viewModel.sessionTimeDisplay ?? ""
        )
    }

    // MARK: - Progress Bar

    /// Discrete steps for the progress bar: spine count for multi-chapter, nil for single/empty.
    var epubDiscreteSteps: Int? {
        guard let meta = viewModel.metadata else { return nil }
        return EPUBProgressCalculator.discreteSteps(totalSpineItems: meta.spineCount)
    }

    /// "Chapter X of Y" label for the progress bar, or nil if no metadata.
    var epubProgressLabel: String? {
        guard let meta = viewModel.metadata else { return nil }
        return EPUBProgressCalculator.label(
            spineIndex: viewModel.currentSpineIndex,
            totalSpineItems: meta.spineCount
        )
    }

    // MARK: - Seek

    /// Handles seeking from the progress bar scrubber.
    /// Maps the seek value to a spine index and scroll fraction, then navigates there.
    func handleProgressSeek(_ seekValue: Double) {
        guard let meta = viewModel.metadata,
              let base = resourceBase,
              meta.spineCount > 0 else { return }
        let target = EPUBProgressCalculator.seekTarget(
            seekValue: seekValue,
            totalSpineItems: meta.spineCount
        )
        let targetIndex = target.spineIndex
        guard targetIndex >= 0, targetIndex < meta.spineItems.count else { return }

        viewModel.navigateToSpine(index: targetIndex)
        webViewError = nil

        let href = meta.spineItems[targetIndex].href
        Task { await ensureChapterExtracted(href: href) } // bug #102
        // Apply scrollFraction so EPUBWebViewBridge scrolls within the chapter
        seekScrollFraction = target.scrollFraction
        contentURL = base.appendingPathComponent(href)
        readingProgress = seekValue
    }
}
#endif
