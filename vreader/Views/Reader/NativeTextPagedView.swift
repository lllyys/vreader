// Purpose: SwiftUI view that renders one page at a time using NativeTextPageNavigator.
// Used by TXT/MD containers when layout is set to paged mode.
//
// Key decisions:
// - Renders the current page's text in a non-scrollable UITextView.
// - Listens for .readerNextPage/.readerPreviousPage notifications for tap zone navigation.
// - Shows page indicator ("Page X of Y") at the bottom.
// - Supports both plain text and attributed text.
// - Posts .readerPositionDidChange after page changes for AI panel context.
// - Bug #215 / GH #837: container owns a single-tap recognizer that routes
//   through `ReaderTapZoneRouter` (paged layout → side-tap page-turn,
//   center-tap chrome-toggle; scroll / nil layout → chrome-toggle for every
//   tap). The textView keeps `isSelectable = true` so long-press selection
//   still produces a `SelectionPopover`; the tap recognizer requires that
//   the long-press gesture failed, so single-tap and selection do not
//   conflict.
//
// @coordinates-with: NativeTextPageNavigator.swift, TXTReaderContainerView.swift,
//   MDReaderContainerView.swift, ReaderTapZoneRouter.swift, PageTurnAnimator.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Single-page text view for native TXT/MD paged mode.
struct NativeTextPagedView: UIViewRepresentable {
    let navigator: NativeTextPageNavigator
    /// The full plain text (for extracting current page content).
    let fullText: String
    /// The full attributed text (for MD rich formatting). Nil for plain TXT.
    let fullAttributedText: NSAttributedString?
    /// Theme-aware text view configuration.
    let config: TXTViewConfig
    /// Explicit page index so SwiftUI detects page changes and triggers updateUIView.
    let currentPage: Int
    /// Page turn animation style.
    let pageTurnAnimation: PageTurnAnimation
    /// Bug #215 / GH #837: the active layout preference. Threaded into the
    /// container so its tap recognizer routes via `ReaderTapZoneRouter`. In
    /// `.paged` left/right zones produce `.readerNextPage` /
    /// `.readerPreviousPage`; in `.scroll` (and the safe `nil` default) every
    /// tap collapses to `.readerContentTapped` — matching the bridge tap
    /// router added in PR #1098 (Bug #239).
    var layout: EPUBLayoutPreference? = nil

    func makeUIView(context: Context) -> NativePagedContainer {
        let container = NativePagedContainer()
        container.applyConfig(config)
        container.pagedLayout = layout
        applyContent(to: container.textView)
        container.accessibilityIdentifier = "nativeTextPagedView"
        return container
    }

    func updateUIView(_ container: NativePagedContainer, context: Context) {
        container.applyConfig(config)
        container.pagedLayout = layout

        // Animate page transition if needed
        let oldPage = context.coordinator.lastPage
        if oldPage != currentPage && oldPage >= 0 {
            let direction: PageTurnAnimator.Direction = currentPage > oldPage ? .forward : .backward
            container.animatePageChange(
                animation: pageTurnAnimation,
                direction: direction
            ) {
                self.applyContent(to: container.textView)
            }
        } else {
            applyContent(to: container.textView)
        }
        context.coordinator.lastPage = currentPage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private func applyContent(to textView: UITextView) {
        if let attrText = fullAttributedText,
           let pageAttr = navigator.currentPageAttributedText(from: attrText) {
            textView.attributedText = pageAttr
        } else if let pageText = navigator.currentPageText(from: fullText) {
            textView.text = pageText
        } else {
            textView.text = ""
        }
    }

    final class Coordinator {
        var lastPage: Int = -1
    }
}

/// Container UIView that holds a UITextView and supports page turn animations.
@MainActor
final class NativePagedContainer: UIView {
    /// Bug #215 / GH #837: per-side `textContainerInset` on the paged
    /// `UITextView`. Exposed as a static constant so the MD container can
    /// subtract `2 × textInset` from the measured GeometryReader proxy
    /// before paginating — pagination must compute pages for the textView's
    /// usable interior (proxy − textContainerInset on both axes), not the
    /// raw container size. Without parity the paginator packs more glyphs
    /// per page than the renderer can display, and the last 1–2 lines get
    /// clipped (Cause 1 in the bug doc).
    static let textInset: CGFloat = 16

