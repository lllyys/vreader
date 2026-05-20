// Purpose: Feature #67 — the design's profile-header card,
// `ProfileCardLibrary` (`vreader-profile-stats.jsx`). A self-contained
// SwiftUI view: a 48pt three-book-spine glyph tile, the "Your library"
// serif-italic header, the "N books · Nh read this month" subline, and
// a trailing pill Stats button.
//
// Identity model: #862 resolved the Settings profile card to
// "Library-as-identity" (Option A) — the card represents the LIBRARY,
// not a person. The header is the fixed serif-italic "Your library";
// the avatar slot is the three-book-spine glyph. No name, no account.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-profile-stats.jsx` (`ProfileCardLibrary`).
//
// Key decisions:
// - **Pure presentation.** The card takes its two numbers as init
//   values and a `onOpenStats` closure — it fetches nothing and posts
//   nothing. WI-3's `SettingsHeaderViewModel` supplies the numbers;
//   WI-4's `SettingsView` supplies the closure (which posts the Stats
//   hand-off notification). Taking explicit values (not a hard-coded
//   "Your library") also keeps the #862 Option-B forward path open.
// - **Subline reuses `ReadingTimeFormatter.formatCompactHours`** (WI-1)
//   for the hour token, so the "this month" copy is consistent with
//   the rest of the app's reading-time formatting.
// - **Singular/plural** — "1 book" vs "N books" with a simple English
//   rule (the app is English-only per AGENTS.md).
// - **Serif-italic header** uses `ReaderTypography.body(for:.sourceSerif4)`
//   — the same Source Serif 4 path `ReaderSheetChrome`'s title uses.
// - **Card / tile / pill fills mirror the JSX formulas verbatim**
//   (`SettingsProfileCardColors`) rather than substituting repo theme
//   tokens — `ProfileCardLibrary` specifies explicit fills (`#fff` /
//   `rgba(255,255,255,0.04)` card, etc.), and rule 51 wants the
//   designed values, not an approximation.
// - `*ForTesting` seams (`statsActionForTesting`, `headerTextForTesting`,
//   `sublineTextForTesting`) expose the closure + copy so the
//   composition test asserts them without a render path.
//
// @coordinates-with: SettingsHeaderViewModel.swift, SettingsView.swift,
//   ReadingTimeFormatter.swift, ReaderTypography.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`

import SwiftUI

/// The design's library-identity profile-header card.
struct SettingsProfileCard: View {

    /// The fixed header copy — the library-identity model (#862 Option
    /// A) never shows a user name.
    static let headerText = "Your library"

    private let theme: ReaderThemeV2
    private let bookCount: Int
    private let monthReadingSeconds: Int
    private let onOpenStats: () -> Void

    /// - Parameters:
    ///   - theme: the sheet theme (Settings is always `.paper`).
    ///   - bookCount: the library book count for the subline.
    ///   - monthReadingSeconds: this calendar month's reading seconds.
    ///   - onOpenStats: invoked when the Stats pill is tapped.
    init(
        theme: ReaderThemeV2,
        bookCount: Int,
        monthReadingSeconds: Int,
        onOpenStats: @escaping () -> Void
    ) {
        self.theme = theme
        self.bookCount = bookCount
        self.monthReadingSeconds = monthReadingSeconds
        self.onOpenStats = onOpenStats
    }

    // MARK: - Testing seams

    /// The closure the Stats button is wired to. A closure-only seam —
    /// it confirms the card invokes `onOpenStats`; the card posts no
    /// notification (that is WI-4's `SettingsView` wiring).
    var statsActionForTesting: () -> Void { onOpenStats }

    /// The header copy the card renders — always `Self.headerText`.
    var headerTextForTesting: String { Self.headerText }

