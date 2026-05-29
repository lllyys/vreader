// Purpose: Feature #42 Phase 1 (WI-4) — DebugBridge probe support for the
// Readium EPUB reader engine. Adds a token-guarded registry slot for the
// active Readium navigator + a JS-eval seam so the Readium host (WI-5) can be
// verified CU-free (`eval?bridge=epub`-style probes) exactly like the legacy
// EPUBWebViewBridge / Foliate hosts.
//
// SPIKE RESULT (Risk 5 in the feature #42 plan): the Readium 3.9
// `EPUBNavigatorViewController` is NOT a single app-owned WKWebView — it owns
// its own (possibly multiple) internal spine webviews. But Readium 3.9 DOES
// expose a clean public JS-eval surface:
//
//   public func evaluateJavaScript(_ script: String) async -> Result<Any, Error>
//
// which runs JS on the currently-visible HTML resource (the active spine
// webview). So this probe does NOT need to reach Readium's internal webviews:
// it stores a `ReadiumNavigatorEvaluating` seam (which WI-5 conforms the real
// `EPUBNavigatorViewController` to via a thin adapter that JSON-serializes the
// `Result<Any, Error>` value), and exposes JS eval through that. The settle
// signal reuses the existing `markReaderSettled` / `awaitReaderSettled`
// machinery (DebugReaderRegistry+Settle.swift) — WI-5's host calls
// `markReaderSettled(for:token:)` from Readium's
// `navigator(_:locationDidChange:)` delegate (the relocate-equivalent that
// fires once a spine is rendered and the first location is reported).
//
// Wiring (WI-5): the Readium host registers its navigator on
// `navigator(_:locationDidChange:)` (or first render) via
// `setActiveReadiumNavigator(_:for:token:)`, and the eval-bridge handler reads
// the navigator back with `readiumNavigator(for:token:)`. Same keyed +
// per-reader-token stale-write guarding as the EPUB/Foliate slots
// (bug #126 / #142) so a late callback from an outgoing reader cannot clobber
// an incoming probe's binding.
//
// @coordinates-with DebugReaderRegistry.swift, DebugReaderRegistry+Settle.swift
// DEBUG-only.

#if DEBUG

import Foundation

/// Eval seam for the Readium EPUB navigator. WI-5 conforms the real
/// `EPUBNavigatorViewController` to this with a thin adapter that calls the
/// navigator's public `evaluateJavaScript(_:) async -> Result<Any, Error>`
/// and JSON-serializes the success value into raw JSON bytes (mirroring
/// `DebugReaderProbe.evaluateJavaScript`'s contract — `null`/`42`/`"hello"`/
/// `[1,2]`/`{...}` serialized via JSONSerialization so the bridge can splat
/// the value without double-encoding). `AnyObject`-constrained so the registry
/// holds it `weak` (the navigator is a UIViewController; the registry must not
/// keep it alive past its host). `@MainActor` because the navigator and its
/// webviews are main-actor-isolated.
@MainActor
protocol ReadiumNavigatorEvaluating: AnyObject {
    /// Evaluate `script` on the navigator's currently-visible spine HTML and
    /// return the value as raw JSON bytes. Throws on eval failure (the value
    /// is not representable, the spine is not loaded, etc.) so the bridge can
    /// surface a clean `{"error": ...}` instead of crashing.
    func evaluateJavaScriptValue(_ script: String) async throws -> Data
}

extension DebugReaderRegistry {

    /// Register `navigator` as the active Readium EPUB navigator for
    /// `fingerprintKey` + per-reader `token`. Rejected (silently) when an
    /// `expectedReaderToken` is set and the incoming token doesn't match — the
    /// call is a stale callback from an outgoing reader and must not clobber
    /// the current reader's binding (bug #142 race). Mirrors
    /// `setActiveEPUBWebView` / `setActiveFoliateWebView`.
    func setActiveReadiumNavigator(
        _ navigator: ReadiumNavigatorEvaluating,
        for fingerprintKey: String,
        token: UUID
    ) {
        if let expected = expectedReaderTokenForTests, expected != token {
            return // stale callback; ignore
        }
        readiumNavigatorRefInternal = navigator
        readiumNavigatorKeyInternal = fingerprintKey
        readiumNavigatorTokenInternal = token
    }

    /// Return the active Readium navigator iff it was registered for the
    /// requested `fingerprintKey` AND `token`. Returns nil when either fails
    /// to match, or when the registered navigator was deallocated. The token
    /// distinguishes a freshly-mounted reader from any leftover binding from a
    /// same-key but earlier reader instance (bug #142 race). Mirrors
    /// `epubWebView(for:token:)` / `foliateWebView(for:token:)`.
    func readiumNavigator(
        for fingerprintKey: String,
        token: UUID
    ) -> ReadiumNavigatorEvaluating? {
        guard readiumNavigatorKeyInternal == fingerprintKey,
              readiumNavigatorTokenInternal == token else { return nil }
        return readiumNavigatorRefInternal
    }
}

#endif
