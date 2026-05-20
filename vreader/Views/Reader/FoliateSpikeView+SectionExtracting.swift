// Purpose: Feature #56 WI-11 — `FoliateSectionExtracting`
// conformance on the live `FoliateSpikeView.Coordinator`. Bridges
// the actor-based `FoliateChapterTextProvider` to Foliate-js'
// per-section text extraction (`readerAPI.bilingualSectionIDs`,
// `readerAPI.bilingualSectionText`) so the bilingual translation
// service can fetch one unit at a time without re-walking the
// whole book.
//
// Key decisions:
// - **Conformance on the Coordinator, not a wrapper class.** The
//   Coordinator already owns the live `WKWebView`; a separate
//   wrapper would double-buffer the reference and complicate
//   lifecycle. The protocol is `@MainActor + AnyObject + Sendable`,
//   so `Coordinator` (used on the main actor) satisfies it
//   without `nonisolated(unsafe)`.
// - **`callAsyncJavaScript` for the JS round-trip.** The two new
//   `readerAPI.bilingual*` helpers return Promises;
//   `callAsyncJavaScript` awaits them, unlike `evaluateJavaScript`
//   which would return the Promise object reference (see the
//   feature #57 `extractPlainText` precedent).
// - **No timeout here.** The per-section extraction is small
//   relative to the whole-book TTS walk; the caller
//   (`FoliateChapterTextProvider`) is already an actor whose
//   methods cooperate with task cancellation via `Task.checkCancellation`
//   downstream. A wedged WKWebView is the same hazard as for
//   `extractPlainText`, but the surface is per-section
//   (proportionally smaller) and the call site is the bilingual
//   prefetch path, not a user-blocking TTS speak loop.
// - **Stringified Int section index as the unit value.** Matches
//   `TranslationUnitID.Kind.foliateHref` semantics: the kind says
//   "Foliate section href / index", and the index is the stable
//   identifier the JS host exposes (Foliate sections in
//   `currentBook.sections` are ordered by render order). A
//   future-href migration can keep the same `foliateHref` Kind
//   without a schema bump.
//
// @coordinates-with: FoliateSpikeView.swift,
//   FoliateSectionExtracting.swift,
//   FoliateChapterTextProvider.swift,
//   vreader/Services/Foliate/JS/foliate-host.js (the
//     `bilingualSectionIDs` / `bilingualSectionText` helpers),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import Foundation
import WebKit

extension FoliateSpikeView.Coordinator: FoliateSectionExtracting {

    /// Ordered list of section unit ids for the open book. Returns
    /// `[]` if the book has not yet rendered or the JS call fails.
    @MainActor
    func extractSections() async -> [TranslationUnitID] {
        guard isBookReady, let webView else { return [] }
        let raw = try? await webView.callAsyncJavaScript(
            "return await readerAPI.bilingualSectionIDs();",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let array = raw as? [Any] else { return [] }
        var units: [TranslationUnitID] = []
        units.reserveCapacity(array.count)
        for raw in array {
            if let s = raw as? String, !s.isEmpty {
                units.append(TranslationUnitID(kind: .foliateHref, value: s))
            } else if let n = raw as? NSNumber {
                units.append(TranslationUnitID(
                    kind: .foliateHref, value: String(describing: n)))
            }
        }
        return units
    }

    /// Plain-text content of one Foliate section. Returns `""` on
    /// any failure (renderer gone, JS error, section missing).
    @MainActor
    func extractSectionText(_ unit: TranslationUnitID) async -> String {
        guard unit.kind == .foliateHref else { return "" }
        guard isBookReady, let webView else { return "" }
        // FoliateJSEscaper handles the `'` / newline / U+2028
        // hazards even though the section value is currently a
        // stringified Int — defence in depth in case a future href
        // mode passes through arbitrary content.
        let safe = FoliateJSEscaper.escapeForJSString(unit.value)
        let js = "return await readerAPI.bilingualSectionText('\(safe)');"
        let raw = try? await webView.callAsyncJavaScript(
            js,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return (raw as? String) ?? ""
    }
}
#endif
