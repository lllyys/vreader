// Purpose: Chapter-title overlay for TXTReaderContainerView.
//
// Key decisions:
// - Chapter title overlay at top of screen, only shown when chrome is visible.
//
// Feature #60 WI-6b note: `ChapterBottomOverlay` (the legacy
// prev/next chapter-nav bar) was removed here — the shared
// `ReaderBottomChrome` replaced it, and chapter navigation moved to
// the Contents (TOC) toolbar button.
//
// @coordinates-with: TXTReaderContainerView.swift, ReaderSettingsStore.swift

#if canImport(UIKit)
import SwiftUI

// MARK: - Chapter Title Overlay

/// Small overlay showing the current chapter title at the top of the reader screen.
struct ChapterTitleOverlay: View {
    let title: String
    let settingsStore: ReaderSettingsStore?

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(backgroundColor.opacity(0.92))
            .accessibilityIdentifier("txtChapterTitleOverlay")
    }

    private var backgroundColor: Color {
        Color(settingsStore?.theme.backgroundColor ?? ReaderTheme.default.backgroundColor)
    }
}
#endif
