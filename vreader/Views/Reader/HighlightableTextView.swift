// Purpose: UITextView subclass with safe highlight rendering via custom HighlightingLayoutManager.
// Extracted from TXTTextViewBridge.swift (WI-001) — zero logic change.
//
// Key decisions:
// - HighlightingLayoutManager.drawBackground() draws highlight backgrounds without modifying
//   text storage — completely avoids the crash chain documented in bug #47 (v5–v12).
// - setSourceText() is the ONLY method that modifies text storage (initial load, config change).
// - setHighlightRanges() updates the layout manager only — safe during active selection.
//
// @coordinates-with TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift

import UIKit

/// Custom layout manager that draws highlight backgrounds without modifying text storage.
/// This completely avoids the UITextView crash chain (bug #47 v5-v11) where ANY
/// text storage modification on a visible text view with active selection crashes:
/// - textStorage.addAttribute → accessibility recursion (v5)
/// - attributedText setter → accessibility traversal crash (v10)
/// - textStorage.setAttributedString → same crash, shorter stack (v11)
///
/// drawBackground() is called by UIKit's normal display pipeline for the visible
/// glyph range only — efficient, synchronized with scrolling, zero text storage mutation.
final class HighlightingLayoutManager: NSLayoutManager {

    /// Persisted highlights to draw — each painted with its own resolved
    /// color (Bug #208 / GH #776). Was previously a bare `[NSRange]`
    /// painted with one hardcoded yellow fill, which dropped the user's
    /// chosen highlight color.
    var persistedHighlights: [PaintedHighlight] = []
    /// Transient search / navigation highlight range. Painted in the
    /// fixed `HighlightPaintColor.searchHighlight` yellow — kept distinct
    /// from a persisted highlight, which carries a user-chosen color.
    var searchHighlightRange: NSRange?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !persistedHighlights.isEmpty || searchHighlightRange != nil,
              let ctx = UIGraphicsGetCurrentContext(),
              let tc = textContainers.first,
              let ts = textStorage else { return }

        let textLength = ts.length
        guard textLength > 0 else { return }
        let validBounds = NSRange(location: 0, length: textLength)

        let visibleCharRange = characterRange(
            forGlyphRange: glyphsToShow, actualGlyphRange: nil
        )

        for highlight in persistedHighlights {
            paint(
                charRange: highlight.range,
                color: HighlightPaintColor.fill(for: highlight.colorName).cgColor,
                ctx: ctx, container: tc, validBounds: validBounds,
                visibleCharRange: visibleCharRange,
                glyphsToShow: glyphsToShow, origin: origin
            )
        }
        if let searchHighlightRange {
            paint(
                charRange: searchHighlightRange,
                color: HighlightPaintColor.searchHighlight.cgColor,
                ctx: ctx, container: tc, validBounds: validBounds,
                visibleCharRange: visibleCharRange,
                glyphsToShow: glyphsToShow, origin: origin
            )
        }
    }

    /// Fills the visible portion of one highlight range with `color`.
    /// Clamps to text storage bounds first — protects against
    /// stale/corrupted ranges (bug #47).
    private func paint(
        charRange: NSRange,
        color: CGColor,
        ctx: CGContext,
        container: NSTextContainer,
        validBounds: NSRange,
        visibleCharRange: NSRange,
        glyphsToShow: NSRange,
        origin: CGPoint
    ) {
        let clamped = NSIntersectionRange(charRange, validBounds)
        guard clamped.length > 0 else { return }
        guard NSIntersectionRange(clamped, visibleCharRange).length > 0 else { return }
        let glyphRange = self.glyphRange(
            forCharacterRange: clamped, actualCharacterRange: nil
        )
        let visible = NSIntersectionRange(glyphRange, glyphsToShow)
        guard visible.length > 0 else { return }

        ctx.setFillColor(color)
        enumerateEnclosingRects(
            forGlyphRange: visible,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in
            ctx.fill(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
    }
}

/// UITextView subclass with safe highlight rendering (bug #47 v12).
///
/// v5-v11 tried every approach to modify text storage for highlights — all crashed.
/// v12 uses a custom HighlightingLayoutManager that draws highlight backgrounds
/// in drawBackground() — NEVER modifying text storage for highlights.
///
/// Text storage is only modified for source text changes (initial load, config
/// change) via setSourceText(), never during active selection.
final class HighlightableTextView: UITextView {

    /// Guard flag to suppress delegate callbacks during source text replacement.
    var isReplacingText = false
    /// Stores the most recently set persisted highlights (separate from active).
    private var storedPersistedRanges: [PaintedHighlight] = []

    /// Creates a text view with HighlightingLayoutManager for safe highlight drawing.
    convenience init() {
        let storage = NSTextStorage()
        let lm = HighlightingLayoutManager()
        let container = NSTextContainer()
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        self.init(frame: .zero, textContainer: container)
    }

    /// Sets source text (for initial load and config changes only).
    /// Do NOT call for highlight-only changes — use setHighlightRanges instead.
    func setSourceText(_ attrText: NSAttributedString) {
        isReplacingText = true
        defer { isReplacingText = false }
        let savedOffset = contentOffset
        selectedTextRange = nil
        textStorage.setAttributedString(attrText)
        contentOffset = savedOffset
    }

    /// Clears the active search highlight, preserving persisted highlights.
    /// Called by scroll/tap handlers to dismiss temporary search navigation highlights.
    func clearSearchHighlight() {
        setHighlightRanges(persisted: storedPersistedRanges, active: nil)
    }

    /// Updates highlight visualization via the layout manager's drawing layer.
    /// NEVER modifies text storage — completely avoids the crash chain (bug #47 v12).
    /// Each persisted highlight carries its own color (Bug #208); the active
    /// search range is painted in the fixed search-highlight yellow.
    func setHighlightRanges(persisted: [PaintedHighlight], active: NSRange?) {
        guard let lm = layoutManager as? HighlightingLayoutManager else { return }
        storedPersistedRanges = persisted
        lm.persistedHighlights = persisted
        // Drop the active search highlight when it exactly matches a
        // persisted range — otherwise the two translucent fills stack and
        // darken (preserves the pre-#208 dedup behavior).
        if let active, active.length > 0,
           !persisted.contains(where: { $0.range == active }) {
            lm.searchHighlightRange = active
        } else {
            lm.searchHighlightRange = nil
        }
        let glyphCount = lm.numberOfGlyphs
        if glyphCount > 0 {
            lm.invalidateDisplay(forGlyphRange: NSRange(location: 0, length: glyphCount))
        }
    }
}
