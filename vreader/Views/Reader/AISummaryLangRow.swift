// Purpose: Feature #90 WI-2 — the Summarize tab's SECOND control row, beneath
// the scope chips: a language control on the LEFT (the current
// `BilingualLanguage` target as a pill + chevron → opens the language popover)
// and a Single / Bilingual segmented toggle on the RIGHT.
//
// Mirrors the committed design `bilingual-summarize-artboards.jsx` `LangRow`
// (`:52-83`): the language pill is a 22×22 `accentColor` rounded-6 square with
// the language glyph in white bold (CJK/RTL scripts get the serif CJK stack),
// the language `key` name in 12.5 semibold ink, and a `chevron.down` that
// rotates when the popover is open, all inside a 0.5pt `ruleColor`-bordered
// capsule with a subtle wash when open. The segmented toggle is a 2-segment
// Single / Bilingual control; the active segment raises a light/dark elevated
// background with a small accent glyph (a line glyph for Single, a stacked
// glyph for Bilingual), the inactive segment is `subColor`.
//
// Control → `SummaryDisplayMode` mapping (the artboard's 2-segment toggle, the
// WI-2 contract): Single → `.translatedOnly`, Bilingual → `.interlinear`.
// `.originalOnly` is the VM default (today's summary, no translation); the
// toggle does not expose it as an explicit third segment (see the Rule-51 note
// in the WI-2 brief / the plan's Gate-2 round-3 resolution). The active-segment
// derivation + the (segment → mode) mapping are pure static helpers so they pin
// without a SwiftUI render pass (the `AISummaryTabView.section(for:)` precedent).
//
// @coordinates-with: AISummaryTabView.swift, AISummaryLangPopover.swift,
//   AIAssistantViewModel+BilingualSummary.swift, BilingualLanguage.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The Summarize tab's language + Single/Bilingual control row — design
/// `LangRow`.
struct AISummaryLangRow: View {

    /// The current bilingual target language (drives the pill glyph + name).
    let language: BilingualLanguage

    /// The current summary display mode (drives which segment renders active).
    let mode: SummaryDisplayMode

    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2

    /// Whether the language popover is open (rotates the chevron + washes the
    /// pill, matching the artboard's `popoverOpen` state).
    let isPopoverOpen: Bool

    /// Invoked when the language pill is tapped — the parent toggles the popover.
    let onTapLanguage: () -> Void

    /// Invoked when a segment is tapped — passes the mapped `SummaryDisplayMode`
    /// (Single → `.translatedOnly`, Bilingual → `.interlinear`).
    let onSelectMode: (SummaryDisplayMode) -> Void

    // MARK: - Segments

    /// The two toggle segments, in design order: Single, then Bilingual.
    enum Segment: CaseIterable, Equatable {
        case single
        case bilingual

        /// The `SummaryDisplayMode` this segment maps to (the WI-2 contract):
        /// Single → translated-only, Bilingual → interlinear.
        var mode: SummaryDisplayMode {
            switch self {
            case .single:    return .translatedOnly
            case .bilingual: return .interlinear
            }
        }

        /// The segment label, per the design (`Single` / `Bilingual`).
        var label: String {
            switch self {
            case .single:    return "Single"
            case .bilingual: return "Bilingual"
            }
        }

        /// The accessibility identifier for this segment.
        var identifier: String {
            switch self {
            case .single:    return "summaryModeSingle"
            case .bilingual: return "summaryModeBilingual"
            }
        }
    }

    /// The segment that renders active for a given `SummaryDisplayMode`. Pure
    /// (no render pass) so the active-segment derivation pins in a unit test.
    ///
    /// `.interlinear` → Bilingual; `.translatedOnly` AND the default
    /// `.originalOnly` both render Single active (the 2-segment toggle has no
    /// distinct "original" segment — `.originalOnly` is the resting state that
    /// matches the Single side, per the design's `layout='single'` default).
    static func activeSegment(for mode: SummaryDisplayMode) -> Segment {
        switch mode {
        case .interlinear:                return .bilingual
        case .translatedOnly, .originalOnly: return .single
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            languagePill
            Spacer(minLength: 0)
            segmentedToggle
        }
        .accessibilityIdentifier("summaryLangControl")
    }

    // MARK: - Language pill

