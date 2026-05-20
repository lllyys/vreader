// Purpose: Feature #60 WI-6b — re-skinned top reader chrome. Floats
// as an overlay above the reader content (no safe-area impact, same
// as the legacy `ReaderChromeBar` it replaces). Feature #56 WI-9
// extends it with an inline `BilingualPill` next to the title when
// bilingual mode is on for the open book.
//
// Layout mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`
// `ReaderTopChrome` + the #760 design supplement
// (`design-notes/reader-search-and-more-menu.md`) + feature #56 WI-9
// (`vreader-bilingual.jsx`):
//
//   ← Library  |  Title [EN ↔ 中]  |  🔍  📑  ⋯
//
// The four shed actions (Contents / Notes / Display / AI) move to
// `ReaderBottomChrome`. The ⋯ More button toggles the anchored
// `ReaderMorePopover` (Feature #60 WI-6c) via its `onMore` closure;
// `moreActive` draws the design's backdrop tint while it is open. The
// pill renders only when both `bilingualActive` is `true` AND a
// language is resolved (`shouldShowBilingualPill`).
//
// @coordinates-with: ReaderBottomChrome.swift, ReaderChromeButton.swift,
//   ReaderThemeV2.swift, ReaderSafeAreaResolver.swift,
//   ReaderMorePopover.swift, ReaderContainerView+Sheets.swift
//   (composition site), BilingualPill.swift, BilingualLanguage.swift

import SwiftUI

/// Re-skinned top reader chrome (Feature #60 WI-6b). Composed once,
/// format-agnostic, in `ReaderContainerView`'s chrome overlay.
struct ReaderTopChrome: View {
    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2
    /// Book title shown in the centered italic label.
    let title: String
    /// Whether the current reading position carries a bookmark — drives
    /// the filled vs. outline bookmark glyph. WI-6b callers pass `false`
    /// (the bookmark button posts a fire-and-forget request); wiring the
    /// live filled state is a tracked follow-up.
    let bookmarked: Bool
    /// Whether the ⋯ More control is the active popover anchor — draws
    /// the 6 % backdrop tint from the design.
    let moreActive: Bool
    /// Feature #56 WI-9 — whether bilingual reading mode is currently
    /// on for the open book. Combined with `bilingualLanguage` via
    /// `shouldShowBilingualPill(...)` to gate the pill render path.
    let bilingualActive: Bool
    /// Feature #56 WI-9 — the persisted target-language key from
    /// `PerBookSettings.bilingualTargetLanguage`. `nil` (book never
    /// configured / transient host state) suppresses the pill even
    /// when `bilingualActive` is `true`.
    let bilingualLanguage: String?
    let onBack: () -> Void
    let onSearch: () -> Void
    let onBookmark: () -> Void
    let onMore: () -> Void

    /// Convenience initialiser keeping the pre-WI-9 call sites
    /// (`bilingualActive` defaults to `false`, no pill rendered) so
    /// callers that don't yet wire bilingual state compile without
    /// edits. The full initialiser is preferred — synthesised default
    /// keeps that to one call site (`ReaderContainerView+Sheets`).
    init(
        theme: ReaderThemeV2,
        title: String,
        bookmarked: Bool,
        moreActive: Bool,
        bilingualActive: Bool = false,
        bilingualLanguage: String? = nil,
        onBack: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onBookmark: @escaping () -> Void,
        onMore: @escaping () -> Void
    ) {
        self.theme = theme
        self.title = title
        self.bookmarked = bookmarked
        self.moreActive = moreActive
        self.bilingualActive = bilingualActive
        self.bilingualLanguage = bilingualLanguage
        self.onBack = onBack
        self.onSearch = onSearch
        self.onBookmark = onBookmark
        self.onMore = onMore
    }

