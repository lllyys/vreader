// Purpose: Feature #60 visual-identity v2 (WI-10) — the reusable sheet
// chrome shared by the 5 re-skinned app sheets (Display / TOC /
// Annotations / AI / App Settings). Mirrors the design bundle's `Sheet`
// wrapper component.
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-panels.jsx` (`Sheet`):
//   - 22pt rounded top corners.
//   - theme-aware surface — `#222020` for dark-family themes, `#fcf8f0`
//     for light-family themes (design's `t.isDark ? '#222020' :
//     '#fcf8f0'`).
//   - an optional title bar with a centred 17pt Source Serif 4 title
//     and `leading` / `trailing` 50pt slots, divided from the body by
//     a 0.5pt hairline.
//   - a scrollable body region.
//
// Key decisions:
// - **The slide-up + drag grabber come from SwiftUI's own `.sheet` +
//   `.presentationDragIndicator(.visible)`.** The design's `Sheet`
//   re-implements the platform sheet for the web; on iOS the platform
//   already provides the slide-up animation, the dimmed backdrop, and
//   the drag grabber. This component supplies only what the platform
//   sheet does NOT: the design's title bar and theme-tinted surface.
//   Re-drawing a grabber would double it against the system one.
// - **Theme is an input.** Reader sheets pass the book's
//   `ReaderThemeV2`; the App Settings sheet (presented from the
//   non-theme-switchable Library) passes `.paper`, matching the
//   design's `SettingsSheet` default (`theme || THEMES.paper`).
// - **`titleBar` is optional** — the AI sheet draws its own custom
//   header (sparkle avatar) so it omits the standard title bar, exactly
//   as the design's `AISheet` does.
//
// @coordinates-with: ReaderSettingsPanel.swift, TOCSheet.swift,
//   HighlightsSheet.swift, AIReaderPanel.swift, SettingsView.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import SwiftUI

/// Shared sheet chrome — a theme-tinted surface with an optional
/// design title bar and a scrollable body. Wraps the content of the
/// 5 feature-#60 re-skinned sheets.
struct ReaderSheetChrome<Body: View, Leading: View, Trailing: View>: View {
    /// Visual-identity-v2 theme tokens for the sheet surface + ink.
    let theme: ReaderThemeV2
    /// Centred title — when nil, the title bar is omitted entirely
    /// (the AI sheet draws its own header).
    let title: String?
    /// Leading title-bar slot — a 50pt-wide region (e.g. an action
    /// button). Defaults to empty.
    let leading: Leading
    /// Trailing title-bar slot — a 50pt-wide region (e.g. a Done or
    /// Share button). Defaults to empty — and when empty, if `onClose`
    /// is provided, the design's default circular close button fills
    /// the slot (`vreader-panels.jsx` `Sheet`'s `trailing || <button>`).
    let trailing: Trailing
    /// Optional explicit-close action. When set and `trailing` is the
    /// empty default, the title bar shows the design's circular close
    /// button — matching the design `Sheet`'s fallback affordance.
    let onClose: (() -> Void)?
    /// The scrollable sheet body.
    @ViewBuilder let content: () -> Body

    init(
        theme: ReaderThemeV2,
        title: String?,
        onClose: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Body
    ) {
        self.theme = theme
        self.title = title
        self.onClose = onClose
        self.leading = leading()
        self.trailing = trailing()
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                titleBar(title)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(theme.sheetSurfaceColor).ignoresSafeArea())
    }

    // MARK: - Title bar

    /// The design's title bar: a 50pt leading slot, a centred 17pt
    /// Source Serif 4 title, a 50pt trailing slot, and a 0.5pt
    /// hairline beneath.
    private func titleBar(_ title: String) -> some View {
        HStack(spacing: 0) {
            leading
                .frame(width: 50, alignment: .leading)
            Text(title)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 17)))
                .fontWeight(.semibold)
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            trailingSlot
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Color(theme.ruleColor).frame(height: 0.5)
        }
    }

    /// The trailing title-bar slot. A caller-supplied `trailing` view
    /// takes precedence; otherwise, when `onClose` is set, the design's
    /// default circular close button fills the slot (the design
    /// `Sheet`'s `trailing || <close button>` fallback).
    @ViewBuilder
    private var trailingSlot: some View {
        if Trailing.self == EmptyView.self, let onClose {
            closeButton(onClose)
        } else {
            trailing
        }
    }

    /// The design's default sheet close button — a 28pt circular
    /// faint-wash disc with an `xmark` glyph (`vreader-panels.jsx`
    /// `Sheet`).
    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(
                        theme.isDark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06)
                    )
                )
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("sheetCloseButton")
    }
}

// MARK: - Sheet surface token

extension ReaderThemeV2 {
    /// Sheet surface fill — the design's `Sheet` uses a hardcoded
    /// `#222020` for the dark-family themes and `#fcf8f0` for the
    /// light-family themes (`vreader-panels.jsx`: `t.isDark ?
    /// '#222020' : '#fcf8f0'`). Distinct from `paperColor` /
    /// `chromeColor` because a sheet floats above everything and the
    /// design gives it its own elevation tint.
    var sheetSurfaceColor: UIColor {
        isDark
            ? UIColor(red: 0x22 / 255, green: 0x20 / 255, blue: 0x20 / 255, alpha: 1)
            : UIColor(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255, alpha: 1)
    }

    /// Grouped-section card fill — the surface the design's `SettingsSheet`
    /// draws BEHIND each group of rows, elevated above `sheetSurfaceColor`
    /// (`vreader-panels.jsx`: card `background: t.isDark ?
    /// 'rgba(255,255,255,0.04)' : '#fff'`). App Settings pins the light
    /// `.paper` theme, so without this the grouped `Section` rows fall
    /// through to the appearance-aware system
    /// `secondarySystemGroupedBackground` — charcoal in Dark Mode, which
    /// renders the near-black `.paper` row labels nearly invisible
    /// (Bug #297 / GH #1328). Set as each Section's `.listRowBackground`.
    var sheetCardSurfaceColor: UIColor {
        isDark
            ? UIColor(white: 1, alpha: 0.04)
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
}
