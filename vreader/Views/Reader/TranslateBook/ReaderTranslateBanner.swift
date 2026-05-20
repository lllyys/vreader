// Purpose: Feature #56 WI-14 — the top-of-page reader banner shown
// whenever the open book has a global translate-entire-book job in
// flight. Tapping the banner opens the status sheet; the trailing close
// button presents the cancel-confirmation alert.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`
// (`ReaderTranslateBanner`).
//
// @coordinates-with: BookTranslationViewModel.swift,
//   BookTranslationProgress.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`

#if canImport(UIKit)
import SwiftUI

/// Reader top-of-page banner — appears whenever a global translate-book
/// job is in flight for the open book.
struct ReaderTranslateBanner: View {

    /// Latest progress snapshot for the open book.
    let progress: BookTranslationProgress
    let targetLanguageLabel: String
    let theme: ReaderThemeV2

    /// Tap the banner body — host opens the status sheet.
    let onOpen: () -> Void
    /// Tap the trailing close pill — host presents the cancel alert.
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(Color(theme.accentColor))
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))
                        .lineLimit(1)
                    progressBar
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            cancelButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .accessibilityIdentifier("readerTranslateBanner")
    }

    private var headerText: String {
        "Translating to \(targetLanguageLabel) \u{00b7} \(progress.completed) / \(progress.total)"
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.isDark
                          ? Color.white.opacity(0.10)
                          : Color.black.opacity(0.08))
                Capsule()
                    .fill(Color(theme.accentColor))
                    .frame(width: max(0, proxy.size.width * CGFloat(progress.fraction)))
            }
        }
        .frame(height: 3)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(theme.isDark
                                  ? Color.white.opacity(0.08)
                                  : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel translation")
        .accessibilityIdentifier("readerTranslateBannerCancel")
    }

    private var bannerBackground: Color {
        theme.isDark
            ? Color(red: 0x28 / 255, green: 0x26 / 255, blue: 0x22 / 255).opacity(0.94)
            : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255).opacity(0.96)
    }

    private var borderColor: Color {
        theme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }
}
#endif
