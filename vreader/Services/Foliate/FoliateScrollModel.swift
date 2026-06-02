// Purpose: The scrolled-mode scroll model for the Foliate continuous surface
// (Feature #76 WI-1). Foliate's `getDirection` returned only `{ vertical, rtl }`,
// which is LOSSY — `vertical-rl` vs `vertical-lr` collapse to the same value, and
// the windowing axis sign (WebKit's negative `scrollLeft` for vertical-rl) cannot
// be recovered from it (there is even a live `FIXME: vertical-rl only, not -lr` in
// paginator.js `#scrollTo`). This Swift type is the source-of-truth derivation the
// vendored `paginator.js` `getDirection`/ScrollModel mirrors, so the axis props +
// sign are pinned by `FoliateScrollModelTests` rather than re-derived ad hoc in JS.
//
// SCROLLED MODE ONLY: horizontal-writing books scroll on the vertical axis
// (`scrollTop`), vertical-writing books scroll on the horizontal axis
// (`scrollLeft`). Paged mode keeps paginator's own axis handling and is out of
// scope here. The `directionSign` feeds the canonical logical-offset seam
// (`FoliateScrolledWindowMath.logicalOffset(sign:)`, Feature #76 #1322), so the
// Feature #73 horizontal-tb path stays sign `+1` / byte-unchanged.
//
// @coordinates-with: FoliateScrolledWindowMath.swift (logicalOffset/rawOffset),
//   vreader/Services/Foliate/JS/paginator.js (getDirection → ScrollModel)

import Foundation

struct FoliateScrollModel: Equatable {

    enum Axis: String, Equatable {
        case vertical    // scrolls top↔bottom (horizontal-writing books)
        case horizontal  // scrolls left↔right (vertical-writing books)
    }

    /// The scroll axis for the section's writing mode in scrolled mode.
    let axis: Axis
    /// The DOM scroll property to read/write: `scrollTop` (vertical axis) or
    /// `scrollLeft` (horizontal axis).
    let scrollProp: String
    /// The size dimension that accumulates along the scroll axis: `height`
    /// (vertical) or `width` (horizontal).
    let sizeProp: String
    /// The `DOMRect` start edge along the scroll axis: `top` or `left`.
    let rectStartProp: String
    /// `+1` when the raw DOM offset already increases in reading order; `−1` for
    /// vertical-rl, where WebKit's `scrollLeft` is `0` at the start and goes
    /// NEGATIVE toward later content. Consumed by
    /// `FoliateScrolledWindowMath.logicalOffset(sign:)`.
    let directionSign: Int

    /// `true` for vertical-writing (`vertical-rl` / `vertical-lr`) sections — the
    /// ones Feature #73 gated out of windowing and Feature #76 re-enables.
    var isVerticalWriting: Bool { axis == .horizontal }

    /// Derive the scrolled-mode model from a section's computed `writing-mode`.
    /// Unknown / unsupported values fall back to the horizontal-tb model (the
    /// safe Feature #73 path), matching `getDirection`'s prior implicit default.
    static func scrolled(writingMode: String) -> FoliateScrollModel {
        switch writingMode {
        case "vertical-rl":
            // Feature #76 WI-3 (Gate-4 High): the logical reading-order start of a
            // vertical-rl section is its RIGHT edge (WebKit scrollLeft is 0 at the
            // right, negative leftward), so the windowed `#elementAxisStart`
            // measures `el.right - container.right`. Mirrors the JS `scrollModelFor`.
            return FoliateScrollModel(
                axis: .horizontal, scrollProp: "scrollLeft", sizeProp: "width",
                rectStartProp: "right", directionSign: -1)
        case "vertical-lr":
            return FoliateScrollModel(
                axis: .horizontal, scrollProp: "scrollLeft", sizeProp: "width",
                rectStartProp: "left", directionSign: 1)
        default: // horizontal-tb and any non-vertical writing mode
            return FoliateScrollModel(
                axis: .vertical, scrollProp: "scrollTop", sizeProp: "height",
                rectStartProp: "top", directionSign: 1)
        }
    }
}