    /// The left language control — a capsule holding the accent glyph square,
    /// the language name, and a rotating chevron. Tapping opens the popover.
    @ViewBuilder
    private var languagePill: some View {
        Button(action: onTapLanguage) {
            HStack(spacing: 7) {
                glyphSquare(
                    glyph: language.glyph,
                    script: language.script,
                    size: 22,
                    corner: 6,
                    background: Color(theme.accentColor),
                    foreground: .white
                )
                Text(language.key)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
                    .rotationEffect(.degrees(isPopoverOpen ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isPopoverOpen)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color(pillFillColor))
            )
            .overlay(
                Capsule().strokeBorder(Color(theme.ruleColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("summaryLangPill")
        .accessibilityLabel("Summary language: \(language.key)")
    }

    // MARK: - Segmented toggle

    /// The right Single / Bilingual segmented toggle — a trough holding two
    /// segments; the active one raises an elevated wash + an accent glyph.
    @ViewBuilder
    private var segmentedToggle: some View {
        let active = Self.activeSegment(for: mode)
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { segment in
                segmentButton(segment, isActive: segment == active)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9).fill(Color(troughFillColor))
        )
    }

    /// One toggle segment — the active one carries the elevated bg + accent glyph.
    @ViewBuilder
    private func segmentButton(_ segment: Segment, isActive: Bool) -> some View {
        Button { onSelectMode(segment.mode) } label: {
            HStack(spacing: 5) {
                segmentGlyph(segment, isActive: isActive)
                Text(segment.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isActive ? Color(theme.inkColor) : Color(theme.subColor))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color(activeSegmentFill) : Color.clear)
                    .shadow(
                        color: isActive ? Color.black.opacity(0.08) : .clear,
                        radius: 1, x: 0, y: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(segment.identifier)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// The small glyph inside a segment — a single line for Single, a stacked
    /// pair for Bilingual (design `LineGlyph` / `StackGlyph`). Active → accent,
    /// inactive → `subColor`.
    @ViewBuilder
    private func segmentGlyph(_ segment: Segment, isActive: Bool) -> some View {
        let tint = isActive ? Color(theme.accentColor) : Color(theme.subColor)
        switch segment {
        case .single:    SummaryLineGlyph(size: 12, color: tint)
        case .bilingual: SummaryStackGlyph(size: 12, color: tint)
        }
    }

    // MARK: - Shared glyph square (reused by the popover via a free function)

    /// The accent glyph square — the language's glyph centered in a rounded
    /// square. CJK / RTL scripts use the serif CJK font stack + a larger size
    /// (matching the design's `cjkFont` branch).
    @ViewBuilder
    private func glyphSquare(
        glyph: String,
        script: BilingualLanguage.Script,
        size: CGFloat,
        corner: CGFloat,
        background: Color,
        foreground: Color
    ) -> some View {
        AISummaryLangGlyphSquare(
            glyph: glyph,
            script: script,
            size: size,
            corner: corner,
            background: background,
            foreground: foreground
        )
    }

    // MARK: - Theme washes

    /// The language pill background — transparent normally, a subtle wash when
    /// the popover is open (design `popoverOpen` branch).
    private var pillFillColor: UIColor {
        guard isPopoverOpen else { return .clear }
        return theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.04)
    }

    /// The segmented-toggle trough wash (design `rgba(255,255,255,0.06)` dark /
    /// `rgba(0,0,0,0.05)` light).
    private var troughFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.05)
    }

    /// The active segment's elevated wash (design `#3a3530` dark / `#fff` light).
    private var activeSegmentFill: UIColor {
        theme.isDark
            ? UIColor(red: 0x3a / 255, green: 0x35 / 255, blue: 0x30 / 255, alpha: 1)
            : .white
    }
}

/// The accent glyph square used by the language pill AND the popover rows. A
/// standalone `View` so both surfaces share one CJK-font / sizing rule.
struct AISummaryLangGlyphSquare: View {
    let glyph: String
    let script: BilingualLanguage.Script
    let size: CGFloat
    let corner: CGFloat
    let background: Color
    let foreground: Color

    var body: some View {
        Text(glyph)
            .font(glyphFont)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: corner).fill(background)
            )
            .accessibilityHidden(true)
    }

    /// CJK / RTL scripts use the serif CJK stack at a larger size; Latin /
    /// Cyrillic use the system bold (matching the design's `cjkFont` branch).
    private var glyphFont: Font {
        let isCJKLike = script == .cjk || script == .rtl
        let pointSize: CGFloat = (script == .cjk) ? size * 0.59 : size * 0.5
        if isCJKLike {
            return Font.custom("Songti SC", size: pointSize).weight(.bold)
        }
        return .system(size: pointSize, weight: .bold)
    }
}
#endif
