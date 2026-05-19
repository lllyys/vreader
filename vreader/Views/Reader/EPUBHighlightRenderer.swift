// Purpose: HighlightRenderer adapter for EPUB format (Phase R4a).
// Translates highlight operations into JavaScript strings for CSS Highlight API
// injection into WKWebView.
//
// Key decisions:
// - Uses onInjectJS callback (set by container) to deliver JS to the bridge.
// - Buffers JS when onInjectJS is nil and flushes when callback is set (bug #77).
// - currentHref must be set before restore() — filters highlights by chapter.
// - Delegates JS generation to EPUBHighlightBridge and EPUBHighlightActions
//   (existing pure-logic modules).
// - No WKWebView dependency — fully testable.
//
// @coordinates-with: HighlightRenderer.swift, EPUBHighlightBridge.swift,
//   EPUBHighlightActions.swift, EPUBReaderContainerView.swift,
//   HighlightCoordinator.swift

#if canImport(UIKit)
import Foundation

/// Highlight renderer for EPUB format.
/// Generates JavaScript for CSS Highlight API operations and delivers
/// via the `onInjectJS` callback. Buffers JS when callback is not yet set.
@MainActor
final class EPUBHighlightRenderer: HighlightRenderer {
    /// Current chapter href for filtering highlights during restore.
    var currentHref: String?

    /// Buffered JS strings awaiting delivery (bug #77: race between .task and highlight creation).
    private var pendingJSBuffer: [String] = []

    /// Callback to inject JS into WKWebView. Set by the container view.
    /// On set, flushes any buffered JS.
    var onInjectJS: ((String) -> Void)? {
        didSet {
            guard let callback = onInjectJS, !pendingJSBuffer.isEmpty else { return }
            let buffered = pendingJSBuffer
            pendingJSBuffer.removeAll()
            for js in buffered {
                callback(js)
            }
        }
    }

    func apply(record: HighlightRecord) {
        guard let js = EPUBHighlightActions.createHighlightJS(for: record) else { return }
        deliverOrBuffer(js)
    }

    func remove(id: UUID) {
        let js = EPUBHighlightBridge.removeHighlightJS(id: id.uuidString)
        deliverOrBuffer(js)
    }

    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) {
        // Bug #103 follow-up (Codex round 1 High): prefer the call's
        // explicit `forHref` over the renderer's mutable `currentHref`.
        // On fast chapter navigation, two concurrent
        // `restore(forHref: A, using: evalA)` and
        // `restore(forHref: B, using: evalB)` calls would otherwise
        // both read whichever value `currentHref` happens to hold by
        // the time they resume — cross-wiring chapter-B JS into evalA.
        // Falling back to `currentHref` only when the caller didn't
        // pass `forHref` keeps the existing `handleRemoval` path
        // (no async gap) working unchanged.
        let resolvedHref = href ?? currentHref
        guard let chapter = resolvedHref, !chapter.isEmpty else { return }
        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: records, currentHref: chapter
        )
        guard !js.isEmpty else { return }
        // When an explicit evaluator is provided, use it directly
        // instead of routing through `onInjectJS`. This keeps the
        // page-ready injection path scoped to the restore call —
        // a concurrent `apply()` or `remove()` from a user-driven
        // highlight creation continues to use `onInjectJS` and lands
        // at the normal callback, not the restore-only one.
        if let evaluator {
            evaluator(js)
        } else {
            deliverOrBuffer(js)
        }
    }

    /// Delivers JS to callback immediately, or buffers if callback is nil.
    private func deliverOrBuffer(_ js: String) {
        if let callback = onInjectJS {
            callback(js)
        } else {
            pendingJSBuffer.append(js)
        }
    }
}

// MARK: - ChapterScopedHighlightRenderer (Feature #64 WI-3)

extension EPUBHighlightRenderer: ChapterScopedHighlightRenderer {
    /// The chapter href the popover's recolor path captures before its
    /// persistence `await`. Surfaces the existing mutable `currentHref`
    /// through the protocol so `HighlightCoordinator.changeColor` does not
    /// depend on the concrete renderer type (R1-4).
    var currentChapterHref: String? { currentHref }
}
#endif
