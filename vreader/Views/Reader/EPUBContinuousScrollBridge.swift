// Purpose: Feature #71 WI-5 — the bridge-side glue between the continuous-scroll
// JS observer and `EPUBWebViewBridge`. Holds the value type the bridge accepts as
// its `continuousScroll:` input (`EPUBContinuousScrollConfig`), the pure parser
// for the `continuousScrollHandler` JS message (`EPUBScrollBoundarySignal.parse`),
// and the windowed whole-book progress mapping (reusing `EPUBProgressCalculator`,
// unchanged per the plan). The bridge's `makeUIView` branches on a non-nil config
// to inject the section-aware observer (`EPUBContinuousScrollJS.continuousScrollObserverJS`)
// in place of the single-document `progressTrackingJS`, register the
// `continuousScrollHandler` channel, and route each boundary signal to the
// `EPUBContinuousScrollCoordinator` (window transitions, WI-4) while feeding the
// windowed spine-index + fraction to the existing `onProgressChange` contract.
//
// Pure + unit-testable (no live WKWebView): the parser + progress mapping are
// exercised by `EPUBContinuousScrollBridgeTests`; the live observer/handler
// injection is representable-context plumbing verified at Gate-5 (the WI-6
// container wiring is what first drives a real continuous-scroll session).
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift (EPUBScrollBoundarySignal),
//   EPUBContinuousScrollJS.swift, EPUBWebViewBridge.swift,
//   EPUBWebViewBridgeCoordinator.swift, EPUBProgressCalculator.swift,
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-5)

import Foundation

/// The `continuousScroll:` input on `EPUBWebViewBridge` (nil ⇒ the legacy
/// one-chapter-per-`loadFileURL` path, byte-identical for paged + the existing
/// single-chapter scroll behaviour). When non-nil, the bridge stitches a windowed
/// multi-chapter DOM and drives it through `coordinator`.
///
/// Holds a reference to the `@MainActor` coordinator + the book's spine count
/// (for the windowed progress mapping). Constructed by the WI-6 container, which
/// owns the `chapterBodyProvider` + restore logic the coordinator is wired with.
@MainActor
struct EPUBContinuousScrollConfig {
    /// The window-transition decision engine (WI-4). The bridge forwards every
    /// parsed boundary signal to `coordinator.handleBoundarySignal(_:)`.
    let coordinator: EPUBContinuousScrollCoordinator
    /// Total spine items in the book — the denominator for whole-book progress.
    let totalSpineCount: Int

    init(coordinator: EPUBContinuousScrollCoordinator, totalSpineCount: Int) {
        self.coordinator = coordinator
        self.totalSpineCount = totalSpineCount
    }

    /// Whole-book progress for a boundary signal, reusing the existing EPUB
    /// progress formula `(spineIndex + scrollFraction) / totalSpineItems`
    /// (`EPUBProgressCalculator`, unchanged — the windowed `{visibleSpineIndex,
    /// intraFraction}` simply feeds it). Instance convenience over the static.
    func windowedProgress(for signal: EPUBScrollBoundarySignal) -> Double {
        Self.windowedProgress(signal: signal, totalSpineCount: totalSpineCount)
    }

    /// Pure mapping (no coordinator access) so it is unit-testable without a
    /// live coordinator. Guards a zero spine count (no divide-by-zero) and
    /// clamps to 0...1 via `EPUBProgressCalculator`.
    nonisolated static func windowedProgress(signal: EPUBScrollBoundarySignal, totalSpineCount: Int) -> Double {
        EPUBProgressCalculator.progress(
            spineIndex: signal.visibleSpineIndex,
            scrollFraction: signal.intraFraction,
            totalSpineItems: totalSpineCount
        )
    }
}

extension EPUBScrollBoundarySignal {

    /// Parse a `continuousScrollHandler` JS-message body into a boundary signal.
    ///
    /// Shape (`EPUBContinuousScrollJS.continuousScrollObserverJS`):
    /// `{ visibleSpineIndex: Int≥0, intraFraction: 0...1, nearTopBoundary: Bool,
    ///    nearBottomBoundary: Bool }`. Returns nil when the body is not a
    /// dictionary, `visibleSpineIndex` is missing / negative, or `intraFraction`
    /// is missing. `intraFraction` is clamped to 0...1 (defensive against a JS
    /// rounding overshoot). The boundary flags default to `false` when absent
    /// (a missing flag means "not near that edge").
    ///
    /// JS booleans arrive over the WKScriptMessage bridge as `NSNumber`, so the
    /// flag coercion accepts `Bool` or `NSNumber`; the numerics accept any
    /// `NSNumber` (Int or integer-valued Double).
    nonisolated static func parse(_ body: Any) -> EPUBScrollBoundarySignal? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let visibleSpineIndex = intValue(dict["visibleSpineIndex"]), visibleSpineIndex >= 0 else {
            return nil
        }
        guard let rawFraction = doubleValue(dict["intraFraction"]) else { return nil }
        let intraFraction = min(max(rawFraction, 0), 1)
        return EPUBScrollBoundarySignal(
            visibleSpineIndex: visibleSpineIndex,
            intraFraction: intraFraction,
            nearTopBoundary: boolValue(dict["nearTopBoundary"]),
            nearBottomBoundary: boolValue(dict["nearBottomBoundary"])
        )
    }

    /// Strict integral coercion (Gate-4 round-1 Medium): a spine index must be a
    /// non-bool, finite, *integral* number. Rejects a bool-backed `NSNumber`
    /// (a JS `true` is not index 1) and a fractional Double (`3.9` is malformed,
    /// not index 3) rather than silently coercing them.
    private nonisolated static func intValue(_ any: Any?) -> Int? {
        if any is Bool { return nil }
        if let i = any as? Int { return i }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            guard d.isFinite, d == d.rounded() else { return nil }
            return n.intValue
        }
        if let d = any as? Double {
            guard d.isFinite, d == d.rounded() else { return nil }
            return Int(d)
        }
        return nil
    }

    /// Finite Double coercion. Rejects a bool-backed `NSNumber` (a JS boolean is
    /// not a fraction) so a malformed `intraFraction: true` isn't read as `1.0`.
    private nonisolated static func doubleValue(_ any: Any?) -> Double? {
        if any is Bool { return nil }
        if let d = any as? Double { return d.isFinite ? d : nil }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue.isFinite ? n.doubleValue : nil
        }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    private nonisolated static func boolValue(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }
}
