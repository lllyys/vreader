// Purpose: Feature #62 WI-2 — the three annotations empty-state SVG
// illustrations, reproduced as SwiftUI shape views.
//
// The committed design (`dev-docs/designs/vreader-fidelity-v1/project/
// vreader-annotations.jsx` — `EmptyTOCArt` / `EmptyBookmarkArt` /
// `EmptyHighlightsArt`) draws each empty state as a 96×96 SVG built
// from abstracted in-app objects (a page, a bookmarked book, a
// highlighted passage). Rule 51 requires the designed surface — these
// replace the plain `ContentUnavailableView` the legacy list views
// used.
//
// Each is a pure `View` taking a `ReaderThemeV2`; the JSX `art`
// functions take `t` and draw with `t.rule` / `t.sub` / `t.accent` /
// `t.isDark`. No data, no behavior — pure geometry. Coordinates are
// transcribed 1:1 from the JSX `viewBox="0 0 96 96"` paths and laid out
// inside a `GeometryReader`-free fixed 96×96 canvas (the design fixes
// the size; `AnnotationsEmptyStateView` frames it).
//
// @coordinates-with: AnnotationsEmptyStateView.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`

import SwiftUI

/// The 96×96 design canvas all three illustrations draw inside.
private let artCanvas: CGFloat = 96

// MARK: - EmptyTOCArt

/// Empty Contents tab — a dashed page outline with text lines and a
/// single accent dot. JSX `EmptyTOCArt`.
struct EmptyTOCArt: View {
    let theme: ReaderThemeV2

    var body: some View {
        ZStack {
            // <rect x=14 y=14 w=68 h=68 rx=4 dashed stroke=rule>
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    Color(theme.ruleColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                )
                .frame(width: 68, height: 68)
                .position(x: 14 + 34, y: 14 + 34)
            // <path d="M28 32h26 M28 42h32 M28 52h22 M28 62h28"> text lines
            textLines
                .stroke(
                    Color(theme.subColor).opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            // <circle cx=68 cy=32 r=5 fill=accent opacity=.85>
            Circle()
                .fill(Color(theme.accentColor).opacity(0.85))
                .frame(width: 10, height: 10)
                .position(x: 68, y: 32)
        }
        .frame(width: artCanvas, height: artCanvas)
    }

    private var textLines: Path {
        var p = Path()
        for (y, width) in [(32.0, 26.0), (42.0, 32.0), (52.0, 22.0), (62.0, 28.0)] {
            p.move(to: CGPoint(x: 28, y: y))
            p.addLine(to: CGPoint(x: 28 + width, y: y))
        }
        return p
    }
}

// MARK: - EmptyBookmarkArt

/// Empty Bookmarks tab — a paper card with faint text lines and an
/// accent bookmark ribbon. JSX `EmptyBookmarkArt`.
struct EmptyBookmarkArt: View {
    let theme: ReaderThemeV2

    var body: some View {
        ZStack {
            // <rect x=20 y=14 w=56 h=72 rx=3 fill=card stroke=rule>
            RoundedRectangle(cornerRadius: 3)
                .fill(cardFill)
                .frame(width: 56, height: 72)
                .position(x: 20 + 28, y: 14 + 36)
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(theme.ruleColor), lineWidth: 1.5)
                .frame(width: 56, height: 72)
                .position(x: 20 + 28, y: 14 + 36)
            // text lines
            textLines
                .stroke(
                    Color(theme.subColor).opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            // <path d="M52 6v32l8-6 8 6V6z" fill=accent> bookmark ribbon
            bookmarkRibbon
                .fill(Color(theme.accentColor).opacity(0.95))
        }
        .frame(width: artCanvas, height: artCanvas)
    }

    /// `t.isDark ? '#2a2724' : '#fcf8f0'` — the page card fill.
    private var cardFill: Color {
        theme.isDark
            ? Color(red: 0x2a / 255, green: 0x27 / 255, blue: 0x24 / 255)
            : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255)
    }

    private var textLines: Path {
        var p = Path()
        for (y, width) in [(26.0, 36.0), (36.0, 32.0), (46.0, 28.0), (56.0, 34.0), (66.0, 22.0)] {
            p.move(to: CGPoint(x: 30, y: y))
            p.addLine(to: CGPoint(x: 30 + width, y: y))
        }
        return p
    }

    private var bookmarkRibbon: Path {
        // M52 6 v32 l8-6 l8 6 V6 z
        var p = Path()
        p.move(to: CGPoint(x: 52, y: 6))
        p.addLine(to: CGPoint(x: 52, y: 38))
        p.addLine(to: CGPoint(x: 60, y: 32))
        p.addLine(to: CGPoint(x: 68, y: 38))
        p.addLine(to: CGPoint(x: 68, y: 6))
        p.closeSubpath()
        return p
    }
}

// MARK: - EmptyHighlightsArt

/// Empty Highlights/Notes surface — three bars (the top one accent-tinted)
/// and an accent highlighter pen. JSX `EmptyHighlightsArt`.
struct EmptyHighlightsArt: View {
    let theme: ReaderThemeV2

    var body: some View {
        ZStack {
            // <rect x=12 y=20 w=72 h=14 rx=3 fill=accent33> — highlighted bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(theme.accentColor).opacity(0.2))
                .frame(width: 72, height: 14)
                .position(x: 12 + 36, y: 20 + 7)
            // <rect x=12 y=42 w=56 h=14 rx=3 fill=faint>
            RoundedRectangle(cornerRadius: 3)
                .fill(faintFill)
                .frame(width: 56, height: 14)
                .position(x: 12 + 28, y: 42 + 7)
            // <rect x=12 y=64 w=64 h=14 rx=3 fill=faint>
            RoundedRectangle(cornerRadius: 3)
                .fill(faintFill)
                .frame(width: 64, height: 14)
                .position(x: 12 + 32, y: 64 + 7)
            // <path d="M70 6l10 10-30 30-12 2 2-12z" fill=accent> — pen
            highlighterPen
                .fill(Color(theme.accentColor).opacity(0.9))
        }
        .frame(width: artCanvas, height: artCanvas)
    }

    /// `t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)'`.
    private var faintFill: Color {
        theme.isDark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.06)
    }

    private var highlighterPen: Path {
        // M70 6 l10 10 l-30 30 l-12 2 l2-12 z
        var p = Path()
        p.move(to: CGPoint(x: 70, y: 6))
        p.addLine(to: CGPoint(x: 80, y: 16))
        p.addLine(to: CGPoint(x: 50, y: 46))
        p.addLine(to: CGPoint(x: 38, y: 48))
        p.addLine(to: CGPoint(x: 40, y: 36))
        p.closeSubpath()
        return p
    }
}
