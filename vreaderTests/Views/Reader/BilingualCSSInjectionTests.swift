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

    // MARK: - Feature #100: heading echo row rules (design BSHeadingPair)

    @Test("heading rows: centered, border-less, rem-sized, serif")
    func headingRule() {
        let css = ReaderThemeV2.paper.bilingualBlockCSSRule()
        #expect(css.contains(".vreader-bilingual--heading[data-vreader-decoration]"))
        #expect(css.contains("text-align: center !important"))
        #expect(css.contains("border-left: none !important"))
        #expect(css.contains("font-size: 0.95rem !important"))
    }

    @Test("CJK tracking applies ONLY under the --cjk modifier")
    func cjkTrackingGated() {
        let css = ReaderThemeV2.paper.bilingualBlockCSSRule()
        #expect(css.contains(".vreader-bilingual--heading.vreader-bilingual--cjk[data-vreader-decoration]"))
        #expect(css.contains("letter-spacing: 0.32em !important"))
        // The tracking must not leak into the base heading rule: it appears
        // exactly once, inside the --cjk-scoped rule.
        #expect(css.components(separatedBy: "letter-spacing").count == 2)
    }

    @Test("heading loading bar centers itself")
    func headingLoadingCentered() {
        let css = ReaderThemeV2.paper.bilingualBlockCSSRule()
        #expect(css.contains(".vreader-bilingual--heading.vreader-bilingual-loading[data-vreader-decoration] .vreader-shimmer-bar"))
        #expect(css.contains("margin-left: auto !important"))
        #expect(css.contains("margin-right: auto !important"))
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
