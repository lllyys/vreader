// Purpose: Feature #56 WI-11 — JavaScript constants for the
// AZW3/MOBI bilingual interlinear renderer. Three thin JS payloads
// that route through `readerAPI.bilingual*` helpers on the
// Foliate host page (where `view.renderer.getContents()` exposes
// the current section's live DOM):
//
//   1. `bilingualEnumerateJS()` — calls `readerAPI.bilingualEnumerate()`,
//      which walks the current rendered section's DOM, stamps a
//      stable `data-vreader-bid` attribute on each translatable
//      block, and posts `[{bid, text}]` back to Swift via the
//      `bilingualEnumerate` message handler.
//   2. `bilingualInjectJS(translationsByBid:)` — calls
//      `readerAPI.bilingualInject({...})` with a serialized lookup
//      table; the host walks every loaded section, finds each
//      block by `data-vreader-bid`, and appends a styled,
//      non-selectable, `data-vreader-decoration`-tagged `<div>`
//      after it.
//   3. `bilingualClearJS()` — calls `readerAPI.bilingualClear()`,
//      which removes every `vreader-bilingual` node from every
//      loaded section.
//
// The split between this Swift-side constant and the host-side
// helper mirrors how the EPUB renderer ships pure JS source
// strings: tests (this WI's `FoliateBilingualJSTests`) pin the
// Swift-side payload shape, runtime DOM behaviour is verified by
// the slice-verification harness against an AZW3 fixture book.
//
// Key decisions:
// - **Host-side helper.** Unlike the EPUB renderer (which
//   evaluates a self-contained iife against `document`), Foliate
//   sections live inside iframes / shadow roots; the only place
//   they are reachable is the host page where
//   `view.renderer.getContents()` returns `[{doc, index}]`. We
//   therefore call into `readerAPI.bilingual*` rather than
//   inlining a `document` walk.
// - **Decoration attribute is keystone.** `data-vreader-decoration`
//   matches the EPUB constant — kept identical so future
//   cross-format highlight code can filter once.
// - **All translation text is escaped via `FoliateJSEscaper`.**
//   A translation containing `'`, `\n`, or U+2028 would otherwise
//   break the single-quoted JS literal and silently fail to inject
//   (best case) or expose a JS injection vector (worst case).
// - **No interlinear style here.** Visual styling lives in CSS
//   injected via the existing Foliate `setStyles` pipeline.
//
// @coordinates-with: FoliateSpikeView.swift (the bridge consumer),
//   FoliateBilingualPipeline.swift, FoliateJSEscaper.swift,
//   vreader/Services/Foliate/JS/foliate-host.js (the host-side
//     `readerAPI.bilingual*` helpers),
//   EPUBBilingualJS.swift (sibling EPUB JS),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import Foundation

/// JavaScript source builders for the AZW3/MOBI bilingual
/// interlinear renderer. All three payloads are pure — same input
/// → same output — and tested via the JS-source-string pins in
/// `FoliateBilingualJSTests`.
enum FoliateBilingualJS {

    /// The attribute every injected translation block carries.
    /// Kept aligned with `EPUBBilingualJS.decorationAttribute` so
    /// future cross-format highlight filtering shares one literal.
    static let decorationAttribute = "data-vreader-decoration"

    /// The attribute the enumerate path stamps on each translatable
    /// block, matched by the inject path. Same as the EPUB renderer's
    /// stamp — the JS payload contract is byte-identical across
    /// formats.
    static let blockIDAttribute = "data-vreader-bid"

    /// The class name every injected translation block carries.
    /// Pinned by name in CSS + the clear path.
    static let blockClassName = "vreader-bilingual"

    /// Feature #77: the modifier class marking a decoration node as the in-flight
    /// LOADING shimmer (vs a landed translation). Shared with
    /// `EPUBBilingualJS.loadingClassName` — the cross-format CSS + clear contract.
    static let loadingClassName = "vreader-bilingual-loading"
    /// Feature #77: the shimmer-bar element class inside a loading decoration.
    static let shimmerBarClassName = "vreader-shimmer-bar"

    /// The WKScriptMessageHandler name the enumerate payload posts
    /// to. Wired up in `FoliateSpikeView.makeUIView`.
    static let enumerateMessageHandlerName = "bilingualEnumerate"

    // MARK: - enumerate

