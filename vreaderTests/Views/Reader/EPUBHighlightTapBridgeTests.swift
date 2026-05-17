// Purpose: Tests for `EPUBHighlightBridge.parseHighlightTapMessage` and
// the click-handler injection in `EPUBHighlightJS.highlightAPIJS`.
// Feature #53 WI-4 / GH #596. Verifies the JS → Swift payload contract
// for tap-on-highlight in EPUB: the JS side hit-tests a click against
// the registered highlight Range map and posts a `{id, rect}` payload;
// the Swift side parses it into a `ReaderHighlightTapEvent` that the
// reader's modifier consumes.
//
// @coordinates-with: EPUBHighlightBridge.swift, EPUBHighlightJS.swift,
//   EPUBWebViewBridgeCoordinator.swift, ReaderNotifications.swift

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("EPUBHighlightTapBridge — parser")
struct EPUBHighlightTapBridgeParserTests {

    @Test
    func parseHighlightTapMessage_validPayload_returnsEvent() {
        let id = UUID()
        let body: [String: Any] = [
            "id": id.uuidString,
            "rectX": 12.5,
            "rectY": 80.0,
            "rectWidth": 96.0,
            "rectHeight": 22.0
        ]
        guard let event = EPUBHighlightBridge.parseHighlightTapMessage(body) else {
            Issue.record("Expected non-nil event for valid payload")
            return
        }
        #expect(event.highlightID == id)
        #expect(event.sourceRect == CGRect(x: 12.5, y: 80, width: 96, height: 22))
    }

    @Test
    func parseHighlightTapMessage_acceptsIntegerCoordinates() {
        // WebKit sometimes serializes integer rect values as NSNumber-int
        // rather than NSNumber-double. The parser must accept both.
        let id = UUID()
        let body: [String: Any] = [
            "id": id.uuidString,
            "rectX": 10,
            "rectY": 80,
            "rectWidth": 96,
            "rectHeight": 22
        ]
        guard let event = EPUBHighlightBridge.parseHighlightTapMessage(body) else {
            Issue.record("Expected non-nil event for integer coordinates")
            return
        }
        #expect(event.highlightID == id)
        #expect(event.sourceRect == CGRect(x: 10, y: 80, width: 96, height: 22))
    }

    @Test
    func parseHighlightTapMessage_missingId_returnsNil() {
        let body: [String: Any] = [
            "rectX": 12.5, "rectY": 80, "rectWidth": 96, "rectHeight": 22
        ]
        #expect(EPUBHighlightBridge.parseHighlightTapMessage(body) == nil)
    }

    @Test
    func parseHighlightTapMessage_invalidUUID_returnsNil() {
        let body: [String: Any] = [
            "id": "not-a-uuid",
            "rectX": 12.5, "rectY": 80, "rectWidth": 96, "rectHeight": 22
        ]
        #expect(EPUBHighlightBridge.parseHighlightTapMessage(body) == nil)
    }

    @Test
    func parseHighlightTapMessage_nonDictBody_returnsNil() {
        // WebKit can pass strings, arrays, or NSNull when JS forgets to
        // serialize properly. The parser must reject anything that isn't
        // a `[String: Any]`.
        #expect(EPUBHighlightBridge.parseHighlightTapMessage("not a dict") == nil)
        #expect(EPUBHighlightBridge.parseHighlightTapMessage(NSNull()) == nil)
        #expect(EPUBHighlightBridge.parseHighlightTapMessage([1, 2, 3]) == nil)
    }

    @Test
    func parseHighlightTapMessage_missingRect_defaultsToZero() {
        // A click handler that fails to compute getBoundingClientRect
        // (e.g. range collapsed after style change) should still post
        // the `id`; the parser accepts missing rect fields and yields
        // a `.zero` source rect. Caller falls back to tap-location
        // anchoring in this case.
        let id = UUID()
        let body: [String: Any] = ["id": id.uuidString]
        guard let event = EPUBHighlightBridge.parseHighlightTapMessage(body) else {
            Issue.record("Expected non-nil event when rect fields are missing")
            return
        }
        #expect(event.highlightID == id)
        #expect(event.sourceRect == .zero)
    }
}

@Suite("EPUBHighlightTapBridge — JS bundle wiring")
struct EPUBHighlightTapBridgeJSTests {

    @Test
    func highlightAPIJS_containsClickListenerRegistration() {
        // The JS bundle must wire a click listener that the
        // `__vreader_highlightRanges` registry can be hit-tested
        // against. Asserting the literal substring is brittle by
        // design — if the marker changes, the test fails and the
        // author is forced to update both the production code and
        // this guard (which mirrors EPUBHighlightBridge's
        // selectionTrackingJS guards).
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(js.contains("__vreader_highlightRanges"))
        #expect(js.contains("highlightTapHandler"))
        #expect(js.contains("caretPositionFromPoint") || js.contains("caretRangeFromPoint"))
    }

