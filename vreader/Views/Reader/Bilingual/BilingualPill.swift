// Purpose: Feature #56 WI-9 — the `EN ↔ 中` reader-top-chrome pill
// shown when bilingual mode is on. Renders inline with the title
// label in `ReaderTopChrome`, so the reader chrome carries a stable
// affordance for "this book is rendering bilingual right now".
//
// Layout pinned to the design bundle:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BilingualPill` (~280–305 in the JSX).
//   - 100pt corner radius — fully pill-shaped.
//   - 2pt vertical padding · 4pt left + 8pt right padding.
//   - 6pt left margin from the title.
//   - Accent-tinted background at 10% (`t.accent + 1a` hex alpha).
//   - Two glyphs: a solid accent rounded-square with white `EN`,
//     a dimmed `↔` joiner, then the target glyph in the script's
//     serif family.
//
// Key decisions:
// - **Stateless view.** All inputs are passed in by the chrome host;
//   the pill does not subscribe to the bilingual VM directly. The
//   chrome wraps `bilingualActive: Bool` + `bilingualLanguage: String?`
//   in its own `shouldShowBilingualPill(...)` and constructs the pill
//   only when both resolve.
// - **Source side is always `EN`** in current scope — translation
//   direction is English → target. A future bidirectional mode would
//   add a source-language parameter; current design pins it.
// - **Registry fallback in the lookup** — a stale per-book file with a
//   deleted-language key still renders the first registered glyph
//   instead of a blank box (`BilingualLanguage.findOrDefault(key:)`).
//
// @coordinates-with: BilingualLanguage.swift, ReaderTopChrome.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`

import SwiftUI

/// Inline reader-chrome pill — `EN ↔ <target glyph>` — shown next to
/// the title when bilingual mode is on for the open book.
struct BilingualPill: View {

    /// Visual-identity-v2 theme tokens for the host book.
    let theme: ReaderThemeV2

    /// Persisted target-language key (one of `BilingualLanguage.all`).
    /// Stale / unknown keys degrade to the first registered language
    /// via `findOrDefault(key:)`.
    let language: String

    /// Accessibility identifier for XCUITest + verify-cron snapshots.
    /// Stable contract — do not rename without updating the harnesses.
    static let accessibilityIdentifier = "readerBilingualPill"

    /// Source-language glyph pinned to `EN` per design.
    static let sourceLanguageGlyph = "EN"

    // MARK: - Resolved inputs (exposed for tests)

    /// The registry entry for `language`, falling back to the first
    /// entry for an unknown key.
    var resolvedLanguage: BilingualLanguage {
        BilingualLanguage.findOrDefault(key: language)
    }

    /// Target-side glyph drawn at the right of the pill.
    var resolvedGlyph: String {
        resolvedLanguage.glyph
    }

    /// Resolved language key after the registry fallback — exposes the
    /// post-fallback key for harnesses + the chrome layout.
    var resolvedLanguageKey: String {
        resolvedLanguage.key
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            sourceBadge
            joiner
            targetGlyph
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color(theme.accentColor).opacity(0.10))
        )
        .padding(.leading, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: - Parts

    /// Accent-filled rounded square with white `EN` — per design
    /// the badge is a 16×16 rounded rectangle (corner radius 4),
    /// not a circle.
    private var sourceBadge: some View {
        Text(Self.sourceLanguageGlyph)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(theme.accentColor))
            )
    }

    /// Dimmed accent `↔` joiner.
    private var joiner: some View {
        Text("\u{2194}")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(theme.accentColor).opacity(0.7))
    }

    /// Target glyph in the script's preferred font family.
    private var targetGlyph: some View {
        Text(resolvedGlyph)
            .font(.system(size: 12, weight: .bold, design: targetFontDesign))
            .foregroundStyle(Color(theme.accentColor))
    }

    /// Font design for the target glyph — serif for CJK / Cyrillic /
    /// RTL scripts (matches the design's `Songti SC / Source Han
    /// Serif` stack), default body for Latin two-letter codes.
    private var targetFontDesign: Font.Design {
        switch resolvedLanguage.script {
        case .cjk, .rtl, .cyrillic: return .serif
        case .latin:                return .default
        }
    }

    /// VoiceOver label — designed for screen readers, not for sight.
    private var accessibilityLabel: String {
        "Bilingual reading on, target language \(resolvedLanguageKey)"
    }
}
