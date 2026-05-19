// Purpose: Feature #68 WI-2 — tests for
// TXTReaderContainerView.makeAttrStringKey covering the chapter-start
// typography seam: the two new theme colors and the heading-line-length
// component must change the key so the `.task(id:)` rebuilds.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTViewConfig.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXTReaderContainerView — chapter-start key (feature #68 WI-2)")
struct TXTReaderContainerViewChapterStartTests {

    private func baseKey(config: TXTViewConfig, headingLineLength: Int = 0) -> String {
        TXTReaderContainerView.makeAttrStringKey(
            hasText: true, textLen: 1000, wordCount: 200,
            chIdx: 0, chCount: 5, config: config,
            chineseConversion: .none, headingLineLength: headingLineLength
        )
    }

    @Test("key changes when accentColor changes (live theme-switch rebuild trigger)")
    func keyChangesOnAccentColor() {
        var a = TXTViewConfig()
        var b = TXTViewConfig()
        a.accentColor = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        b.accentColor = UIColor(red: 0.84, green: 0.53, blue: 0.35, alpha: 1.0)
        #expect(baseKey(config: a) != baseKey(config: b))
    }

    @Test("key changes when chapterHeadingColor changes")
    func keyChangesOnHeadingColor() {
        var a = TXTViewConfig()
        var b = TXTViewConfig()
        a.chapterHeadingColor = UIColor(white: 0.55, alpha: 1.0)
        b.chapterHeadingColor = UIColor(white: 0.30, alpha: 1.0)
        #expect(baseKey(config: a) != baseKey(config: b))
    }

    @Test("key changes when the headingLineLength component changes")
    func keyChangesOnHeadingLineLength() {
        let config = TXTViewConfig()
        #expect(baseKey(config: config, headingLineLength: 0)
            != baseKey(config: config, headingLineLength: 11))
    }

    @Test("key is stable when the two new colors are at their defaults — no regression")
    func keyStableForDefaults() {
        // Two default configs must produce the same key — the new
        // components must not introduce nondeterminism.
        #expect(baseKey(config: TXTViewConfig()) == baseKey(config: TXTViewConfig()))
    }

    @Test("legacy callers omitting headingLineLength still produce a stable key")
    func legacyCallerDefaultParameter() {
        let config = TXTViewConfig()
        let withDefault = TXTReaderContainerView.makeAttrStringKey(
            hasText: true, textLen: 1000, wordCount: 200,
            chIdx: 0, chCount: 5, config: config, chineseConversion: .none
        )
        let explicitZero = TXTReaderContainerView.makeAttrStringKey(
            hasText: true, textLen: 1000, wordCount: 200,
            chIdx: 0, chCount: 5, config: config,
            chineseConversion: .none, headingLineLength: 0
        )
        #expect(withDefault == explicitZero)
    }

    @Test("key still changes on the pre-existing text/background color seam")
    func keyChangesOnTextColorRegressionGuard() {
        var a = TXTViewConfig()
        var b = TXTViewConfig()
        a.textColor = .black
        b.textColor = .darkGray
        #expect(baseKey(config: a) != baseKey(config: b))
    }
}
#endif
