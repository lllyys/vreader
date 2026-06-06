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

    /// Feature #74: the transient locate-bloom layer — a highlight range, its
    /// color, the bloom `intensity` (0 = rest, 1 = peak), and the theme family.
    /// Painted SEPARATELY (so it renders even when its range equals a persisted
    /// range — defeats the dedup no-op), and it REPLACES the persisted fill for
    /// an equal range (the design's single wash value-lift, never a stacked
    /// translucent fill). `nil` when no bloom is active. WI-2 drives `intensity`.
    var landingHighlight: (range: NSRange, colorName: String, intensity: CGFloat, family: LandingBloomThemeFamily, reduceMotion: Bool)?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !persistedHighlights.isEmpty || searchHighlightRange != nil || landingHighlight != nil,
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
            // Feature #74: skip the persisted wash the landing layer replaces for
            // an equal range — the landing wash is painted instead (single
            // value-lifting wash, never two stacked translucent fills).
            if let landing = landingHighlight,
               LandingBloomPaint.suppressesPersisted(
                   persistedRange: highlight.range, landingRange: landing.range) {
                continue
            }
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
        if let landing = landingHighlight {
            paintLandingBloom(
                landing, ctx: ctx, container: tc, validBounds: validBounds,
                visibleCharRange: visibleCharRange,
                glyphsToShow: glyphsToShow, origin: origin
            )
        }
    }

    /// Feature #74: paint the locate-bloom layer — the value-lifted wash (which
    /// replaces the suppressed equal-range persisted fill), then the solid-swatch
    /// focus ring with its outer glow. Ring + glow are wrapped in
    /// `saveGState`/`restoreGState` so the shadow/stroke state never leaks into
    /// the persisted/search fills painted above.
    private func paintLandingBloom(
        _ landing: (range: NSRange, colorName: String, intensity: CGFloat, family: LandingBloomThemeFamily, reduceMotion: Bool),
        ctx: CGContext, container: NSTextContainer, validBounds: NSRange,
        visibleCharRange: NSRange, glyphsToShow: NSRange, origin: CGPoint
    ) {
        let p = LandingBloomPaint(
            intensity: landing.intensity, family: landing.family,
            reduceMotion: landing.reduceMotion
        )
        let swatch = HighlightPaintColor.solidSwatch(for: landing.colorName)
        // 1. Wash (value-lifted alpha).
        paint(
            charRange: landing.range,
            color: swatch.withAlphaComponent(p.washAlpha).cgColor,
            ctx: ctx, container: container, validBounds: validBounds,
            visibleCharRange: visibleCharRange,
            glyphsToShow: glyphsToShow, origin: origin
        )
        // 2. Ring + glow — nothing to stroke at rest (ringWidth 0).
        guard p.ringWidth > 0 else { return }
        let clamped = NSIntersectionRange(landing.range, validBounds)
        guard clamped.length > 0,
              NSIntersectionRange(clamped, visibleCharRange).length > 0 else { return }
        let glyphRange = self.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
        let visible = NSIntersectionRange(glyphRange, glyphsToShow)
        guard visible.length > 0 else { return }

        ctx.saveGState()
        if p.glowRadius > 0 {
            ctx.setShadow(
                offset: .zero, blur: p.glowRadius,
                color: swatch.withAlphaComponent(p.glowAlpha).cgColor
            )
        }
        ctx.setStrokeColor(swatch.withAlphaComponent(p.ringAlpha).cgColor)
        ctx.setLineWidth(p.ringWidth)
        enumerateEnclosingRects(
            forGlyphRange: visible,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in
            ctx.stroke(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        ctx.restoreGState()
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
        invalidateHighlightDisplay(lm)
    }

    /// Feature #74 WI-1: set the locate-bloom layer + invalidate. WI-2's
    /// animation driver calls this per frame with a rising/falling `intensity`;
    /// a single call paints one static frame. Painted separately from
    /// persisted/search (so an equal range still renders — defeats the dedup),
    /// and it replaces the equal-range persisted wash (no stacking).
    func setLandingHighlight(
        range: NSRange, colorName: String, intensity: CGFloat,
        family: LandingBloomThemeFamily, reduceMotion: Bool = false
    ) {
        guard let lm = layoutManager as? HighlightingLayoutManager else { return }
        lm.landingHighlight = (
            range: range, colorName: colorName, intensity: intensity,
            family: family, reduceMotion: reduceMotion
        )
        invalidateHighlightDisplay(lm)
    }

    /// Feature #74 WI-1: tear down the locate-bloom layer + invalidate.
    func clearLandingHighlight() {
        guard let lm = layoutManager as? HighlightingLayoutManager,
              lm.landingHighlight != nil else { return }
        lm.landingHighlight = nil
        invalidateHighlightDisplay(lm)
    }

    // MARK: - Feature #74 WI-2: bloom animation driver

    private var bloomLink: CADisplayLink?
    private var bloomStart: CFTimeInterval = 0
    private var bloomRange = NSRange(location: 0, length: 0)
    private var bloomColorName = "yellow"
    private var bloomFamily: LandingBloomThemeFamily = .light
    private var bloomReduceMotion = false

    #if DEBUG
    // MARK: - Feature #74: DEBUG-only bloom readback (CU-free verification)
    //
    // The bloom VISUAL (~1.5s sub-second wash-lift) cannot be screenshot /
    // video-captured on the Screen-Sharing virtual display, so the DebugBridge
    // reads these counters back instead — proving the bloom FIRED through the
    // REAL render path. Both PERSIST after the bloom settles, so a post-settle
    // snapshot proves it bloomed + reached a peak above the resting 0.4 wash.

    /// Number of times `playLandingBloom` has been invoked on this view.
    private(set) var bloomPlayCount: Int = 0
    /// Highest bloom `intensity` (0…1 curve value) recorded across every
    /// display-link tick of every play — `max`-accumulated, never reset to 0
    /// on settle, so a single post-settle read proves the peak was reached.
    private(set) var lastBloomPeakIntensity: CGFloat = 0

    /// Record one bloom tick's intensity into the persisted peak. Called from
    /// `playLandingBloom`'s seeded frame 0 and every `bloomTick`. The peak only
    /// rises (`max`), so it survives the decay tail + settle.
    private func recordBloomPeak(_ intensity: CGFloat) {
        lastBloomPeakIntensity = max(lastBloomPeakIntensity, intensity)
        postBloomReadback()
    }

    /// Push the persisted bloom counters onto the DebugBridge probe via
    /// `.debugBridgeLandingBloomChanged`. No fingerprintKey is included: a
    /// locate bloom only fires on the currently-active TXT/MD reader, and
    /// `ReaderContainerView`'s observer caches it onto the active probe — the
    /// same reader the snapshot reads. Posted whenever the counters change so a
    /// post-settle snapshot reflects the run's final (persisted) peak + count.
    private func postBloomReadback() {
        NotificationCenter.default.post(
            name: .debugBridgeLandingBloomChanged,
            object: nil,
            userInfo: [
                "count": bloomPlayCount,
                "peakIntensity": Double(lastBloomPeakIntensity)
            ]
        )
    }

    /// Test seam — drive a single bloom tick at `elapsedMs` deterministically
    /// (the `CADisplayLink` cannot run in a unit test). Records the curve's
    /// intensity at that time into the peak, mirroring `bloomTick`'s recording.
    func recordBloomTickForTests(elapsedMs: Double) {
        let i = LandingBloomCurve.intensity(elapsedMs: elapsedMs, reduceMotion: bloomReduceMotion)
        recordBloomPeak(i)
    }
    #endif

    /// Plays the locate bloom once over the `LandingBloomCurve` (design §3 / §5),
    /// driving `intensity` per display frame and tearing the layer down when the
    /// run completes. Cancels any in-flight bloom first (single fire).
    func playLandingBloom(
        range: NSRange, colorName: String,
        family: LandingBloomThemeFamily, reduceMotion: Bool
    ) {
        cancelLandingBloom()
        bloomRange = range
        bloomColorName = colorName
        bloomFamily = family
        bloomReduceMotion = reduceMotion
        bloomStart = 0
        #if DEBUG
        bloomPlayCount += 1
        #endif
        // Seed the FIRST frame at the curve's t=0 value — 0 for motion (rises in),
        // 1 for reduce-motion (jumps to peak per §5), so there is no rest-frame
        // flash before the first display tick (Gate-4 Medium).
        let seedIntensity = LandingBloomCurve.intensity(elapsedMs: 0, reduceMotion: reduceMotion)
        #if DEBUG
        recordBloomPeak(seedIntensity)
        #endif
        setLandingHighlight(
            range: range, colorName: colorName,
            intensity: seedIntensity,
            family: family, reduceMotion: reduceMotion
        )
        let link = CADisplayLink(target: self, selector: #selector(bloomTick(_:)))
        link.add(to: .main, forMode: .common)
        bloomLink = link
    }

    @objc private func bloomTick(_ link: CADisplayLink) {
        if bloomStart == 0 { bloomStart = link.timestamp }
        let elapsedMs = (link.timestamp - bloomStart) * 1000
        if LandingBloomCurve.isComplete(elapsedMs: elapsedMs, reduceMotion: bloomReduceMotion) {
            cancelLandingBloom()
            return
        }
        let i = LandingBloomCurve.intensity(elapsedMs: elapsedMs, reduceMotion: bloomReduceMotion)
        #if DEBUG
        recordBloomPeak(i)
        #endif
        setLandingHighlight(
            range: bloomRange, colorName: bloomColorName, intensity: i,
            family: bloomFamily, reduceMotion: bloomReduceMotion
        )
    }

    /// Cancels an in-flight bloom + clears the layer (design §3: interruptible —
    /// any tap/scroll during the bloom cancels it to resting).
    func cancelLandingBloom() {
        bloomLink?.invalidate()
        bloomLink = nil
        clearLandingHighlight()
    }

    // Feature #74 WI-2 (Gate-4 Medium): teardown is handled by
    // `TXTTextViewBridge.dismantleUIView` → `cancelLandingBloom()`, which
    // invalidates the link. A `deinit` cannot touch the MainActor-isolated
    // `CADisplayLink` under Swift 6, and isn't needed: while a bloom runs the
    // link retains `self`, so the view cannot dealloc until the link is already
    // invalidated (on completion, cancel, or dismantle).

    private func invalidateHighlightDisplay(_ lm: HighlightingLayoutManager) {
        let glyphCount = lm.numberOfGlyphs
        if glyphCount > 0 {
            lm.invalidateDisplay(forGlyphRange: NSRange(location: 0, length: glyphCount))
        }
    }
}
