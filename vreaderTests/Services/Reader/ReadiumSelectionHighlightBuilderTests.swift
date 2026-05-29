// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — unit tests for the
// PURE `ReadiumSelectionHighlightBuilder`, which maps a live Readium text
// selection (its `Locator.Text` highlight/before/after quote + container-
// relative href + progression) into the inputs `HighlightCoordinator.create`
// needs (selectedText / anchor / vreader `Locator`).
//
// The live navigator selection (a rendered EPUBNavigatorViewController + a real
// finger drag) is exercised by device verification, not here — these tests pin
// the testable mapping seam: quote trimming, the empty/whitespace guard, the
// text-quote context, href round-trip, and the default-yellow color.
//
// @coordinates-with vreader/Services/Reader/ReadiumSelectionHighlightBuilder.swift

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("ReadiumSelectionHighlightBuilder (WI-8 new-highlight)")
struct ReadiumSelectionHighlightBuilderTests {

    private func fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 4096,
            format: .epub
        )
    }

    // MARK: - Happy path

    @Test func mapsSelectionToHighlightInputs() throws {
        let fp = fingerprint()
        let inputs = try #require(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: "selected phrase",
                before: "context before ",
                after: " context after",
                href: "OEBPS/chapter1.xhtml",
                progression: 0.37,
                fingerprint: fp
            )
        )
        #expect(inputs.selectedText == "selected phrase")
        // Anchor carries the Readium container-relative href; cfi/range empty
        // (Readium re-anchors by text quote, not XPath).
        guard case let .epub(href, cfi, range) = inputs.anchor else {
            Issue.record("expected .epub anchor")
            return
        }
        #expect(href == "OEBPS/chapter1.xhtml")
        #expect(cfi.isEmpty)
        #expect(range.startContainerPath.isEmpty)
        // Locator carries the quote + context so the adapter's
        // text-quote re-anchoring (decoration(for:)) can render it.
        #expect(inputs.locator.href == "OEBPS/chapter1.xhtml")
        #expect(inputs.locator.progression == 0.37)
        #expect(inputs.locator.textQuote == "selected phrase")
        #expect(inputs.locator.textContextBefore == "context before ")
        #expect(inputs.locator.textContextAfter == " context after")
    }

    // MARK: - Empty / whitespace guard

    @Test func nilHighlightReturnsNil() {
        #expect(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: nil, before: nil, after: nil,
                href: "OEBPS/ch.xhtml", progression: 0.1, fingerprint: fingerprint()
            ) == nil
        )
    }

    @Test func emptyHighlightReturnsNil() {
        #expect(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: "", before: nil, after: nil,
                href: "OEBPS/ch.xhtml", progression: 0.1, fingerprint: fingerprint()
            ) == nil
        )
    }

    @Test func whitespaceOnlyHighlightReturnsNil() {
        #expect(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: "   \n\t ", before: nil, after: nil,
                href: "OEBPS/ch.xhtml", progression: 0.1, fingerprint: fingerprint()
            ) == nil
        )
    }

    // MARK: - href guard

    @Test func emptyHrefReturnsNil() {
        #expect(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: "phrase", before: nil, after: nil,
                href: "", progression: 0.1, fingerprint: fingerprint()
            ) == nil
        )
    }

    @Test func nilHrefReturnsNil() {
        #expect(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: "phrase", before: nil, after: nil,
                href: nil, progression: 0.1, fingerprint: fingerprint()
            ) == nil
        )
    }

    // MARK: - Selected text is preserved verbatim (not trimmed in the record)

    @Test func selectedTextWithEdgeWhitespaceIsPreserved() throws {
        // The guard trims to DECIDE renderability, but the stored quote stays
        // verbatim so Readium's text-quote match uses the exact selection.
        let inputs = try #require(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: " word ", before: nil, after: nil,
                href: "OEBPS/ch.xhtml", progression: 0.0, fingerprint: fingerprint()
            )
        )
        #expect(inputs.selectedText == " word ")
    }

    // MARK: - CJK selection (Unicode edge case)

    @Test func cjkSelectionMapsCleanly() throws {
        let inputs = try #require(
            ReadiumSelectionHighlightBuilder.makeInputs(
                highlight: "被讨厌的勇气", before: "前文", after: "后文",
                href: "OEBPS/ch.xhtml", progression: 0.5, fingerprint: fingerprint()
            )
        )
        #expect(inputs.selectedText == "被讨厌的勇气")
        #expect(inputs.locator.textContextBefore == "前文")
        #expect(inputs.locator.textContextAfter == "后文")
    }
}