    let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(
            top: NativePagedContainer.textInset,
            left: NativePagedContainer.textInset,
            bottom: NativePagedContainer.textInset,
            right: NativePagedContainer.textInset
        )
        // Bug #215 / GH #837: match NativeTextPaginator's
        // `lineFragmentPadding = 0` (NativeTextPaginator.swift:102). Without
        // this parity each rendered line costs an extra ~5pt of horizontal
        // padding the paginator does not account for; long lines reflow
        // differently between paginator and renderer, drifting page
        // boundaries.
        tv.textContainer.lineFragmentPadding = 0
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    /// Snapshot view used during page turn animations.
    private var snapshotView: UIView?

    /// Bug #215 / GH #837: current layout preference; consulted by the tap
    /// recognizer to decide between page-turn (paged) and chrome-toggle
    /// (scroll / nil). Defaults to nil so a freshly-instantiated container
    /// (e.g. in a unit test or a pre-wiring path) is scroll-equivalent.
    var pagedLayout: EPUBLayoutPreference?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Bug #215 — install a single-tap recognizer that routes through
        // `ReaderTapZoneRouter`. The textView keeps `isSelectable = true`
        // so long-press selection still works; the long-press recognizer
        // resolves first because UIKit's default disambiguation lets the
        // long-press hold defer the single tap, and a quick single tap
        // (which doesn't transition the long-press to "began") fires this
        // handler.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleContentTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func applyConfig(_ config: TXTViewConfig) {
        textView.backgroundColor = config.backgroundColor
        textView.textColor = config.textColor
        backgroundColor = config.backgroundColor
        // Bug #324 / GH #1546: tint the selection (caret, grab handles,
        // selection-highlight) with the reader theme accent instead of the
        // system default blue. `applyConfig` runs on every theme change, so the
        // refresh path is covered. Only assign when changed (mirrors the other
        // color props' implicit no-op-on-equal behaviour).
        if textView.tintColor != config.accentColor {
            textView.tintColor = config.accentColor
        }
    }

    // MARK: - Content Tap

    /// Bug #215 / GH #837: route a content tap through `ReaderTapZoneRouter`.
    /// `.paged` layout: left zone → `.readerPreviousPage`, right zone →
    /// `.readerNextPage`, center zone → `.readerContentTapped`. `.scroll` or
    /// nil layout: every tap → `.readerContentTapped`. Mirrors
    /// `TXTTextViewBridgeCoordinator.handleContentTap` (PR #1098 / Bug #239).
    /// `@objc` so a `UITapGestureRecognizer` selector can target it; visible
    /// to tests for unit-driven coverage (UIKit's gesture system does not
    /// fire recognizers in an XCTest harness).
    @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        ReaderTapZoneRouter.dispatch(
            x: location.x,
            totalWidth: bounds.width,
            layout: pagedLayout
        )
    }

    /// Performs page turn animation: snapshots current content, applies new content,
    /// then animates the transition.
    func animatePageChange(
        animation: PageTurnAnimation,
        direction: PageTurnAnimator.Direction,
        applyContent: () -> Void
    ) {
        guard animation != .none else {
            applyContent()
            return
        }

        // Snapshot current state
        let snapshot = textView.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = textView.frame
        addSubview(snapshot)

        // Apply new content
        applyContent()

        // Animate: snapshot is "from", textView is "to"
        PageTurnAnimator.transition(
            from: snapshot,
            to: textView,
            animation: animation,
            direction: direction
        ) {
            Task { @MainActor in
                snapshot.removeFromSuperview()
            }
        }
        snapshotView = snapshot
    }
}
#endif