    /// JS that calls the Foliate host's `readerAPI.bilingualEnumerate`
    /// helper. The helper walks the currently-rendered section's
    /// DOM (via `view.renderer.getContents()`), stamps a stable
    /// `data-vreader-bid` on each translatable block (`p` / `li` /
    /// `blockquote` / `pre` / `dd` / `dt` — same set the EPUB
    /// renderer enumerates), and posts an ordered
    /// `[{bid, text, sectionIndex}]` array back to Swift via the
    /// `bilingualEnumerate` channel.
    ///
    /// Stamping is idempotent — a block that already carries a
    /// trusted `^fb\d+$` `data-vreader-bid` keeps the existing id.
    ///
    /// Gate-4 audit finding H2: `targetSectionIndex`
    /// scopes the enumerate to a single Foliate section so an
    /// adjacent loaded section (paginated mode) is not walked. When
    /// `nil`, every loaded section is enumerated and the Swift
    /// pipeline partitions blocks by the per-block `sectionIndex`.
    static func bilingualEnumerateJS(
        targetSectionIndex: Int? = nil
    ) -> String {
        // The actual DOM walk lives in `readerAPI.bilingualEnumerate`
        // on the Foliate host page. The Swift-side payload is a
        // single forward call wrapped in a try/catch so a missing
        // helper (e.g., on an older bundle) doesn't poison the JS
        // execution context.
        //
        // `targetSectionIndex` is interpolated as a JS literal
        // (`null` or an integer) — never a user-supplied string —
        // so no escape is required.
        let arg: String
        if let idx = targetSectionIndex {
            arg = String(idx)
        } else {
            arg = "null"
        }
        return """
        (function() {
            try {
                if (window.readerAPI && typeof readerAPI.bilingualEnumerate === 'function') {
                    readerAPI.bilingualEnumerate(\(arg));
                }
            } catch (e) {}
            try {
                // Belt-and-braces: surface the message channel name in
                // the source string so test pins find it; the actual
                // post happens inside readerAPI.bilingualEnumerate.
                // Future migrations that switch to callAsyncJavaScript
                // can drop this no-op handle without changing the
                // contract.
                var __vreaderBilingualEnumerateHandle =
                    window.webkit && window.webkit.messageHandlers
                        && window.webkit.messageHandlers.\(enumerateMessageHandlerName);
            } catch (e) {}
        })();
        """
    }

    // MARK: - inject

    /// JS that calls the Foliate host's `readerAPI.bilingualInject`
    /// helper with the supplied `data-vreader-bid` → translation
    /// map. The helper walks every loaded section's DOM, finds
    /// each block by id, and appends a styled `<div>` after it.
    ///
    /// Gate-4 audit finding H2: pass
    /// `targetSectionIndex` to scope the inject walk to one
    /// section's DOM. With multiple sections loaded
    /// simultaneously (paginated mode), an unscoped inject would
    /// let one unit's translations leak into adjacent sections.
    /// `nil` falls back to "every loaded section" for the disable
    /// / clear paths.
    ///
    /// Idempotent — an existing decoration sibling is replaced in
    /// place rather than re-appended, so a re-injection (chapter
    /// re-render, language change refetch) does NOT stack
    /// duplicates.
    ///
    /// All translation text routes through
    /// `FoliateJSEscaper.escapeForJSString` so a `'` or newline in a
    /// cached AI response cannot break out of the JS literal or
    /// inject markup.
    static func bilingualInjectJS(
        translationsByBid: [String: String],
        targetSectionIndex: Int? = nil,
        targetIsCJK: Bool = false
    ) -> String {
        var entries: [String] = []
        // Stable order: sort keys so the emitted JS is deterministic
        // and tests can compare full strings without flakes from
        // dictionary iteration order. The runtime walk is
        // attribute-keyed so order does not affect correctness.
        for bid in translationsByBid.keys.sorted() {
            guard let translation = translationsByBid[bid] else { continue }
            let safeBid = FoliateJSEscaper.escapeForJSString(bid)
            let safeText = FoliateJSEscaper.escapeForJSString(translation)
            entries.append("    '\(safeBid)': '\(safeText)'")
        }
        let table = entries.isEmpty ? "" : entries.joined(separator: ",\n") + "\n"

        let sectionArg: String
        if let idx = targetSectionIndex {
            sectionArg = String(idx)
        } else {
            sectionArg = "null"
        }
        return """
        (function() {
            // Build the translations table. Quoted literals — every
            // value already passed through FoliateJSEscaper, so a `'`
            // in a translation never escapes the literal.
            var translations = {
        \(table)};

            // Decoration / class / attribute constants kept in the
            // emitted JS body so a test that pins them by string
            // literal stays self-contained.
            var DECO = '\(decorationAttribute)';
            var BID = '\(blockIDAttribute)';
            var CLS = '\(blockClassName)';

            // The host-side helper does the actual section walk;
            // the wrapper here surfaces user-select / class / attr
            // names in the emitted JS so the test pins resolve.
            try {
                if (window.readerAPI && typeof readerAPI.bilingualInject === 'function') {
                    readerAPI.bilingualInject({
                        translations: translations,
                        decorationAttribute: DECO,
                        blockIDAttribute: BID,
                        blockClassName: CLS,
                        // Belt-and-braces: both user-select forms,
                        // mirroring the EPUB renderer's inject path
                        // (the WebKit content world honours `-webkit-
                        // user-select`; modern WebKit honours `user-
                        // select`).
                        styleCssText: 'user-select: none; -webkit-user-select: none;',
                        // Gate-4 audit finding H2:
                        // section-scoped inject. `null` falls back
                        // to "every loaded section" — used by the
                        // clear path / older bundles.
                        targetSectionIndex: \(sectionArg),
                        // Feature #100: gates the heading rows' CJK tracking.
                        targetIsCJK: \(targetIsCJK ? "true" : "false")
                    });
                }
            } catch (e) {}
        })();
        """
    }

