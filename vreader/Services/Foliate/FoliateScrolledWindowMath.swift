// Purpose: Pure windowing math for the Foliate scrolled-mode continuous
// rendering surface (Feature #73 WI-1). Operates on the MOUNTED window's
// per-section sizes (a contiguous sub-list of the book's sections measured
// live in the WKWebView). These are the seams `#afterScroll` / mount-evict /
// navigation-landing call in `paginator.js`, lifted to testable Swift.
//
// Gate-2 C1 (binding): there is NO whole-book fraction here. `SectionProgress`
// (progress.js) remains the single source of whole-book truth; the renderer's
// `#afterScroll` emits the INTRA-section fraction these helpers produce, and
// `SectionProgress.getProgress(index, intraFraction, …)` converts it. Emitting
// whole-book here would double-apply section progress and break Bug #265
// position restore.

import Foundation

enum FoliateScrolledWindowMath {

    /// The contiguous window of absolute section indices to keep mounted around
    /// `current`, target size `k` (current + neighbours). The window keeps size
    /// `k` where possible, shifting inward when it would run off either end, and
    /// clamps to `0...(total-1)`. Returns `nil` for an empty book or `k <= 0`.
    static func window(current: Int, total: Int, k: Int) -> ClosedRange<Int>? {
        guard total > 0, k > 0 else { return nil }
        let size = min(k, total)
        let c = min(max(current, 0), total - 1)
        let half = (size - 1) / 2
        var lo = c - half
        var hi = c + (size - 1 - half)
        if lo < 0 { hi += -lo; lo = 0 }
        if hi > total - 1 { lo -= (hi - (total - 1)); hi = total - 1 }
        lo = max(0, lo)
        return lo...hi
    }

    /// Cumulative offset where the mounted-list position `index` starts (the sum
    /// of the sizes before it). `index` is clamped to `0...count`.
    static func offsetOfSection(_ index: Int, mountedSizes: [Double]) -> Double {
        guard !mountedSizes.isEmpty else { return 0 }
        let i = min(max(index, 0), mountedSizes.count)
        return mountedSizes.prefix(i).reduce(0, +)
    }

    /// Which mounted-list index a scroll offset falls in, clamped to a valid
    /// index. An offset exactly on a section boundary belongs to the LATER
    /// section (so the page that just became fully visible is "current").
    static func sectionAtOffset(_ offset: Double, mountedSizes: [Double]) -> Int {
        guard !mountedSizes.isEmpty else { return 0 }
        if offset <= 0 { return 0 }
        var acc = 0.0
        for (i, size) in mountedSizes.enumerated() {
            acc += size
            if offset < acc { return i }
        }
        return mountedSizes.count - 1
    }

    /// `(mounted-list index, intra-section fraction in 0...1)` for a scroll
    /// offset — the exact pair `#afterScroll` emits. The fraction is
    /// `(offset - sectionStart) / sectionSize`, clamped. A zero-size section
    /// yields fraction 0.
    static func intraSectionFraction(scrollOffset: Double, mountedSizes: [Double]) -> (index: Int, intra: Double) {
        guard !mountedSizes.isEmpty else { return (0, 0) }
        let idx = sectionAtOffset(scrollOffset, mountedSizes: mountedSizes)
        let start = offsetOfSection(idx, mountedSizes: mountedSizes)
        let size = mountedSizes[idx]
        guard size > 0 else { return (idx, 0) }
        let intra = min(max((scrollOffset - start) / size, 0), 1)
        return (idx, intra)
    }

    /// How much to subtract from `scrollTop` after the given sizes above the
    /// viewport are evicted, so visible content stays put (no jump): the total
    /// evicted size. Negative inputs are ignored.
    static func offsetAdjustmentOnEvict(evictedSizesAbove: [Double]) -> Double {
        evictedSizesAbove.reduce(0) { $0 + max(0, $1) }
    }

    /// WI-1b — anchor coordinate translation across mounted iframes (Gate-2 H5).
    /// A rect/anchor inside the mounted section at `mountedIndex` is measured in
    /// that section's OWN iframe-document coordinates (top = `rectTopWithinSection`);
    /// the windowed `#scrollToRect`/`#scrollToAnchor` must add the section's offset
    /// in the container to land at the right place. Container offset =
    /// `offsetOfSection(mountedIndex) + rectTopWithinSection`. (The current
    /// single-view `#scrollToRect` adds no offset — correct only for index 0.)
    static func containerOffset(rectTopWithinSection: Double, mountedIndex: Int, mountedSizes: [Double]) -> Double {
        offsetOfSection(mountedIndex, mountedSizes: mountedSizes) + rectTopWithinSection
    }

    // MARK: - Feature #76 WI-1: canonical logical-offset conversion

    /// Convert a RAW container scroll offset (what the DOM reports) into a
    /// non-negative, reading-order LOGICAL offset that all the windowing math
    /// above consumes — using the active scroll axis's `directionSign`.
    ///
    /// Vertical-scroll (horizontal-writing LTR/RTL — scrolled mode scrolls
    /// `scrollTop`) and horizontal-writing-LTR use `sign = +1` (raw == logical).
    /// Vertical-rl scrolls the horizontal axis right-to-left, where WebKit's
    /// `scrollLeft` is `0` at the start and goes NEGATIVE toward later content,
    /// so `sign = -1` maps the raw negative offset to a positive logical one.
    /// This is the single normalization point (Gate-2 audit: one canonical
    /// logical-offset API, so raw negative `scrollLeft` is never mixed with the
    /// windowing math).
    ///
    /// - Note: idempotent for `sign == +1`; the existing vertical-scroll callers
    ///   (Feature #73) pass `sign = +1` and are byte-for-byte unchanged.
    static func logicalOffset(rawOffset: Double, sign: Int) -> Double {
        sign < 0 ? -rawOffset : rawOffset
    }

    /// Inverse of `logicalOffset`: convert a reading-order LOGICAL offset back to
    /// the RAW container offset for the axis (e.g. to assign `scrollLeft` for an
    /// RTL / vertical-rl window). `logicalOffset(rawOffset(x, sign), sign) == x`.
    static func rawOffset(logicalOffset: Double, sign: Int) -> Double {
        sign < 0 ? -logicalOffset : logicalOffset
    }
}