    @Test
    func highlightAPIJS_createHighlightStoresRangeInRegistry() {
        // The create function must populate the registry; otherwise
        // the click handler has nothing to hit-test against.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(js.contains("__vreader_highlightRanges["))
    }

    @Test
    func highlightAPIJS_removeHighlightClearsRegistryEntry() {
        // Remove must also delete the registry entry — otherwise a
        // deleted highlight stays tap-targetable, and the user's
        // delete action fires against a stale paint.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(js.contains("delete window.__vreader_highlightRanges"))
    }

    @Test
    func highlightAPIJS_clearAllHighlightsResetsRegistry() {
        // ClearAll (called on chapter change / book switch) must also
        // reset the registry to avoid cross-chapter stale entries.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(js.contains("window.__vreader_highlightRanges = {}"))
    }

    @Test
    func highlightAPIJS_tapHitTest_comparesEndBoundaryAgainstTapPoint() {
        // Bug #211 / GH #820: the WI-4 tap-on-highlight membership test
        // used the wrong `Range.compareBoundaryPoints` constant for its
        // end-boundary check. It called
        // `range.compareBoundaryPoints(Range.END_TO_START, probe)` —
        // which compares `range`'s START boundary to `probe`'s END
        // boundary — when the hit-test needs `range`'s END vs `probe`'s
        // START, i.e. `Range.START_TO_END`. With the wrong constant
        // `endVsProbe` came back -1 for every tap past the highlight's
        // first character, the `endVsProbe >= 0` guard failed, no
        // `highlightTapHandler` message posted, and the inline Delete
        // menu never appeared. Device-verified in
        // `dev-docs/verification/feature-53-20260517-round5.md`.
        //
        // The assertions match the full call expression (not the bare
        // constant) so the explanatory JS comment — which names the
        // old `END_TO_START` constant on purpose — cannot satisfy or
        // break this guard.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(js.contains("compareBoundaryPoints(Range.START_TO_END, probe)"))
        #expect(!js.contains("compareBoundaryPoints(Range.END_TO_START, probe)"))
    }

    @Test
    func highlightAPIJS_removeHighlight_forcesRepaintOfAffectedRange() {
        // Bug #212 / GH #828: tapping "Delete Highlight" on an EPUB
        // highlight cleared persistence AND all JS/CSS highlight state
        // (`CSS.highlights.delete`, the `vreader-hl-style-*` element,
        // the `__vreader_highlightRanges` registry entry) — yet the
        // yellow paint lingered on screen until the chapter reloaded.
        // Deleting a CSS Highlight API entry does not reliably
        // invalidate an already-composited paged/columned EPUB column,
        // so `__vreader_removeHighlight` must additionally force the
        // removed range's container element to re-rasterize.
        //
        // The reliable nudge is a render-object rebuild — display
        // none → forced synchronous reflow (`offsetHeight`) → restore
        // — because a freshly-built RenderObject always paints fresh.
        // A paint-only invalidation (opacity / visibility toggle) is
        // exactly the class of invalidation WebKit drops here. These
        // assertions are a JS-bundle string guard: the JS is embedded
        // as a Swift string with no JS-execution harness, so pinning
        // the helper name + the rebuild mechanism is the right
        // lightweight guard (mirrors the suite's other JS-bundle
        // string assertions).
        let js = EPUBHighlightBridge.highlightAPIJS
        // Pin the call path inside __vreader_removeHighlight itself —
        // not just that the tokens exist somewhere in the bundle (the
        // range-capture line also appears in the click hit-test).
        // Slice the bundle to the removeHighlight function body so the
        // assertions cannot be satisfied by an unrelated code path.
        guard let removeStart = js.range(
            of: "window.__vreader_removeHighlight = function(id) {"
        )?.lowerBound else {
            Issue.record("highlightAPIJS no longer defines __vreader_removeHighlight")
            return
        }
        let afterRemove = String(js[removeStart...])
        guard let removeEnd = afterRemove.range(
            of: "window.__vreader_clearAllHighlights"
        )?.lowerBound else {
            Issue.record("__vreader_clearAllHighlights no longer follows removeHighlight")
            return
        }
        let removeBody = String(afterRemove[..<removeEnd])
        // Inside removeHighlight: capture the range, drop the registry
        // entry, then force the repaint of the affected block(s).
        #expect(removeBody.contains("var range = window.__vreader_highlightRanges[id];"))
        #expect(removeBody.contains("delete window.__vreader_highlightRanges[id];"))
        #expect(removeBody.contains("forceRangeRepaint(range);"))
        // The helper definition + its render-object-rebuild mechanism
        // (display toggle around a forced synchronous reflow).
        #expect(js.contains("function forceRangeRepaint("))
        #expect(js.contains("style.display = 'none'"))
        #expect(js.contains("offsetHeight"))
    }
}
