// Purpose: Feature #62 WI-2 — pins that the three annotations
// empty-state SVG illustrations build for every theme.
//
// `EmptyTOCArt` / `EmptyBookmarkArt` / `EmptyHighlightsArt` are the
// design's empty-state illustrations (`vreader-annotations.jsx`)
// reproduced as SwiftUI `Shape`/`Path` views. They are pure geometry —
// no data, no behavior — but they read `ReaderThemeV2` tokens
// (`accent` / `sub` / `rule` / `isDark`), so the #60 "a re-skin must
// not drop wiring" regression lesson applies: each art view must build
// for all five themes.
//
// @coordinates-with: AnnotationsEmptyStateArt.swift, ReaderThemeV2.swift

import Testing
import SwiftUI
@testable import vreader

@Suite("Feature #62 — Annotations empty-state art")
@MainActor
struct AnnotationsEmptyStateArtTests {

    @Test("EmptyTOCArt builds for every theme")
    func emptyTOCArtBuildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let art = EmptyTOCArt(theme: theme)
            _ = art.body
        }
    }

    @Test("EmptyBookmarkArt builds for every theme")
    func emptyBookmarkArtBuildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let art = EmptyBookmarkArt(theme: theme)
            _ = art.body
        }
    }

    @Test("EmptyHighlightsArt builds for every theme")
    func emptyHighlightsArtBuildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let art = EmptyHighlightsArt(theme: theme)
            _ = art.body
        }
    }
}
