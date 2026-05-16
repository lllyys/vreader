// Purpose: Contract tests for the feature #60 WI-10 generative book-cover
// fallback — `GenerativeCoverStyle` (the 5 style families + deterministic
// assignment policy) and `BookCoverArtView`'s fallback-decision logic.
//
// These are structural / token assertions, NOT pixel snapshots: they pin
// the design's 5 style families (`vreader-cover.jsx` `CoverArt`), confirm
// the style/palette assignment is deterministic for a given
// `fingerprintKey`, and confirm the cover view picks the generative
// cover exactly when the book has no cover image.
//
// Design source: `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-cover.jsx` (`BookCover`, `CoverArt`).
//
// @coordinates-with: GenerativeCoverStyle.swift, GenerativeCoverView.swift,
//   BookCoverArtView.swift

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("GenerativeCover style + fallback policy (feature #60 WI-10)")
@MainActor
struct GenerativeCoverViewStyleTests {

    // MARK: - The 5 style families

    @Test("There are exactly 5 generative cover style families")
    func fiveStyleFamilies() {
        // The design `CoverArt` switches on classic / modern / animal /
        // editorial / minimal — exactly 5 branches.
        #expect(GenerativeCoverStyle.allCases.count == 5)
    }

    @Test("Style families match the design's named set")
    func styleFamiliesMatchDesign() {
        let names = Set(GenerativeCoverStyle.allCases.map(\.rawValue))
        #expect(names == ["classic", "modern", "animal", "editorial", "minimal"])
    }

    @Test("Every style family has a distinguishable palette")
    func everyStyleHasADistinguishablePalette() {
        // Each palette contributes a (bg, ink, accent) triple. The
        // generative cover renders differently per style; the palette
        // is the load-bearing visual difference the design specifies.
        let palettes = GenerativeCoverStyle.allCases.map { style in
            GenerativeCoverPalette.palette(for: style, seed: 0)
        }
        // All 5 palettes are constructed without crashing.
        #expect(palettes.count == 5)
        // No palette is the zero/default — bg and ink differ within each.
        for palette in palettes {
            #expect(palette.background != palette.ink)
        }
    }

    // MARK: - Deterministic assignment policy

    @Test("Style assignment is deterministic for a given fingerprintKey")
    func styleAssignmentIsDeterministic() {
        let key = "epub:\(String(repeating: "a", count: 64)):1024"
        let first = GenerativeCoverStyle.style(forFingerprintKey: key)
        let second = GenerativeCoverStyle.style(forFingerprintKey: key)
        #expect(first == second)
    }

    @Test("Palette assignment is deterministic for a given fingerprintKey")
    func paletteAssignmentIsDeterministic() {
        let key = "txt:\(String(repeating: "b", count: 64)):2048"
        let first = GenerativeCoverPalette.palette(forFingerprintKey: key)
        let second = GenerativeCoverPalette.palette(forFingerprintKey: key)
        #expect(first.background == second.background)
        #expect(first.ink == second.ink)
        #expect(first.accent == second.accent)
    }

    @Test("Different fingerprintKeys can map to different styles")
    func differentKeysCanDifferInStyle() {
        // The hash distributes across all 5 styles; over a spread of
        // distinct keys we expect to see more than one style chosen.
        var styles = Set<GenerativeCoverStyle>()
        for index in 0..<200 {
            let key = "epub:key-\(index):1024"
            styles.insert(GenerativeCoverStyle.style(forFingerprintKey: key))
        }
        // A degenerate hash would collapse to one bucket; a good one
        // hits every family across 200 keys.
        #expect(styles.count == 5)
    }

    @Test("Style assignment is stable across an empty fingerprintKey")
    func styleAssignmentHandlesEmptyKey() {
        // An empty key must not crash and must still be deterministic.
        let first = GenerativeCoverStyle.style(forFingerprintKey: "")
        let second = GenerativeCoverStyle.style(forFingerprintKey: "")
        #expect(first == second)
    }

    @Test("Style assignment handles a CJK fingerprintKey")
    func styleAssignmentHandlesCJKKey() {
        // The hash walks UTF-8 bytes; a CJK title in the key must work.
        let key = "txt:三体刘慈欣:4096"
        let first = GenerativeCoverStyle.style(forFingerprintKey: key)
        let second = GenerativeCoverStyle.style(forFingerprintKey: key)
        #expect(first == second)
    }

    @Test("Exhaustive style switch — every case maps to a font family")
    func exhaustiveStyleSwitch() {
        // The design assigns serif vs sans per style; a non-exhaustive
        // switch would fail to compile. This pins the per-style title
        // typeface choice from `vreader-cover.jsx`.
        for style in GenerativeCoverStyle.allCases {
            switch style {
            case .classic, .animal, .editorial, .minimal:
                #expect(style.titleFontFamily == .sourceSerif4)
            case .modern:
                #expect(style.titleFontFamily == .inter)
            }
        }
    }

    // MARK: - Fallback decision (BookCoverArtView)

    @Test("Fallback decision picks generative cover when no image")
    func fallbackPicksGenerativeWhenNoImage() {
        // `BookCoverArtView` with a nil image renders the generative
        // cover, not the old plain placeholder.
        #expect(BookCoverArtView.usesGenerativeFallback(hasImage: false))
    }

    @Test("Fallback decision keeps the image when one exists")
    func fallbackKeepsImageWhenPresent() {
        #expect(!BookCoverArtView.usesGenerativeFallback(hasImage: true))
    }

    // MARK: - View construction

    @Test("Generative cover view builds for every style + book combo")
    func generativeCoverBuildsForEveryStyle() {
        for style in GenerativeCoverStyle.allCases {
            let view = GenerativeCoverView(
                title: "Pride and Prejudice",
                author: "Jane Austen",
                style: style,
                palette: GenerativeCoverPalette.palette(for: style, seed: 1)
            )
            _ = view.body
        }
    }

    @Test("Generative cover view builds with no author")
    func generativeCoverBuildsWithoutAuthor() {
        let view = GenerativeCoverView(
            title: "Beowulf",
            author: nil,
            style: .editorial,
            palette: GenerativeCoverPalette.palette(for: .editorial, seed: 2)
        )
        _ = view.body
    }

    @Test("Generative cover view builds with a CJK title + author")
    func generativeCoverBuildsForCJK() {
        let view = GenerativeCoverView(
            title: "三体",
            author: "刘慈欣",
            style: .minimal,
            palette: GenerativeCoverPalette.palette(for: .minimal, seed: 3)
        )
        _ = view.body
    }

    @Test("Generative cover view builds with an empty title")
    func generativeCoverBuildsWithEmptyTitle() {
        let view = GenerativeCoverView(
            title: "",
            author: "Anon",
            style: .classic,
            palette: GenerativeCoverPalette.palette(for: .classic, seed: 4)
        )
        _ = view.body
    }

    // MARK: - BookCoverArtView still builds (re-skin regression guard)

    @Test("BookCoverArtView builds with no image (generative fallback)")
    func coverArtBuildsWithGenerativeFallback() {
        let view = BookCoverArtView(
            image: nil,
            fingerprintKey: "epub:abc:1024",
            title: "A Book",
            author: "An Author"
        )
        _ = view.body
    }

    @Test("BookCoverArtView builds with an image (image path unchanged)")
    func coverArtBuildsWithImage() {
        let view = BookCoverArtView(
            image: UIImage(),
            fingerprintKey: "pdf:def:2048",
            title: "Another Book",
            author: nil
        )
        _ = view.body
    }
}
