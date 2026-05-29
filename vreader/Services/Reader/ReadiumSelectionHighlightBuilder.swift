// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — pure mapping from a
// live Readium text selection to the inputs `HighlightCoordinator.create` needs.
// The Readium `Selection` carries a `Locator` whose `text` (highlight / before /
// after quote) + container-relative `href` + `progression` are exactly the
// anchors vreader's text-quote highlight model stores. This builder decomposes
// that into `(selectedText, AnnotationAnchor, vreader.Locator)` so the host's
// `ReadiumDecorationHighlightAdapter` can re-anchor and render the new
// decoration by the same text-quote path it uses for restore.
//
// Key decisions:
// - PURE + `nonisolated static`: unit-tested without a navigator (the live
//   `Selection` is decomposed by the caller, so the builder takes scalars).
// - Empty / whitespace-only highlight, or an empty / nil href, is unrenderable
//   (Readium re-anchors by the text quote against a real spine resource), so the
//   builder returns `nil` and the caller does NOT create a highlight — mirroring
//   `ReadiumDecorationHighlightAdapter.decoration(for:)`'s skip contract.
// - The stored quote is the selection's `highlight` VERBATIM (the trim is only
//   the renderability DECISION) so Readium's text-quote match uses the exact
//   selection, not a trimmed approximation.
// - The anchor is `.epub(href:cfi:serializedRange:)` with EMPTY cfi + range:
//   Readium anchors by text quote, never the legacy XPath, so a Readium-created
//   highlight stores no serialized DOM range (the adapter ignores it anyway).
//
// @coordinates-with ReadiumDecorationHighlightAdapter.swift,
//   HighlightCoordinator.swift, AnnotationAnchor.swift, Locator.swift

import Foundation

/// Maps a live Readium text selection into `HighlightCoordinator.create` inputs.
enum ReadiumSelectionHighlightBuilder {

    /// The decomposed inputs `HighlightCoordinator.create(locator:anchor:selectedText:color:note:)`
    /// needs to persist + render a new highlight from a Readium selection.
    struct Inputs: Sendable, Equatable {
        let selectedText: String
        let anchor: AnnotationAnchor
        let locator: Locator
    }

    /// Build the create inputs from a Readium selection's decomposed fields, or
    /// `nil` when the selection is unrenderable (empty/whitespace quote, or empty/
    /// nil href). The caller (the Readium host's selection handler) passes the
    /// `Selection.locator`'s `text.highlight` / `text.before` / `text.after`,
    /// the container-relative `href` string, and `locations.progression`.
    nonisolated static func makeInputs(
        highlight: String?,
        before: String?,
        after: String?,
        href: String?,
        progression: Double?,
        fingerprint: DocumentFingerprint
    ) -> Inputs? {
        guard let highlight,
              !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let href, !href.isEmpty
        else {
            return nil
        }
        let anchor: AnnotationAnchor = .epub(
            href: href,
            cfi: "",
            serializedRange: EPUBSerializedRange(
                startContainerPath: "", startOffset: 0,
                endContainerPath: "", endOffset: 0
            )
        )
        let locator = Locator(
            bookFingerprint: fingerprint,
            href: href,
            progression: progression,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: highlight,
            textContextBefore: before,
            textContextAfter: after
        )
        return Inputs(selectedText: highlight, anchor: anchor, locator: locator)
    }
}

#if canImport(UIKit)
import ReadiumShared
import ReadiumNavigator

extension ReadiumSelectionHighlightBuilder {
    /// Convenience that decomposes a live Readium `Selection` into the scalar
    /// `makeInputs` above. The selection's `locator.href` is an `AnyURL`
    /// (container-relative, e.g. `OEBPS/chapter1.xhtml`) — the same href space
    /// the host's `ReadiumDecorationHighlightAdapter` resolves against the
    /// reading-order, so no extra normalization is needed here. Returns `nil`
    /// for an unrenderable selection (see scalar overload).
    @MainActor
    static func makeInputs(
        from selection: Selection,
        fingerprint: DocumentFingerprint
    ) -> Inputs? {
        let text = selection.locator.text
        return makeInputs(
            highlight: text.highlight,
            before: text.before,
            after: text.after,
            href: selection.locator.href.string,
            progression: selection.locator.locations.progression,
            fingerprint: fingerprint
        )
    }
}
#endif
