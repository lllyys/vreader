// Purpose: Feature #54 Phase D-1 — pins the CFI-safe EPUB replacement-injection
// JS builder (`EPUBReplacementJS.injectionJS`).
//
// @coordinates-with: EPUBReplacementJS.swift, ReplacementTransform.swift

import Testing
import Foundation
@testable import vreader

@Suite("EPUBReplacementJS (feature #54 Phase D-1)")
struct EPUBReplacementJSTests {

    private func rule(_ pattern: String, _ replacement: String,
                      isRegex: Bool = false, enabled: Bool = true, order: Int = 0)
    -> ReplacementRuleDescriptor {
        ReplacementRuleDescriptor(pattern: pattern, replacement: replacement,
                                  isRegex: isRegex, enabled: enabled, order: order)
    }

    @Test("no enabled rules → empty string (caller skips injection)")
    func emptyWhenNoRules() {
        #expect(EPUBReplacementJS.injectionJS(rules: []) == "")
        #expect(EPUBReplacementJS.injectionJS(rules: [rule("a", "b", enabled: false)]) == "")
    }

    @Test("string rule → JSON-encoded rule array + non-recursive replace-all")
    func stringRuleEmitsJSON() {
        let js = EPUBReplacementJS.injectionJS(rules: [rule("Introduction", "Prologue")])
        #expect(js.contains("{\"p\":\"Introduction\",\"r\":\"Prologue\",\"x\":false}")
             || js.contains("\"p\":\"Introduction\""))
        #expect(js.contains("\"Prologue\""))
        // string path uses split().join() (replace-all, non-recursive)
        #expect(js.contains("split(c.p).join(c.r)"))
    }

    @Test("regex rule sets x:true and compiles a global RegExp")
    func regexRuleFlag() {
        let js = EPUBReplacementJS.injectionJS(rules: [rule("colou?r", "color", isRegex: true)])
        #expect(js.contains("\"x\":true"))
        #expect(js.contains("new RegExp(rule.p, \"g\")"))
    }

    @Test("user strings are JSON-escaped — no raw JS injection")
    func escapesUserStrings() {
        // A pattern with a double-quote + backslash must be JSON-escaped so it
        // cannot break out of the rule literal.
        let js = EPUBReplacementJS.injectionJS(rules: [rule("a\"b\\c", "x</script>")])
        #expect(js.contains("a\\\"b\\\\c"))           // JSON-escaped quote + backslash
        #expect(!js.contains("a\"b\\c\","))           // not raw-injected
        #expect(js.contains("x<\\/script>") || js.contains("x</script>"))
    }

    @Test("CFI-safe + per-section idempotent: only text nodes, skip script/style")
    func cfiSafeStructure() {
        let js = EPUBReplacementJS.injectionJS(rules: [rule("a", "b")])
        #expect(js.contains("createTreeWalker"))
        #expect(js.contains("NodeFilter.SHOW_TEXT"))
        #expect(js.contains("SCRIPT") && js.contains("STYLE"))
        // Section-scoped idempotency: process [data-vreader-spine-index] sections
        // (legacy stitch) / body (Readium) once each, marked via data-vreader-repl.
        #expect(js.contains("[data-vreader-spine-index]"))
        #expect(js.contains("data-vreader-repl"))
        #expect(js.contains("n.nodeValue = s"))                // mutates text only
        #expect(!js.contains("innerHTML"))                     // never structural
        // Legacy-stitch appended-section coverage via a scroll-root observer.
        #expect(js.contains("MutationObserver"))
        #expect(js.contains("vreader-scroll-root"))
    }

    @Test("disabled rules filtered, enabled rules order-sorted")
    func filterAndSort() {
        let js = EPUBReplacementJS.injectionJS(rules: [
            rule("z", "Z", order: 2),
            rule("disabled", "X", enabled: false),
            rule("a", "A", order: 1),
        ])
        #expect(!js.contains("\"disabled\""))
        // order: "a"(1) appears before "z"(2) in the emitted JSON array
        let aIdx = js.range(of: "\"a\"")
        let zIdx = js.range(of: "\"z\"")
        #expect(aIdx != nil && zIdx != nil)
        if let a = aIdx, let z = zIdx { #expect(a.lowerBound < z.lowerBound) }
    }
}
