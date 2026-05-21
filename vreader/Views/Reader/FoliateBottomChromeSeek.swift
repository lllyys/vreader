// Purpose: Bug #260 / GH #1130 — pure seam for the AZW3/MOBI bottom
// chrome's reading-progress scrubber seek. Builds the
// `readerAPI.goToFraction(...)` JS the live Foliate spike evaluates
// when the user drags the bottom-chrome scrubber.
//
// Extracted as a pure static so the clamp + literal-formatting are
// unit-testable without a live WKWebView — mirrors
// `FoliateSpikeView.Coordinator.setStylesJS(forCSS:)`.
//
// @coordinates-with: FoliateBilingualContainerView.swift,
//   FoliateSpikeView.swift (the .foliateRequestSeekFraction observer),
//   FoliateBottomChromeWiringTests.swift,
//   vreader/Services/Foliate/JS/foliate-host.js (readerAPI.goToFraction)

import Foundation

/// Builds the Foliate-js seek JS for the bottom-chrome scrubber.
enum FoliateBottomChromeSeek {

    /// Returns `readerAPI.goToFraction(<v>);` where `<v>` is the seek
    /// value clamped to `0...1` and formatted as a finite JS numeric
    /// literal. NaN / infinity (which could otherwise serialize to a
    /// non-numeric token and break the eval) resolve to the clamped
    /// finite bound. The value is a `Double`, so there is no string
    /// injection surface — clamping is purely a render-correctness +
    /// finiteness guard.
    static func goToFractionJS(_ fraction: Double) -> String {
        let clamped: Double
        if fraction.isNaN {
            clamped = 0
        } else {
            clamped = min(1.0, max(0.0, fraction))
        }
        // `clamped` is finite and in 0...1; `%g`-style default
        // String(Double) yields a JS-parseable literal (e.g. "0.5",
        // "1.0", "0.0"). Force a fractional form for the integer bounds
        // so the literal is unambiguous.
        let literal: String
        if clamped == clamped.rounded(), clamped == 0 || clamped == 1 {
            literal = clamped == 0 ? "0.0" : "1.0"
        } else {
            literal = String(clamped)
        }
        return "readerAPI.goToFraction(\(literal));"
    }
}
