// Purpose: Feature #42 WI-11b — host-owned eval-channel commander that drives
// the bilingual interlinear enumerate→inject→clear loop on the Readium EPUB
// navigator. The mirror of `ReadiumNavCommander` (WI-9a) for the bilingual
// surface: the host holds it via `@State`, passes it into the representable, and
// the coordinator binds its production eval method into it on `attach` / clears
// it on `detach`. The host-side bilingual extension calls the commander's async
// methods.
//
// Why an eval-channel commander and NOT a WKScriptMessageHandler:
// - The Readium `EPUBNavigatorViewController` owns its OWN (possibly several)
//   internal spine WebViews and does NOT expose a `bilingualEnumerate` message
//   channel to app code — the entire reason WI-11a's `ReadiumBilingualEvalAdapter`
//   exists. Enumerate is driven by the navigator's public one-way
//   `evaluateJavaScript(_:) async -> Result<Any, Error>`, whose RETURN value
//   carries the `[{bid,text}]` array (the IIFE's last expression). No postMessage
//   anywhere.
//
// Key decisions:
// - **Injected evaluator closure**, set by the coordinator on `attach`
//   (`coordinator.evaluateForBilingual`) and cleared on `detach`. A late call
//   after teardown finds the evaluator nil and no-ops (mirrors the navCommander
//   bind/clear discipline + the navigator-weak posture). The closure shape
//   `(String) async -> Result<Any, Error>?` matches the production eval method;
//   `nil` = no navigator bound.
// - **Parsing reuses `EPUBBilingualPipeline.parseEnumerateMessage`** — the same
//   tolerant `[{bid,text}]` parser the legacy EPUB engine feeds from its message
//   handler. Readium's `.success(value)` carries the bare array, which the
//   pipeline already accepts (confirmed in the WI-11a spike).
// - **Href-consistency normalization (seam #3).** The Readium host produces a
//   vreader `Locator` whose href is Readium's CONTAINER-relative reading-order
//   href (e.g. `OEBPS/chapter1.xhtml`); the `EPUBChapterTextProvider` resolves
//   `unit(containing:)` by EXACT match against vreader's OPF-relative spine
//   hrefs (e.g. `chapter1.xhtml`). Left unmapped, the unit lookup returns nil and
//   nothing translates (the WI-8 highlight-href finding, recurring on the
//   bilingual path). `normalizedLocator(_:toSpineHrefs:)` rewrites the href to
//   the matching OPF spine entry via the shared
//   `ReadiumDecorationHighlightAdapter.resolveHref` tolerance (exact →
//   unique-suffix → unique-basename), keeping every other Locator field intact.
//   No safe match keeps the raw href (an EPUB whose href already matches still
//   resolves; never silently drops the unit).
//
// @coordinates-with: ReadiumBilingualEvalAdapter.swift,
//   EPUBBilingualPipeline.swift, ReadiumReaderCoordinator.swift,
//   ReadiumDecorationHighlightAdapter.swift, ReadiumEPUBHost+Bilingual.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import Foundation

/// Host-owned eval-channel sink for the bilingual enumerate/inject/clear loop.
/// The coordinator binds its production eval method on `attach` and clears it on
/// `detach`; the host-side bilingual extension calls `enumerate` / `inject` /
/// `clear`. A late call after teardown finds the evaluator nil and no-ops.
@MainActor
final class ReadiumBilingualCommander {

    /// Set by the coordinator on `attach`; runs `script` on the live navigator's
    /// visible spine and returns its eval result. `nil` result = no navigator
    /// (or the navigator could not evaluate). `@MainActor @Sendable` so it
    /// survives the navigator-delegate boundary under strict concurrency.
    private var evaluator: (@MainActor @Sendable (String) async -> Result<Any, Error>?)?

    init() {}

    // MARK: - Bind / clear (coordinator → commander)

    /// Binds the production eval method. Called from
    /// `ReadiumReaderCoordinator.attach`.
    func setEvaluator(
        _ evaluator: @escaping @MainActor @Sendable (String) async -> Result<Any, Error>?
    ) {
        self.evaluator = evaluator
    }

    /// Drops the evaluator so a late enumerate/inject/clear no-ops after
    /// teardown. Called from `ReadiumReaderCoordinator.detach`.
    func clearEvaluator() {
        evaluator = nil
    }

    // MARK: - Eval-channel loop

