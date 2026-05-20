// Purpose: Feature #56 WI-13 — PDF below-page bilingual translation
// panel. PDF is fixed-layout so the paragraph-interlinear renderer
// (`BilingualTextRenderer`) can't reflow page glyphs; this panel is
// the entire user-visible bilingual surface for PDF.
//
// Layout pinned to the design bundle:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-pdf-translation.jsx`
//   — `PDFTranslationPanel` (variant A split-layout).
//
// Header is always visible (38pt). Body switches on
// `PDFBilingualPanelState`:
//   - `.translated([..])` — paragraphs of translation, 13pt serif at
//     85% ink opacity, line-height 1.65 (echoes interlinear hierarchy).
//   - `.loading`          — 3-bar shimmer + "translating…" suffix.
//   - `.offline`          — cloud-off icon + retry + open-AI-tab CTAs.
//   - `.empty`            — image-only-page message.
//   - `.off`              — host doesn't construct the panel.
//
// Key decisions:
// - **Stateless view.** All inputs are passed in by the host; the
//   panel does not subscribe to the bilingual VM directly. The host's
//   `PDFReaderContainerView+Bilingual.swift` extension derives state
//   via `PDFBilingualPanelState.panelState(...)` and rebuilds the
//   panel on `.readerBilingualDidChange` / page changes.
// - **Heights pinned to the design.** 260pt expanded / 38pt collapsed.
//   The host owns the SwiftUI layout via `.safeAreaInset(edge: .bottom)`.
// - **Two CTAs in the offline state.** Retry posts `.readerBilingualRetry`
//   (host calls `vm.retryUnit(currentUnit)`). Open AI tab posts
//   `.readerOpenAITranslate` (no payload — `ReaderContainerView`
//   observes and routes to the AI sheet's `.translate` tab).
//
// @coordinates-with: PDFBilingualPanelState.swift,
//   BilingualLanguage.swift, ReaderThemeV2.swift,
//   ReaderNotifications.swift, BilingualPill.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-pdf-translation.jsx`

#if canImport(UIKit)
import SwiftUI

/// The PDF below-page bilingual translation panel. A pure SwiftUI
/// sub-view; rebuilt by the host whenever VM state or current page
/// changes.
struct PDFBilingualPanel: View {

    /// The visible state of the panel (excluding the orthogonal
    /// collapsed-strip presentation, which is `isCollapsed`).
    let state: PDFBilingualPanelState

    /// Visual-identity-v2 theme tokens for the host book.
    let theme: ReaderThemeV2

    /// Persisted target-language key (one of `BilingualLanguage.all`).
    /// Stale / unknown keys degrade to the first registered language.
    let targetLanguage: String

    /// "Page N" or "Pages M-N" — the header subtitle.
    let pageLabel: String

    /// Whether the body is hidden (header-only strip).
    let isCollapsed: Bool

    /// Tapped on the chevron toggle button.
    let onToggleCollapsed: () -> Void

    /// Tapped on the offline-state Retry button.
    let onRetry: () -> Void

    /// Tapped on the offline-state Open AI tab button.
    let onOpenAITab: () -> Void

    // MARK: - Public API (pinned to PDFBilingualPanelTests)

    static let accessibilityIdentifier = "pdfBilingualPanel"
    static let retryButtonIdentifier = "pdfBilingualPanelRetryButton"
    static let openAITabButtonIdentifier = "pdfBilingualPanelOpenAITabButton"
    static let chevronButtonIdentifier = "pdfBilingualPanelChevron"

    static let expandedHeight: CGFloat = 260
    static let collapsedHeight: CGFloat = 38

    /// Per-state accessibility identifier suffix — `pdfBilingualPanel.<state>`.
    static func identifier(forState state: PDFBilingualPanelState) -> String {
        switch state {
        case .off:        return "pdfBilingualPanel.off"
        case .loading:    return "pdfBilingualPanel.loading"
        case .translated: return "pdfBilingualPanel.translated"
        case .offline:    return "pdfBilingualPanel.offline"
        case .empty:      return "pdfBilingualPanel.empty"
        }
    }

    /// The header's status-suffix text — design canvas labels per
    /// state. `nil` for default (no suffix).
    static func statusSuffix(forState state: PDFBilingualPanelState) -> String? {
        switch state {
        case .off, .translated:
            return nil
        case .loading:
            return "translating…"
        case .offline:
            return "offline"
        case .empty:
            return "no text on page"
        }
    }

    /// Resolves the language key's glyph; falls back to the first
    /// language entry if the key is unknown (mirrors `BilingualPill`).
    static func glyph(forLanguage key: String) -> String {
        BilingualLanguage.findOrDefault(key: key).glyph
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                    .background(Color(theme.ruleColor))
                bodyView
            }
        }
        .frame(maxWidth: .infinity)
        .background(panelBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(theme.ruleColor)),
            alignment: .top
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            languageChip
            pageLabelLine
            Spacer(minLength: 0)
            chevronButton
        }
        .padding(.horizontal, 16)
        .frame(height: Self.collapsedHeight)
    }

    @ViewBuilder
    private var languageChip: some View {
        let glyph = Self.glyph(forLanguage: targetLanguage)
        HStack(spacing: 4) {
            Text("EN")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(
                    Circle().fill(Color(theme.accentColor))
                )
            Text("↔")
                .font(.system(size: 9))
                .foregroundStyle(Color(theme.accentColor).opacity(0.7))
            Text(glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(theme.accentColor))
        }
        .padding(.leading, 3)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color(theme.accentColor).opacity(0.10))
        )
    }

    @ViewBuilder
    private var pageLabelLine: some View {
        let suffix = Self.statusSuffix(forState: state)
        HStack(spacing: 6) {
            Text(pageLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color(theme.subColor))
                .kerning(0.3)
            if let suffix {
                Text("· \(suffix)")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(
                        state == .loading
                            ? Color(theme.accentColor)
                            : Color(theme.subColor)
                    )
            }
        }
    }

    @ViewBuilder
    private var chevronButton: some View {
        Button(action: onToggleCollapsed) {
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand translation" : "Collapse translation")
        .accessibilityIdentifier(Self.chevronButtonIdentifier)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyView: some View {
        Group {
            switch state {
            case .off:
                EmptyView()
            case .translated(let segments):
                PDFBilingualTranslatedBody(theme: theme, segments: segments)
            case .loading:
                PDFBilingualLoadingBody(theme: theme)
            case .offline:
                PDFBilingualOfflineBody(
                    theme: theme,
                    onRetry: onRetry,
                    onOpenAITab: onOpenAITab
                )
            case .empty:
                PDFBilingualEmptyBody(theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier(Self.identifier(forState: state))
    }

    // MARK: - Background

    private var panelBackground: Color {
        // 2.5% alpha overlay so the panel reads as a sub-surface
        // within the same tonal family as the reader frame.
        if theme.isDark {
            return Color.white.opacity(0.025)
        } else {
            return Color(red: 20/255, green: 14/255, blue: 4/255).opacity(0.025)
        }
    }
}

// MARK: - Body subviews (kept small so the file stays under ~300 LOC
//          — they live in PDFBilingualPanelBodies.swift)

#endif
