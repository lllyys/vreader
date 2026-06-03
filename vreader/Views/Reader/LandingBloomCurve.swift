// Purpose: Feature #74 WI-2 — the pure intensity-over-time curve for the
// highlight-landing "locate bloom" (design reader-highlight-landing.md §3, §5).
// A `CADisplayLink` driver samples `intensity(elapsedMs:reduceMotion:)` each
// frame and feeds it to `HighlightableTextView.setLandingHighlight(intensity:)`.
//
// Motion (§3):  rise 0→140ms ease-out → hold 140→360ms → decay 360→1500ms ease-in-out.
// Reduce-Motion (§5): jump to peak, hold ~1200ms, then a single linear opacity
//   fade ~320ms (no movement/glow — the driver also suppresses the glow).
//
// Pure + unit-tested; the driver + paint live in HighlightableTextView.swift /
// the bridge coordinator.
//
// @coordinates-with: LandingBloomPaint.swift, HighlightableTextView.swift

import CoreGraphics

enum LandingBloomCurve {

    // Motion timings (ms).
    static let riseMs: Double = 140
    static let holdEndMs: Double = 360
    static let totalMs: Double = 1500

    // Reduce-Motion timings (ms).
    static let reduceMotionHoldMs: Double = 1200
    static let reduceMotionFadeMs: Double = 320
    static var reduceMotionTotalMs: Double { reduceMotionHoldMs + reduceMotionFadeMs }

    /// The total run length for a given motion preference.
    static func totalDurationMs(reduceMotion: Bool) -> Double {
        reduceMotion ? reduceMotionTotalMs : totalMs
    }

    /// Bloom intensity (0…1) at `elapsedMs`. Clamps to `[0, 1]`; returns 0 once
    /// the run is complete (the caller then clears the layer).
    static func intensity(elapsedMs t: Double, reduceMotion: Bool) -> CGFloat {
        if reduceMotion {
            if t <= reduceMotionHoldMs { return 1 }
            if t >= reduceMotionTotalMs { return 0 }
            return CGFloat(1 - (t - reduceMotionHoldMs) / reduceMotionFadeMs)
        }
        if t <= 0 { return 0 }
        if t < riseMs { return easeOut(CGFloat(t / riseMs)) }
        if t < holdEndMs { return 1 }
        if t >= totalMs { return 0 }
        let d = CGFloat((t - holdEndMs) / (totalMs - holdEndMs))  // 0…1 through decay
        return 1 - easeInOut(d)
    }

    /// Whether the run is finished at `elapsedMs` (the driver stops + clears).
    static func isComplete(elapsedMs t: Double, reduceMotion: Bool) -> Bool {
        t >= totalDurationMs(reduceMotion: reduceMotion)
    }

    // MARK: - Easing

    /// Ease-out (design's `cubic-bezier(0.22,1,0.36,1)` approximated by the
    /// standard ease-out cubic — monotone 0→1, fast start, soft finish).
    private static func easeOut(_ x: CGFloat) -> CGFloat {
        let c = min(max(x, 0), 1)
        let inv = 1 - c
        return 1 - inv * inv * inv
    }

    /// Symmetric ease-in-out cubic — 0→1, slow ends, fast middle.
    private static func easeInOut(_ x: CGFloat) -> CGFloat {
        let c = min(max(x, 0), 1)
        return c < 0.5
            ? 4 * c * c * c
            : 1 - pow(-2 * c + 2, 3) / 2
    }
}