    /// The subline copy the card renders.
    var sublineTextForTesting: String { sublineText }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            glyphTile
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.headerText)
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 16)))
                    .fontWeight(.semibold)
                    .italic()
                    .foregroundStyle(Color(theme.inkColor))
                Text(sublineText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(theme.subColor))
            }
            Spacer(minLength: 8)
            statsButton
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsProfileCardColors.cardBackground(isDark: theme.isDark))
        )
    }

    // MARK: - Subviews

    /// The 48pt rounded tile holding the three-book-spine library glyph.
    private var glyphTile: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(SettingsProfileCardColors.glyphTileFill(isDark: theme.isDark))
            .frame(width: 48, height: 48)
            .overlay { ThreeBookSpineGlyph(theme: theme) }
    }

    /// The trailing pill-shaped Stats button.
    private var statsButton: some View {
        Button(action: onOpenStats) {
            Text("Stats")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(theme.inkColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(SettingsProfileCardColors.statsPillFill(isDark: theme.isDark))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsProfileStatsButton")
    }

    // MARK: - Copy

    /// "{N} books · {hours} read this month" — singular "book" at N == 1.
    private var sublineText: String {
        let bookWord = bookCount == 1 ? "book" : "books"
        let hours = ReadingTimeFormatter.formatCompactHours(totalSeconds: monthReadingSeconds)
        return "\(bookCount) \(bookWord) · \(hours) read this month"
    }
}

// MARK: - Card fills

/// The design's explicit `ProfileCardLibrary` fills, mirroring the JSX
/// formulas verbatim (`vreader-profile-stats.jsx`). Kept as a named
/// helper so the composition test can pin the exact colors and the card
/// uses the *designed* fills rather than substituted theme tokens.
enum SettingsProfileCardColors {

    /// Card background — design `t.isDark ? 'rgba(255,255,255,0.04)' : '#fff'`.
    static func cardBackground(isDark: Bool) -> Color {
        isDark
            ? Color(.sRGB, white: 1.0, opacity: 0.04)
            : Color(.sRGB, white: 1.0, opacity: 1.0)
    }

    /// Glyph-tile fill — design
    /// `t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'`.
    static func glyphTileFill(isDark: Bool) -> Color {
        isDark
            ? Color(.sRGB, white: 1.0, opacity: 0.06)
            : Color(.sRGB, white: 0.0, opacity: 0.04)
    }

    /// Stats-pill fill — design
    /// `t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(60,40,20,0.08)'`.
    static func statsPillFill(isDark: Bool) -> Color {
        isDark
            ? Color(.sRGB, white: 1.0, opacity: 0.08)
            : Color(.sRGB, red: 60 / 255.0, green: 40 / 255.0, blue: 20 / 255.0, opacity: 0.08)
    }
}

// MARK: - Library glyph

/// The design's three-book-spine library glyph — three rounded
/// vertical bars of staggered height, mirroring the `<svg>` in
/// `ProfileCardLibrary`.
private struct ThreeBookSpineGlyph: View {
    let theme: ReaderThemeV2

    var body: some View {
        // The design SVG is 22×26 with three rects:
        //   x0.6  y3  6×20  fill accent
        //   x7.6  y0.6 6×22.4 fill dimmed-ink
        //   x14.6 y5  6×18  fill warm-brown
        HStack(alignment: .center, spacing: 1) {
            spine(height: 20, color: Color(theme.accentColor))
            spine(height: 22.4, color: Color(theme.inkColor).opacity(theme.isDark ? 0.7 : 0.5))
            spine(height: 18, color: warmBrown)
        }
        .frame(width: 22, height: 26)
    }

    /// One book spine — a 6pt-wide rounded bar of the given height.
    private func spine(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 6, height: height)
    }

    /// The design's third-spine color — `#8c6a4a` dark / `#5a3a3a` light.
    private var warmBrown: Color {
        theme.isDark
            ? Color(.sRGB, red: 0x8c / 255.0, green: 0x6a / 255.0, blue: 0x4a / 255.0)
            : Color(.sRGB, red: 0x5a / 255.0, green: 0x3a / 255.0, blue: 0x3a / 255.0)
    }
}
