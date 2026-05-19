// Purpose: Feature #62 WI-2 — pins `AnnotationsEmptyStateView`'s
// composition.
//
// `AnnotationsEmptyStateView` is the design's `EmptyState` component
// (`vreader-annotations.jsx`): a centred art illustration + serif title
// + body + an OPTIONAL CTA button. The four annotations list surfaces
// (`TOCSheet`'s Contents/Bookmarks tabs, `HighlightsSheet`'s filters)
// reuse it for their empty states.
//
// The contract these tests guard: the CTA is part of the composition
// iff a CTA closure + label are supplied (the design's `cta && ...`),
// the configurable accessibility identifier is applied (so the
// existing XCUITest `tocEmptyState` / `bookmarkEmptyState` identifier
// strings keep resolving once the legacy views are deleted in WI-5),
// and the view builds for every theme.
//
// @coordinates-with: AnnotationsEmptyStateView.swift,
//   AnnotationsEmptyStateArt.swift, ReaderThemeV2.swift

import Testing
import SwiftUI
@testable import vreader

@Suite("Feature #62 — AnnotationsEmptyStateView")
@MainActor
struct AnnotationsEmptyStateViewTests {

    @Test("Builds for every theme")
    func buildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let view = AnnotationsEmptyStateView(
                theme: theme,
                accessibilityIdentifier: "tocEmptyState",
                art: AnyView(EmptyTOCArt(theme: theme)),
                title: "No table of contents",
                body: "This book doesn't ship a TOC."
            )
            _ = view.body
        }
    }

    @Test("hasCTA is false when no CTA closure is supplied")
    func hasCTAFalseWithoutClosure() {
        let view = AnnotationsEmptyStateView(
            theme: .paper,
            accessibilityIdentifier: "bookmarkEmptyState",
            art: AnyView(EmptyBookmarkArt(theme: .paper)),
            title: "No bookmarks yet",
            body: "Tap the bookmark icon to save your place."
        )
        #expect(view.hasCTA == false)
    }

    @Test("hasCTA is true when a CTA label + closure are supplied")
    func hasCTATrueWithClosure() {
        let view = AnnotationsEmptyStateView(
            theme: .paper,
            accessibilityIdentifier: "tocEmptyState",
            art: AnyView(EmptyTOCArt(theme: .paper)),
            title: "No table of contents",
            body: "Use Search to jump to a passage.",
            ctaLabel: "Open Search",
            ctaSystemImage: "magnifyingglass",
            onCTA: {}
        )
        #expect(view.hasCTA)
    }

    @Test("CTA closure is invoked on tap")
    func ctaClosureInvoked() {
        var fired = false
        let view = AnnotationsEmptyStateView(
            theme: .paper,
            accessibilityIdentifier: "tocEmptyState",
            art: AnyView(EmptyTOCArt(theme: .paper)),
            title: "No table of contents",
            body: "Use Search to jump to a passage.",
            ctaLabel: "Open Search",
            ctaSystemImage: "magnifyingglass",
            onCTA: { fired = true }
        )
        view.invokeCTAForTesting()
        #expect(fired)
    }

    @Test("Builds with a CTA for every theme")
    func buildsWithCTAForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let view = AnnotationsEmptyStateView(
                theme: theme,
                accessibilityIdentifier: "tocEmptyState",
                art: AnyView(EmptyTOCArt(theme: theme)),
                title: "No table of contents",
                body: "Use Search.",
                ctaLabel: "Open Search",
                ctaSystemImage: "magnifyingglass",
                onCTA: {}
            )
            _ = view.body
        }
    }

    @Test("The configured accessibility identifier is retained")
    func accessibilityIdentifierRetained() {
        // WI-5 re-homes the legacy `tocEmptyState` / `bookmarkEmptyState`
        // XCUITest identifiers onto this view — the identifier must be a
        // configurable input the test can read back.
        let toc = AnnotationsEmptyStateView(
            theme: .paper,
            accessibilityIdentifier: "tocEmptyState",
            art: AnyView(EmptyTOCArt(theme: .paper)),
            title: "t", body: "b"
        )
        let bm = AnnotationsEmptyStateView(
            theme: .paper,
            accessibilityIdentifier: "bookmarkEmptyState",
            art: AnyView(EmptyBookmarkArt(theme: .paper)),
            title: "t", body: "b"
        )
        #expect(toc.accessibilityIdentifier == "tocEmptyState")
        #expect(bm.accessibilityIdentifier == "bookmarkEmptyState")
    }

    @Test("Builds with a CJK title and body")
    func buildsWithCJKText() {
        let view = AnnotationsEmptyStateView(
            theme: .dark,
            accessibilityIdentifier: "highlightsEmptyState",
            art: AnyView(EmptyHighlightsArt(theme: .dark)),
            title: "暂无高亮或笔记",
            body: "长按任意段落即可高亮或添加笔记。"
        )
        _ = view.body
    }

    @Test("title and body are wired from the init arguments")
    func titleAndBodyWired() {
        // The design's EmptyState renders the supplied title + body —
        // pin that they are carried onto the view, not dropped or
        // swapped (a value-type View's testable contract).
        let view = AnnotationsEmptyStateView(
            theme: .sepia,
            accessibilityIdentifier: "tocEmptyState",
            art: AnyView(EmptyTOCArt(theme: .sepia)),
            title: "No table of contents",
            body: "This book doesn't ship a TOC."
        )
        #expect(view.title == "No table of contents")
        #expect(view.body_ == "This book doesn't ship a TOC.")
    }

    @Test("invokeCTAForTesting no-ops when no CTA label is supplied")
    func invokeCTANoOpsWithoutLabel() {
        // The hook is gated on hasCTA — an action with no label means no
        // button renders, so the hook must not fire (faithful proxy for
        // "tap the visible CTA").
        var fired = false
        let view = AnnotationsEmptyStateView(
            theme: .paper,
            accessibilityIdentifier: "tocEmptyState",
            art: AnyView(EmptyTOCArt(theme: .paper)),
            title: "t", body: "b",
            ctaLabel: nil,
            onCTA: { fired = true }
        )
        #expect(view.hasCTA == false)
        view.invokeCTAForTesting()
        #expect(fired == false)
    }
}