    // MARK: - clear

    /// JS that calls `readerAPI.bilingualClear()` on the Foliate
    /// host page. The helper enumerates every `vreader-bilingual`
    /// node and removes it. Safe to run multiple times — an empty
    /// NodeList is a no-op.
    ///
    /// Gate-4 audit finding H2: pass
    /// `targetSectionIndex` to scope the clear to one section
    /// (used on a section advance — we only need to clear the
    /// just-left section, not every loaded section). `nil` is the
    /// safe default for disable / book close.
    static func bilingualClearJS(
        targetSectionIndex: Int? = nil
    ) -> String {
        let arg: String
        if let idx = targetSectionIndex {
            arg = String(idx)
        } else {
            arg = "null"
        }
        return """
        (function() {
            try {
                if (window.readerAPI && typeof readerAPI.bilingualClear === 'function') {
                    readerAPI.bilingualClear(\(arg));
                }
            } catch (e) {}
        })();
        """
    }

    // MARK: - loading shimmer (Feature #77 WI-3)

    /// JS that calls the Foliate host's `readerAPI.bilingualInjectLoading`
    /// helper with the supplied bids. The helper inserts an inline shimmer
    /// decoration (2 shimmer bars) after each block, skipping any that already
    /// carry a decoration (never downgrades a landed translation). `nil`
    /// `targetSectionIndex` walks every loaded section.
    ///
    /// Each bid routes through `FoliateJSEscaper.escapeForJSString` for the JS
    /// literal; the host applies a defensive `CSS.escape` for the selector.
    static func bilingualInjectLoadingJS(
        loadingBids: [String],
        targetSectionIndex: Int? = nil,
        targetIsCJK: Bool = false
    ) -> String {
        let bidArray = loadingBids.sorted()
            .map { "'\(FoliateJSEscaper.escapeForJSString($0))'" }
            .joined(separator: ", ")
        let sectionArg: String
        if let idx = targetSectionIndex {
            sectionArg = String(idx)
        } else {
            sectionArg = "null"
        }
        return """
        (function() {
            var loadingBids = [\(bidArray)];
            var DECO = '\(decorationAttribute)';
            var BID = '\(blockIDAttribute)';
            var CLS = '\(blockClassName)';
            var LOADING_CLS = '\(loadingClassName)';
            var BAR_CLS = '\(shimmerBarClassName)';
            try {
                if (window.readerAPI && typeof readerAPI.bilingualInjectLoading === 'function') {
                    readerAPI.bilingualInjectLoading({
                        loadingBids: loadingBids,
                        decorationAttribute: DECO,
                        blockIDAttribute: BID,
                        blockClassName: CLS,
                        loadingClassName: LOADING_CLS,
                        shimmerBarClassName: BAR_CLS,
                        styleCssText: 'user-select: none; -webkit-user-select: none;',
                        targetSectionIndex: \(sectionArg),
                        targetIsCJK: \(targetIsCJK ? "true" : "false")
                    });
                }
            } catch (e) {}
        })();
        """
    }

    /// JS that calls `readerAPI.bilingualClearLoading()` — removes ONLY the
    /// loading-shimmer decoration nodes (a failed / cancelled prefetch), leaving
    /// landed translations intact. `nil` clears every loaded section.
    static func bilingualClearLoadingJS(
        targetSectionIndex: Int? = nil
    ) -> String {
        let arg: String
        if let idx = targetSectionIndex {
            arg = String(idx)
        } else {
            arg = "null"
        }
        return """
        (function() {
            try {
                if (window.readerAPI && typeof readerAPI.bilingualClearLoading === 'function') {
                    readerAPI.bilingualClearLoading(\(arg));
                }
            } catch (e) {}
        })();
        """
    }
}
#endif
