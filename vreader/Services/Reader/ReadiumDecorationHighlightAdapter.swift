// Purpose: Feature #42 Phase 1 WI-8 — `HighlightRenderer` adapter for the
// Readium EPUB engine. Translates vreader's stored `HighlightRecord`s into
// Readium `Decoration`s and submits them to the live `EPUBNavigatorViewController`
// (a `DecorableNavigator`) via `apply(decorations:in:"highlights")`. Counterpart
// of the legacy `EPUBHighlightRenderer` (which emits CSS-Highlight-API JS).
//
// Key decisions:
// - Readium's `apply(decorations:in:)` is DECLARATIVE — it REPLACES the whole
//   group each call. So the adapter holds the active highlight set in memory
//   (`[UUID: HighlightRecord]`) and recomputes the full `[Decoration]` array on
//   every apply / remove / restore, re-submitting the entire `"highlights"`
//   group. There are no deltas to compute.
// - Re-anchoring is TEXT-QUOTE based, not XPath (WI-8a migration spike): each
//   `HighlightRecord` carries `selectedText` + the locator's text context, which
//   map onto `Locator.Text(before:after:highlight:)`. Readium re-anchors by the
//   quote, so the legacy `serializedRange` XPath is never consulted here and is
//   never mutated (flag-OFF returns to legacy XPath rendering losslessly).
// - Spine href source: prefer the EPUB anchor's href, else the locator's href.
//   A record without a non-empty selected-text quote, OR without a spine href,
//   is unrenderable (Readium anchors by the text quote, not href/progression) → SKIP
//   (never crash, never mutate the stored anchor).
// - The pure mapping (`decoration(for:)` + `tintColor(for:)`) is `nonisolated
//   static` so it unit-tests without a navigator.
// - `restore`'s `using evaluator` parameter is the legacy JS-routing seam; the
//   Readium path injects no JS, so it's accepted for protocol conformance and
//   ignored. `forHref` is likewise ignored: Readium decorations are book-wide
//   (the navigator renders only the decorations whose locators fall on visible
//   spine items), so chapter filtering is unnecessary — the full set is always
//   submitted and Readium decides what to draw.
//
// @coordinates-with HighlightRenderer.swift, ReadiumEPUBHost.swift,
//   NamedHighlightColor.swift, HighlightRecord.swift, AnnotationAnchor.swift

#if canImport(UIKit)
import Foundation
import UIKit
import ReadiumShared
import ReadiumNavigator

/// Renders vreader highlights in the Readium EPUB navigator via Readium
/// Decorations. Conforms to the shared `HighlightRenderer` lifecycle
/// (apply / remove / restore), the Readium counterpart of `EPUBHighlightRenderer`.
@MainActor
final class ReadiumDecorationHighlightAdapter: HighlightRenderer {

    /// The decoration group all vreader highlights live in. Readium replaces the
    /// whole group on each `apply(decorations:in:)`.
    static let group: DecorationGroup = "highlights"

    /// The navigator the decorations are submitted to. `DecorableNavigator` is
    /// not class-bound (`weak` is impossible), so the reference is strong but
    /// scoped: `detach()` nils it on host teardown (called from the
    /// representable's `dismantleUIViewController`), and the navigator itself is
    /// owned by the representable's controller lifecycle — so the adapter never
    /// outlives a torn-down navigator and there is no retain cycle past teardown.
    private var navigator: (any DecorableNavigator)?

    /// The active highlight set, keyed by id. The full `"highlights"` group is
    /// recomputed from this on every mutation because Readium's apply replaces
    /// the whole group declaratively.
    private var records: [UUID: HighlightRecord] = [:]

    init() {}

    /// Binds the adapter to the live navigator and submits the current set.
    /// Called from the host's representable once the navigator is built.
    func attach(navigator: any DecorableNavigator) {
        self.navigator = navigator
        rebuildAndApply()
    }

    /// Drops the navigator reference on host teardown so no stale apply fires
    /// after the host leaves the hierarchy.
    func detach() {
        navigator = nil
    }

    // MARK: - HighlightRenderer

    func apply(record: HighlightRecord) {
        records[record.highlightId] = record
        rebuildAndApply()
    }

    func remove(id: UUID) {
        records[id] = nil
        rebuildAndApply()
    }

    func restore(
        records newRecords: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) {
        // `forHref` + `evaluator` are the legacy JS-routing seams; the Readium
        // path injects no JS and decorations are book-wide, so both are ignored
        // (see file header). The full set always replaces the group.
        records = Dictionary(
            newRecords.map { ($0.highlightId, $0) },
            uniquingKeysWith: { _, last in last }
        )
        rebuildAndApply()
    }

    // MARK: - Rebuild

    /// Recomputes the full decoration array from the active set and submits it,
    /// replacing the entire `"highlights"` group. No-op when no navigator is
    /// attached (the set is still tracked, applied on the next `attach`).
    private func rebuildAndApply() {
        guard let navigator else { return }
        let decorations = records.values.compactMap(Self.decoration(for:))
        navigator.apply(decorations: decorations, in: Self.group)
    }

    // MARK: - Pure mapping (unit-testable without a navigator)

    /// Maps a `HighlightRecord` to a Readium `Decoration`, or `nil` when the
    /// record is unrenderable.
    ///
    /// Gate-4 round-1 Low: Readium re-anchors a decoration from the locator's
    /// `text.highlight` quote (or a CSS-selector/fragment we don't supply) — NOT
    /// from `href` + `progression` alone. So a record needs BOTH a spine href AND
    /// a non-empty selected-text quote; without the quote the decoration is a
    /// silent no-op + Readium log noise, so we SKIP it. The stored anchor is
    /// never mutated (flag-OFF returns to legacy XPath rendering losslessly).
    nonisolated static func decoration(for record: HighlightRecord) -> Decoration? {
        let quote = record.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty,
              let href = spineHref(for: record),
              let relative = RelativeURL(path: href) else {
            return nil
        }
        let text = ReadiumShared.Locator.Text(
            after: record.locator.textContextAfter,
            before: record.locator.textContextBefore,
            highlight: record.selectedText
        )
        let locator = ReadiumShared.Locator(
            href: relative,
            mediaType: .xhtml,
            locations: ReadiumShared.Locator.Locations(
                progression: record.locator.progression
            ),
            text: text
        )
        return Decoration(
            id: record.highlightId.uuidString,
            locator: locator,
            style: .highlight(tint: tintColor(for: record.color), isActive: false)
        )
    }

    /// Spine href source precedence: the EPUB anchor's href wins; otherwise the
    /// locator's href. `nil` when neither is present.
    nonisolated static func spineHref(for record: HighlightRecord) -> String? {
        if case let .epub(href, _, _) = record.anchor, !href.isEmpty {
            return href
        }
        if let href = record.locator.href, !href.isEmpty {
            return href
        }
        return nil
    }

    /// Maps the stored color string to a tint `UIColor`, reusing the existing
    /// `HighlightPaintColor.fill(for:)` — the same named-swatch resolver the
    /// TXT/MD painter uses (designed `NamedHighlightColor` hex stops at 0.4
    /// alpha, yellow fallback for legacy/unknown values). Sharing it keeps the
    /// Readium highlight tint visually consistent with every other format and
    /// avoids a second hex-parsing implementation.
    nonisolated static func tintColor(for colorString: String) -> UIColor {
        HighlightPaintColor.fill(for: colorString)
    }
}
#endif
