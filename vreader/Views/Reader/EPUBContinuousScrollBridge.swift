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

#if canImport(UIKit)

/// The `continuousScroll:` input on `EPUBWebViewBridge` (nil ⇒ the legacy
/// one-chapter-per-`loadFileURL` path, byte-identical for paged + the existing
/// single-chapter scroll behaviour). When non-nil, the bridge stitches a windowed
/// multi-chapter DOM and drives it through `coordinator`.
///
/// Holds a reference to the `@MainActor` coordinator + the book's spine count
/// (for the windowed progress mapping). Constructed by the WI-6 container, which
/// owns the `chapterBodyProvider` + restore logic the coordinator is wired with.
///
/// Gated to `canImport(UIKit)` because it carries the live-`WKWebView`
/// `EPUBWebViewEvaluatorHandle` (WI-6b-i). The pure `EPUBScrollBoundarySignal.parse`
/// extension below stays ungated so the parser remains unit-testable without UIKit.
@MainActor
struct EPUBContinuousScrollConfig {
    /// The window-transition decision engine (WI-4). The bridge forwards every
    /// parsed boundary signal to `coordinator.handleBoundarySignal(_:)`.
    let coordinator: EPUBContinuousScrollCoordinator
    /// Total spine items in the book — the denominator for whole-book progress.
    let totalSpineCount: Int
    /// WI-6b-i late-binding evaluator: the container builds this handle, captures
    /// it in `coordinator.evaluate`, AND hands it here so the bridge can bind
    /// `handle.webView = webView` in `makeUIView` once the live `WKWebView` exists.
    /// One handle is shared by both ends — the coordinator emits section JS through
    /// it, the bridge populates its `webView` reference per generation.
    let handle: EPUBWebViewEvaluatorHandle
    /// WI-6b-i (re-audit finding 1, Critical): continuous-mode position update.
    /// The bridge calls this with the windowed `{visibleSpineIndex, intraFraction}`
    /// so the container can persist the chapter the reader scrolled *into* — the
    /// Double-only `onProgressChange` can't carry which section is on screen, so a
    /// reopen would otherwise restore to a stale chapter. Default is a no-op for
    /// callers (tests) that don't track position.
    let onWindowedPosition: @MainActor (_ visibleSpineIndex: Int, _ intraFraction: Double) -> Void
    /// WI-6b-ii: invoked when a chapter section is materialized into the DOM
    /// (the `sectionMaterialized` JS post — appended/prepended sections never
    /// fire `didFinish`). The container restores that section's highlights
    /// (and, later, bilingual enumerate) re-rooted into the section. Default is
    /// a no-op for callers (tests) that don't drive per-section restore.
    let onSectionMaterialized: @MainActor (_ spineIndex: Int, _ href: String) -> Void

    init(
        coordinator: EPUBContinuousScrollCoordinator,
        totalSpineCount: Int,
        handle: EPUBWebViewEvaluatorHandle,
        onWindowedPosition: @escaping @MainActor (_ visibleSpineIndex: Int, _ intraFraction: Double) -> Void = { _, _ in },
        onSectionMaterialized: @escaping @MainActor (_ spineIndex: Int, _ href: String) -> Void = { _, _ in }
    ) {
        self.coordinator = coordinator
        self.totalSpineCount = totalSpineCount
        self.handle = handle
        self.onWindowedPosition = onWindowedPosition
        self.onSectionMaterialized = onSectionMaterialized
    }

