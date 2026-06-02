// Bug #304: the interlinear `.vreader-bilingual` style must reach the MODERN
// engines (Readium spine + Foliate setStyles), which don't thread
// `epubOverrideCSS` — otherwise the injected bilingual blocks render as plain
// body text. These CI-safe tests pin the three load-bearing pieces.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bilingual interlinear CSS injection (Bug #304)")
struct BilingualCSSInjectionTests {

    @Test("theme.bilingualBlockCSSRule emits the .vreader-bilingual interlinear rule")
    func themeRule() {
        let css = ReaderThemeV2.paper.bilingualBlockCSSRule()
        #expect(css.contains(".vreader-bilingual"))
        #expect(css.contains("font-size: 0.88em"))
        #expect(css.contains("user-select: none"))
        #expect(css.contains("border-left"))
    }

    @Test("bilingualStyleJS produces an idempotent <style> injection carrying the rule")
    func styleJS() {
        let js = EPUBBilingualJS.bilingualStyleJS(css: ReaderThemeV2.paper.bilingualBlockCSSRule())
        #expect(js.contains("vreader-bilingual-style"))   // the <style> element id
        #expect(js.contains("getElementById"))            // idempotent lookup
        #expect(js.contains("createElement('style')"))    // create only on miss
        #expect(js.contains("vreader-bilingual"))         // the CSS rule, escaped in
    }

    @Test("empty CSS still produces well-formed (no-op-safe) JS")
    func styleJSEmpty() {
        let js = EPUBBilingualJS.bilingualStyleJS(css: "")
        #expect(js.contains("vreader-bilingual-style"))
        #expect(js.contains("(function()"))
    }

    @Test("Foliate themeCSS includes the bilingual rule for a paper-themed store")
    func foliateThemeCSSIncludesBilingual() {
        let store = ReaderSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.theme = .paper
        let css = FoliateSpikeView.themeCSS(for: store)
        #expect(css?.contains(".vreader-bilingual") == true)
        // The base (font-size) CSS is still present.
        #expect(css?.contains("font-size") == true)
    }
}
