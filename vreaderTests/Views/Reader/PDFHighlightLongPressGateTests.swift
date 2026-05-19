// Purpose: Feature #64 WI-6 — preserves the regression coverage for the PDF
// reader's still-live feature #53 highlight long-press gate, carried over
// from the deleted `Feature55NativeWiringTests.swift`.
//
// WI-6 migrated the TXT / MD containers to the unified highlight-action
// popover and removed their long-press machinery. The PDF container is NOT
// migrated until WI-7, so `PDFViewBridge.Coordinator.gestureRecognizerShouldBegin`
// and the shared `TXTBridgeShared.simultaneousRecognitionAllowed` policy are
// still live production code. These tests keep guarding that gate until WI-7
// replaces it; WI-7 removes this file alongside the PDF long-press code.
//
// Covers: the highlight long-press recognizer is named, denied simultaneous
// recognition against the native selection long-press, and gated by a
// renderer/lookup hit-test so a long-press on plain page text falls through
// to PDFKit's native selection.

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@Suite("PDF highlight long-press gate (feature #53, live until WI-7)")
@MainActor
struct PDFHighlightLongPressGateTests {

    @Test("simultaneousRecognitionAllowed denies the highlight long-press, allows everything else")
    func simultaneityPolicyDeniesHighlightLongPressOnly() {
        // The highlight long-press must be mutually exclusive with the native
        // selection long-press; the tap recognizer (and any unnamed
        // recognizer) keeps the legacy "always simultaneous" answer.
        #expect(
            TXTBridgeShared.simultaneousRecognitionAllowed(
                for: TXTBridgeShared.highlightLongPressName
            ) == false
        )
        #expect(TXTBridgeShared.simultaneousRecognitionAllowed(for: nil) == true)
        #expect(
            TXTBridgeShared.simultaneousRecognitionAllowed(
                for: "some.other.recognizer"
            ) == true
        )
    }

    @Test("PDF coordinator gestureRecognizerShouldBegin lets non-highlight recognizers begin")
    func pdfShouldBeginPassesThroughForNonHighlightRecognizers() {
        let coordinator = PDFViewBridge.Coordinator()
        let tap = UITapGestureRecognizer()
        #expect(coordinator.gestureRecognizerShouldBegin(tap) == true)
    }

    @Test("PDF coordinator gestureRecognizerShouldBegin blocks the highlight long-press with no PDFView")
    func pdfShouldBeginBlocksHighlightLongPressWhenNoRenderer() {
        // With no attached PDFView (and therefore no renderer/annotations),
        // the named highlight long-press must not begin — a long-press on the
        // page falls through to PDFKit's native text selection.
        let coordinator = PDFViewBridge.Coordinator()
        let longPress = UILongPressGestureRecognizer()
        longPress.name = TXTBridgeShared.highlightLongPressName
        #expect(coordinator.gestureRecognizerShouldBegin(longPress) == false)
    }
}
#endif
