// Feature #75 WI-3 — tests for the pure parse + resolve half of the
// pre-pagination page-axis probe (the WKWebView eval is integration-tested
// on-device in WI-5).

import Testing
@testable import vreader

@Suite("EPUBPageAxisProbe")
struct EPUBPageAxisProbeTests {

    private func json(wm: String = "", dir: String = "", docDir: String = "", lang: String = "") -> String {
        #"{"wm":"\#(wm)","dir":"\#(dir)","docDir":"\#(docDir)","lang":"\#(lang)"}"#
    }

    @Test func resolvesVerticalRLFromWritingMode() {
        let axis = EPUBPageAxisProbe.resolve(
            from: json(wm: "vertical-rl", dir: "ltr"), hint: .auto)
        #expect(axis == .verticalRL)
    }

    @Test func resolvesHorizontalRTLFromComputedDirection() {
        let axis = EPUBPageAxisProbe.resolve(
            from: json(wm: "horizontal-tb", dir: "rtl"), hint: .ltr)
        #expect(axis == .horizontalRTL)
    }

    @Test func resolvesHorizontalLTRDefault() {
        let axis = EPUBPageAxisProbe.resolve(
            from: json(wm: "horizontal-tb", dir: "ltr"), hint: .auto)
        #expect(axis == .horizontalLTR)
    }

    @Test func ambiguousComputed_fallsBackToDocDir() {
        let axis = EPUBPageAxisProbe.resolve(
            from: json(wm: "horizontal-tb", dir: "", docDir: "rtl"), hint: .ltr)
        #expect(axis == .horizontalRTL)
    }

    @Test func ambiguousComputed_autoHint_rtlLang() {
        let axis = EPUBPageAxisProbe.resolve(
            from: json(wm: "horizontal-tb", dir: "", lang: "ar"), hint: .auto)
        #expect(axis == .horizontalRTL)
    }

    // MARK: - Robustness

    @Test func nilResult_fallsBackToHint() {
        #expect(EPUBPageAxisProbe.resolve(from: nil, hint: .rtl) == .horizontalRTL)
        #expect(EPUBPageAxisProbe.resolve(from: nil, hint: .ltr) == .horizontalLTR)
    }

    @Test func malformedJSON_fallsBackToHint() {
        #expect(EPUBPageAxisProbe.resolve(from: "not json", hint: .rtl) == .horizontalRTL)
        #expect(EPUBPageAxisProbe.resolve(from: 42, hint: .ltr) == .horizontalLTR)
    }

    @Test func parse_emptyOnGarbage() {
        #expect(EPUBPageAxisProbe.parse(nil).isEmpty)
        #expect(EPUBPageAxisProbe.parse("[]").isEmpty)
        #expect(EPUBPageAxisProbe.parse("{\"wm\":\"vertical-rl\"}")["wm"] == "vertical-rl")
    }

    @Test func computedStyleJS_readsBodyAndDocElement() {
        // Contract: the probe reads computed body style + the doc dir/lang.
        #expect(EPUBPageAxisProbe.computedStyleJS.contains("getComputedStyle(document.body)"))
        #expect(EPUBPageAxisProbe.computedStyleJS.contains("writingMode"))
        #expect(EPUBPageAxisProbe.computedStyleJS.contains("direction"))
    }
}
