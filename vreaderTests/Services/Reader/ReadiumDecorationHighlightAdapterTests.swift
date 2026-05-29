// Purpose: Feature #42 Phase 1 WI-8 — unit tests for the
// `ReadiumDecorationHighlightAdapter`. Covers the PURE `HighlightRecord` →
// Readium `Decoration` mapping (href-source precedence, text-quote anchoring,
// tint mapping, skip/unsupported), plus the adapter's set-rebuild logic
// (apply/remove/restore recompute the full `"highlights"` group) driven through
// a fake `DecorableNavigator` test double.
//
// The render itself (a live EPUBNavigatorViewController + WKWebView) is exercised
// by device verification, not here — these tests pin the testable seams.
//
// @coordinates-with vreader/Services/Reader/ReadiumDecorationHighlightAdapter.swift

import Testing
import Foundation
import UIKit
import ReadiumShared
import ReadiumNavigator
@testable import vreader

@MainActor
@Suite("ReadiumDecorationHighlightAdapter (WI-8)")
struct ReadiumDecorationHighlightAdapterTests {

    // MARK: - Fixtures

    private func fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "e", count: 64),
            fileByteCount: 8192,
            format: .epub
        )
    }

    private func locator(
        href: String? = "chapter1.xhtml",
        progression: Double? = 0.42,
        quote: String? = "selected text",
        before: String? = "context before ",
        after: String? = " context after"
    ) -> vreader.Locator {
        vreader.Locator(
            bookFingerprint: fingerprint(),
            href: href, progression: progression, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: quote, textContextBefore: before, textContextAfter: after
        )
    }

    private func record(
        id: UUID = UUID(),
        anchorHref: String? = nil,
        locatorHref: String? = "chapter1.xhtml",
        selectedText: String = "selected text",
        color: String = "yellow",
        note: String? = nil,
        progression: Double? = 0.42
    ) -> HighlightRecord {
        let anchor: AnnotationAnchor? = anchorHref.map {
            .epub(href: $0, cfi: "", serializedRange: EPUBSerializedRange(
                startContainerPath: "/p[1]", startOffset: 0,
                endContainerPath: "/p[1]", endOffset: 5
            ))
        }
        return HighlightRecord(
            highlightId: id,
            locator: locator(href: locatorHref, progression: progression),
            anchor: anchor,
            profileKey: "default",
            selectedText: selectedText,
            color: color,
            note: note,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Pure mapping: decoration(for:)

    @Test func decoration_mapsHrefTextQuoteAndId() throws {
        let id = UUID()
        let rec = record(id: id, locatorHref: "ch5.xhtml", selectedText: "hello")
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.id == id.uuidString)
        #expect(dec.locator.href.string == "ch5.xhtml")
        #expect(dec.locator.text.highlight == "hello")
        #expect(dec.locator.text.before == "context before ")
        #expect(dec.locator.text.after == " context after")
        #expect(dec.locator.locations.progression == 0.42)
    }

    @Test func decoration_anchorHrefWinsOverLocatorHref() throws {
        let rec = record(anchorHref: "anchor-ch.xhtml", locatorHref: "locator-ch.xhtml")
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.locator.href.string == "anchor-ch.xhtml")
    }

    @Test func decoration_fallsBackToLocatorHrefWhenAnchorNil() throws {
        let rec = record(anchorHref: nil, locatorHref: "only-locator.xhtml")
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.locator.href.string == "only-locator.xhtml")
    }

    // MARK: - Gate-5 fix: legacy href → Readium spine href resolution

    @Test func resolveHref_suffixMatch_addsContainerPrefix() {
        // Legacy stores `chapter1.xhtml` (OPF-relative); Readium's spine href is
        // `OEBPS/chapter1.xhtml` (container-relative) — suffix match resolves it.
        let spine = ["OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("chapter1.xhtml", against: spine) == "OEBPS/chapter1.xhtml")
    }

    @Test func resolveHref_exactMatch_returnsAsIs() {
        let spine = ["OEBPS/chapter1.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("OEBPS/chapter1.xhtml", against: spine) == "OEBPS/chapter1.xhtml")
    }

    @Test func resolveHref_basenameMatch_whenNoSuffix() {
        // Different directory prefixes on both sides → basename fallback.
        let spine = ["text/ch1.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("OPS/ch1.xhtml", against: spine) == "text/ch1.xhtml")
    }

    @Test func resolveHref_noMatch_returnsNil() {
        let spine = ["OEBPS/chapter1.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("nonexistent.xhtml", against: spine) == nil)
    }

    @Test func resolveHref_ambiguousBasename_returnsNil() {
        // Gate-4 round-2 Medium: two spine items share the basename `ch1.xhtml`
        // in different directories → basename fallback must NOT guess (it could
        // mis-anchor onto the wrong resource), so the stored href that matches
        // neither exactly nor by suffix resolves to nil.
        let spine = ["text/ch1.xhtml", "alt/ch1.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("OPS/ch1.xhtml", against: spine) == nil)
    }

    @Test func resolveHref_ambiguousSuffix_returnsNil() {
        // Gate-4 round-2 Medium: both `text/ch1.xhtml` and `alt/ch1.xhtml` end
        // with `/ch1.xhtml`, so a bare `ch1.xhtml` suffix-matches BOTH → don't
        // guess, return nil (the suffix branch is uniqueness-guarded too).
        let spine = ["text/ch1.xhtml", "alt/ch1.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("ch1.xhtml", against: spine) == nil)
    }

    @Test func resolveHref_uniqueSuffix_resolvesEvenWithDeeperPath() {
        // A more-specific stored path that suffix-matches exactly one resource
        // resolves, even if the bare basename would be ambiguous.
        let spine = ["OEBPS/text/ch1.xhtml", "OEBPS/alt/ch1.xhtml"]
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("text/ch1.xhtml", against: spine) == "OEBPS/text/ch1.xhtml")
    }

    @Test func resolveHref_emptySpine_returnsNil() {
        #expect(ReadiumDecorationHighlightAdapter.resolveHref("chapter1.xhtml", against: []) == nil)
    }

    /// End-to-end of the fix: decoration built with spineHrefs uses the RESOLVED
    /// container-relative href so Readium can route it to the spine resource.
    @Test func decoration_resolvesLegacyHrefAgainstSpine() throws {
        let rec = record(anchorHref: "chapter1.xhtml", locatorHref: nil, selectedText: "hello")
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(
            for: rec, spineHrefs: ["OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml"]
        ))
        #expect(dec.locator.href.string == "OEBPS/chapter1.xhtml")
    }

    /// No spine list (e.g. before the publication is bound) → raw stored href,
    /// preserving the prior behavior the other mapping tests assert.
    @Test func decoration_emptySpine_keepsRawHref() throws {
        let rec = record(anchorHref: "chapter1.xhtml", locatorHref: nil, selectedText: "hello")
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.locator.href.string == "chapter1.xhtml")
    }

    @Test func decoration_skipsWhenNoHrefAndEmptyText() {
        let rec = record(anchorHref: nil, locatorHref: nil, selectedText: "")
        #expect(ReadiumDecorationHighlightAdapter.decoration(for: rec) == nil)
    }

    @Test func decoration_skipsWhenHrefButEmptyText() {
        // Gate-4 round-1 Low: an href without a text quote is unrenderable —
        // Readium anchors a decoration by the `text.highlight` quote, not by
        // href/progression alone, so an empty-quote record is SKIPPED.
        let rec = record(anchorHref: nil, locatorHref: "ch.xhtml", selectedText: "")
        #expect(ReadiumDecorationHighlightAdapter.decoration(for: rec) == nil)
    }

    @Test func decoration_skipsWhenWhitespaceOnlyText() {
        let rec = record(anchorHref: nil, locatorHref: "ch.xhtml", selectedText: "   \n ")
        #expect(ReadiumDecorationHighlightAdapter.decoration(for: rec) == nil)
    }

    @Test func decoration_nilProgressionStillMaps() throws {
        let rec = record(locatorHref: "ch.xhtml", progression: nil)
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.locator.locations.progression == nil)
    }

    @Test func decoration_noteDoesNotAffectDecoration() throws {
        let recA = record(id: UUID(), note: nil)
        let recB = record(id: recA.highlightId, note: "a note")
        let decA = try #require(ReadiumDecorationHighlightAdapter.decoration(for: recA))
        let decB = try #require(ReadiumDecorationHighlightAdapter.decoration(for: recB))
        #expect(decA.locator.text.highlight == decB.locator.text.highlight)
        #expect(decA.locator.href.string == decB.locator.href.string)
    }

    @Test func decoration_cjkSelectedTextPreserved() throws {
        let rec = record(locatorHref: "ch.xhtml", selectedText: "被讨厌的勇气")
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.locator.text.highlight == "被讨厌的勇气")
    }

    @Test func decoration_surrogatePairSelectedTextPreserved() throws {
        let emoji = "highlight 👨‍👩‍👧‍👦 family"
        let rec = record(locatorHref: "ch.xhtml", selectedText: emoji)
        let dec = try #require(ReadiumDecorationHighlightAdapter.decoration(for: rec))
        #expect(dec.locator.text.highlight == emoji)
    }

    // MARK: - Pure mapping: tintColor(for:)

    @Test func tintColor_namedColorsAreDistinctAndNonNil() {
        let yellow = ReadiumDecorationHighlightAdapter.tintColor(for: "yellow")
        let pink = ReadiumDecorationHighlightAdapter.tintColor(for: "pink")
        let green = ReadiumDecorationHighlightAdapter.tintColor(for: "green")
        let blue = ReadiumDecorationHighlightAdapter.tintColor(for: "blue")
        let set = Set([yellow, pink, green, blue])
        #expect(set.count == 4)
    }

    @Test func tintColor_unknownStringFallsBackToYellow() {
        let unknown = ReadiumDecorationHighlightAdapter.tintColor(for: "chartreuse")
        let yellow = ReadiumDecorationHighlightAdapter.tintColor(for: "yellow")
        #expect(unknown == yellow)
    }

    @Test func tintColor_emptyStringFallsBackToYellow() {
        let empty = ReadiumDecorationHighlightAdapter.tintColor(for: "")
        let yellow = ReadiumDecorationHighlightAdapter.tintColor(for: "yellow")
        #expect(empty == yellow)
    }

    // MARK: - Set rebuild via fake DecorableNavigator

    @Test func apply_thenRemove_rebuildsGroup() {
        let nav = FakeDecorableNavigator()
        let adapter = ReadiumDecorationHighlightAdapter()
        adapter.attach(navigator: nav, spineHrefs: [])

        let a = record(id: UUID(), locatorHref: "ch1.xhtml")
        let b = record(id: UUID(), locatorHref: "ch2.xhtml")
        adapter.apply(record: a)
        adapter.apply(record: b)
        #expect(nav.lastGroup == "highlights")
        #expect(Set(nav.lastDecorations.map(\.id)) == Set([a.highlightId.uuidString, b.highlightId.uuidString]))

        adapter.remove(id: a.highlightId)
        #expect(nav.lastDecorations.map(\.id) == [b.highlightId.uuidString])
    }

    @Test func apply_sameId_replacesNotDuplicates() {
        let nav = FakeDecorableNavigator()
        let adapter = ReadiumDecorationHighlightAdapter()
        adapter.attach(navigator: nav, spineHrefs: [])
        let id = UUID()
        adapter.apply(record: record(id: id, color: "yellow"))
        adapter.apply(record: record(id: id, color: "pink"))
        #expect(nav.lastDecorations.count == 1)
    }

    @Test func restore_replacesEntireSet() {
        let nav = FakeDecorableNavigator()
        let adapter = ReadiumDecorationHighlightAdapter()
        adapter.attach(navigator: nav, spineHrefs: [])
        adapter.apply(record: record(id: UUID()))

        let r1 = record(id: UUID(), locatorHref: "x.xhtml")
        let r2 = record(id: UUID(), locatorHref: "y.xhtml")
        adapter.restore(records: [r1, r2], forHref: nil, using: nil)
        #expect(Set(nav.lastDecorations.map(\.id)) == Set([r1.highlightId.uuidString, r2.highlightId.uuidString]))
    }

    @Test func restore_skipsUnsupportedRecords() {
        let nav = FakeDecorableNavigator()
        let adapter = ReadiumDecorationHighlightAdapter()
        adapter.attach(navigator: nav, spineHrefs: [])
        let good = record(id: UUID(), locatorHref: "ch.xhtml", selectedText: "x")
        let bad = record(id: UUID(), anchorHref: nil, locatorHref: nil, selectedText: "")
        adapter.restore(records: [good, bad], forHref: nil, using: nil)
        #expect(nav.lastDecorations.map(\.id) == [good.highlightId.uuidString])
    }

    @Test func removeUnknownId_isNoOpButReapplies() {
        let nav = FakeDecorableNavigator()
        let adapter = ReadiumDecorationHighlightAdapter()
        adapter.attach(navigator: nav, spineHrefs: [])
        let a = record(id: UUID())
        adapter.apply(record: a)
        adapter.remove(id: UUID())  // not in the set
        #expect(nav.lastDecorations.map(\.id) == [a.highlightId.uuidString])
    }

    @Test func operationsWithoutNavigator_doNotCrash() {
        let adapter = ReadiumDecorationHighlightAdapter()
        // No attach() — must not crash; state still tracked.
        adapter.apply(record: record(id: UUID()))
        adapter.remove(id: UUID())
        adapter.restore(records: [], forHref: nil, using: nil)
    }
}

/// Minimal `DecorableNavigator` double recording the last `apply(decorations:in:)`.
/// `DecorableNavigator` is nonisolated, so the conformance cannot be `@MainActor`;
/// the recording storage is `nonisolated(unsafe)` because the tests drive it
/// single-threaded on the main actor (the adapter that calls `apply` is
/// `@MainActor`).
final class FakeDecorableNavigator: DecorableNavigator, @unchecked Sendable {
    private(set) nonisolated(unsafe) var lastDecorations: [Decoration] = []
    private(set) nonisolated(unsafe) var lastGroup: DecorationGroup?

    func supports(decorationStyle style: Decoration.Style.Id) -> Bool { true }

    func apply(decorations: [Decoration], in group: DecorationGroup) {
        lastDecorations = decorations
        lastGroup = group
    }

    func observeDecorationInteractions(
        inGroup group: DecorationGroup,
        onActivated: @escaping OnActivatedCallback
    ) {}
}