    /// The live evaluator the bridge binds to the `WKWebView`. Feature #71 WI-7
    /// (Gate-4 round-2 MEDIUM 1): per-section bilingual enumerate / inject JS is
    /// evaluated through THIS handle (the live continuous-scroll evaluator)
    /// rather than the bridge's single `pendingHighlightJS` slot — multiple
    /// section-materialize posts in quick succession would otherwise let a later
    /// section's JS overwrite an earlier one before the bridge evaluates it.
    /// A no-op (throws `noWebView`) before the webview mounts or after teardown.
    @MainActor
    func evaluateBilingual(_ js: String) {
        let handle = self.handle
        Task { @MainActor in try? await handle.evaluate(js) }
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

#endif

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
        // Bug #327: handle NSNumber FIRST and distinguish a real boolean only via
        // `CFGetTypeID == CFBooleanGetTypeID`. The live WKScriptMessage bridges
        // every JS number to NSNumber, and `any is Bool` / `as? Int` CONFLATE
        // NSNumber(0)/NSNumber(1) with a Swift Bool (NSNumber↔Bool bridge) — which
        // dropped a JS index `0` (the cover-top case: a real book reports
        // visibleSpineIndex 0 while the reader sits above section 0's offsetTop),
        // so the continuous-scroll window never extended and reading got stuck.
        // Swift-native Int/Double/Bool all bridge through `as? NSNumber` too, so
        // this one branch covers them; the fallbacks below are defensive.
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            guard d.isFinite, d == d.rounded() else { return nil }
            return n.intValue
        }
        if any is Bool { return nil }
        if let i = any as? Int { return i }
        if let d = any as? Double {
            guard d.isFinite, d == d.rounded() else { return nil }
            return Int(d)
        }
        return nil
    }

    /// Finite Double coercion. Rejects a bool-backed `NSNumber` (a JS boolean is
    /// not a fraction) so a malformed `intraFraction: true` isn't read as `1.0`.
    private nonisolated static func doubleValue(_ any: Any?) -> Double? {
        // Bug #327: NSNumber first (CFBoolean check) — a JS `0` fraction bridges to
        // NSNumber(0), and the `any is Bool` shortcut conflated it with a Bool and
        // dropped the whole boundary signal (the cover-top case where intraFraction
        // is exactly 0). See `intValue`.
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue.isFinite ? n.doubleValue : nil
        }
        if any is Bool { return nil }
        if let d = any as? Double { return d.isFinite ? d : nil }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    private nonisolated static func boolValue(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }
}

/// Feature #71 WI-6b-ii: the `sectionMaterialized` JS post — `{spineIndex, href}`
/// emitted after a chapter section is appended/prepended into the stitched DOM.
/// Drives per-section highlight restore (appended sections never fire
/// `didFinish`). Pure value + parser, unit-testable without a live WKWebView.
struct EPUBSectionMaterialized: Equatable, Sendable {
    let spineIndex: Int
    let href: String

    /// Parse a `sectionMaterialized` message body. Returns nil when the body is
    /// not a dictionary, `spineIndex` is missing/negative/non-integral, or
    /// `href` is missing/empty. `spineIndex` accepts `Int` or an integer-valued
    /// `NSNumber` (JS numbers arrive as `NSNumber` over the bridge); a
    /// bool-backed `NSNumber` is rejected.
    nonisolated static func parse(_ body: Any) -> EPUBSectionMaterialized? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let spineIndex = intValue(dict["spineIndex"]), spineIndex >= 0 else { return nil }
        guard let href = dict["href"] as? String, !href.isEmpty else { return nil }
        return EPUBSectionMaterialized(spineIndex: spineIndex, href: href)
    }

    private nonisolated static func intValue(_ any: Any?) -> Int? {
        // Bug #327: handle NSNumber FIRST and distinguish a real boolean only via
        // `CFGetTypeID == CFBooleanGetTypeID`. The live WKScriptMessage bridges
        // every JS number to NSNumber, and `any is Bool` / `as? Int` CONFLATE
        // NSNumber(0)/NSNumber(1) with a Swift Bool (NSNumber↔Bool bridge) — which
        // dropped a JS index `0` (the cover-top case: a real book reports
        // visibleSpineIndex 0 while the reader sits above section 0's offsetTop),
        // so the continuous-scroll window never extended and reading got stuck.
        // Swift-native Int/Double/Bool all bridge through `as? NSNumber` too, so
        // this one branch covers them; the fallbacks below are defensive.
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            guard d.isFinite, d == d.rounded() else { return nil }
            return n.intValue
        }
        if any is Bool { return nil }
        if let i = any as? Int { return i }
        if let d = any as? Double {
            guard d.isFinite, d == d.rounded() else { return nil }
            return Int(d)
        }
        return nil
    }
}