    var body: some View {
        VStack(spacing: 0) {
            // Background fill under the Dynamic Island / notch — the
            // window inset is read directly because the parent applies
            // `.ignoresSafeArea(.top)`, which zeroes GeometryReader.
            chromeBackground
                .frame(height: ReaderSafeAreaResolver.windowSafeAreaTop)

            HStack(spacing: 0) {
                backButton
                titleWithPill
                    .frame(maxWidth: .infinity)
                trailingButtons
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .background(chromeBackground)
            .overlay(alignment: .bottom) {
                Color(theme.ruleColor).frame(height: 0.5)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bilingual pill helpers (Feature #56 WI-9)

    /// Whether to render `BilingualPill` for these inputs. Pure +
    /// static so tests pin the predicate without spinning up SwiftUI.
    ///
    /// Off → never render. On + nil language → never render
    /// (transient host state — safer to suppress than draw an empty
    /// pill). On + a key → render.
    static func shouldShowBilingualPill(
        bilingualActive: Bool,
        bilingualLanguage: String?
    ) -> Bool {
        guard bilingualActive else { return false }
        guard let key = bilingualLanguage, !key.isEmpty else { return false }
        return true
    }

    /// Resolves a per-book persisted language key through the registry
    /// fallback — the same fallback `BilingualPill` applies internally.
    /// Exposed so a chrome consumer can mirror the displayed language
    /// (e.g., XCUITest harnesses asserting the resolved key).
    static func resolvedPillLanguage(for language: String) -> String {
        BilingualLanguage.findOrDefault(key: language).key
    }

    // MARK: - Background

    /// Chrome surface: the theme `chrome` token, or a dark scrim over a
    /// Photo-theme background image so the chrome stays legible.
    private var chromeBackground: Color {
        theme.usesBackgroundImage
            ? Color.black.opacity(0.55)
            : Color(theme.chromeColor)
    }

    // MARK: - Back button

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text("Library")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Color(theme.accentColor))
            .padding(.vertical, 6)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Back to library")
        .accessibilityIdentifier(ReaderTopChromeSlot.back.accessibilityIdentifier)
    }

    // MARK: - Title

    /// Title + (optional) bilingual pill. The pill sits inline with
    /// the title text per design — `display: inline-flex` in the JSX
    /// — so it consumes a slice of the title block's flexible width
    /// rather than reserving a fixed lane.
    private var titleWithPill: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                .fontWeight(.semibold)
                .italic()
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .accessibilityIdentifier(ReaderTopChromeSlot.title.accessibilityIdentifier)
            if Self.shouldShowBilingualPill(
                bilingualActive: bilingualActive,
                bilingualLanguage: bilingualLanguage
            ), let resolvedKey = bilingualLanguage {
                BilingualPill(
                    theme: theme,
                    language: BilingualLanguage.findOrDefault(key: resolvedKey).key
                )
            }
        }
    }

    // MARK: - Trailing icon buttons

    private var trailingButtons: some View {
        HStack(spacing: 0) {
            iconButton(
                systemName: "magnifyingglass",
                size: 18,
                tint: Color(theme.inkColor),
                label: "Search in book",
                slot: .search,
                action: onSearch
            )
            iconButton(
                systemName: bookmarked ? "bookmark.fill" : "bookmark",
                size: 18,
                tint: bookmarked ? Color(theme.accentColor) : Color(theme.inkColor),
                label: bookmarked ? "Remove bookmark" : "Add bookmark",
                slot: .bookmark,
                action: onBookmark
            )
            iconButton(
                systemName: "ellipsis",
                size: 20,
                tint: Color(theme.inkColor),
                label: "More",
                slot: .more,
                action: onMore,
                activeBackground: moreActive
            )
        }
    }

    /// A 36×36 circular chrome icon button matching the design's
    /// `iconBtnStyle`. `activeBackground` paints the design's faint
    /// backdrop tint (used by ⋯ while its popover is open).
    private func iconButton(
        systemName: String,
        size: CGFloat,
        tint: Color,
        label: String,
        slot: ReaderTopChromeSlot,
        action: @escaping () -> Void,
        activeBackground: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background {
                    if activeBackground {
                        Circle().fill(
                            theme.isDark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.06)
                        )
                    }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(slot.accessibilityIdentifier)
    }
}