    /// Runs the return-value enumerate JS on the live spine and parses the
    /// returned `[{bid,text}]` array into `[BilingualBlock]`.
    ///
    /// Gate-4 round-3 MED-2: distinguishes eval FAILURE from a successful-but-empty
    /// enumerate so the driver can retry a transient failure without permanently
    /// marking the chapter enumerated:
    ///   - `nil`  → eval FAILURE / unbound evaluator / detached navigator / a
    ///     MALFORMED `.success` payload (a real PARSE FAILURE — non-array,
    ///     non-envelope). The driver must NOT commit the chapter as enumerated — a
    ///     later `locationDidChange` for the same chapter retries.
    ///   - `[]`   → a successful eval over a chapter that has no translatable
    ///     blocks (a genuinely valid-but-empty result). The driver COMMITS so it
    ///     does not retry-loop forever.
    ///   - non-empty → success with blocks.
    ///
    /// Gate-4 round-3 MED (Finding A): `parseEnumerateMessage` tolerantly returns
    /// `[]` for garbage too, so a parse failure would otherwise look like
    /// success-empty and the chapter would be permanently deduped after a bad eval
    /// payload. We gate on a POSITIVE shape check FIRST: the value must be a bare
    /// `[Any]` array (the paged `[{bid,text}]` shape, incl. `[]`) or a
    /// `[String:Any]` envelope carrying a `blocks` array (the continuous-scroll
    /// shape, incl. `{blocks:[]}`). Anything else is a parse failure → `nil`.
    func enumerate() async -> [BilingualBlock]? {
        guard let evaluator else { return nil }
        switch await evaluator(ReadiumBilingualEvalAdapter.enumerateJS()) {
        case let .success(value)?:
            guard ReadiumBilingualCommander.isValidEnumerateShape(value) else {
                return nil
            }
            return EPUBBilingualPipeline.parseEnumerateMessage(value)
        case .failure?, nil:
            return nil
        }
    }

    /// Gate-4 round-3 MED (Finding A): positive shape gate distinguishing a
    /// valid-but-empty enumerate result from a malformed (unparseable) payload.
    /// Valid: a bare `[Any]` array (paged `[{bid,text}]`, including empty) OR a
    /// `[String:Any]` envelope with a `blocks` array (continuous-scroll, including
    /// `{blocks:[]}`). Garbage (string / number / `blocks`-less dict) is NOT a
    /// valid empty — it is a parse failure the driver must be free to retry.
    nonisolated static func isValidEnumerateShape(_ value: Any) -> Bool {
        if value is [Any] { return true }
        if let dict = value as? [String: Any] { return dict["blocks"] is [Any] }
        return false
    }

    /// Injects the `data-vreader-bid` → translation map as interlinear
    /// decoration siblings on the live spine. No-op when unbound. Every value is
    /// escaped through `FoliateJSEscaper` by the adapter's inject builder.
    func inject(_ pairs: [String: String]) async {
        guard let evaluator, !pairs.isEmpty else { return }
        _ = await evaluator(ReadiumBilingualEvalAdapter.injectJS(pairs: pairs))
    }

    /// Removes every bilingual decoration node from the live spine. No-op when
    /// unbound. Idempotent (safe on a spine without decorations).
    func clear() async {
        guard let evaluator else { return }
        _ = await evaluator(ReadiumBilingualEvalAdapter.clearJS())
    }

    // MARK: - Href-consistency normalization (seam #3)

    /// Rewrites a Readium-host-produced vreader `Locator`'s href (Readium's
    /// CONTAINER-relative reading-order form) to the matching OPF-relative spine
    /// href the `EPUBChapterTextProvider` keys on, so `unit(containing:)` resolves
    /// instead of returning nil. Reuses the shared
    /// `ReadiumDecorationHighlightAdapter.resolveHref` tolerance (exact →
    /// unique-suffix → unique-basename). No safe match keeps the raw href. Every
    /// other Locator field is preserved so the prefetch trigger stays intact.
    nonisolated static func normalizedLocator(
        _ locator: Locator, toSpineHrefs spineHrefs: [String]
    ) -> Locator {
        guard let href = locator.href, !href.isEmpty else { return locator }
        // resolveHref resolves a stored href against a candidate set via exact /
        // unique-suffix / unique-basename. Here the Readium container-relative
        // href (`OEBPS/chapter2.xhtml`) basename-matches the OPF spine
        // (`chapter2.xhtml`). No safe match → keep the raw href.
        guard let resolved = ReadiumDecorationHighlightAdapter.resolveHref(
            href, against: spineHrefs
        ), resolved != href else {
            return locator
        }
        return Locator(
            bookFingerprint: locator.bookFingerprint,
            href: resolved,
            progression: locator.progression,
            totalProgression: locator.totalProgression,
            cfi: locator.cfi,
            page: locator.page,
            charOffsetUTF16: locator.charOffsetUTF16,
            charRangeStartUTF16: locator.charRangeStartUTF16,
            charRangeEndUTF16: locator.charRangeEndUTF16,
            textQuote: locator.textQuote,
            textContextBefore: locator.textContextBefore,
            textContextAfter: locator.textContextAfter
        )
    }
}
#endif
