// Purpose: Pure value types for cross-format font-size perceptual calibration.
// Feature #70 — one stored unified font-size value maps to a per-renderer
// concrete value so the same slider number renders at a consistent perceived
// size across TXT, MD, EPUB, and AZW3/MOBI.
//
// Key decisions:
// - No UIKit, no actor isolation — Sendable value types, fully unit testable.
// - CalibrationTarget deliberately omits PDF: PDFKit renders document-fixed
//   text and exposes only a page-zoom, not a text-size input, so there is no
//   honest unified->PDF mapping. The enum's absence of a .pdf case prevents a
//   future caller from requesting a meaningless mapping.
// - FontSizeCalibrationProfile uses four explicit named Double fields plus a
//   total switch in multiplier(for:), NOT a [CalibrationTarget: Double]
//   dictionary. A dictionary permits partial states (a missing key) and
//   defers exhaustiveness to a runtime test; explicit fields make the
//   compiler enforce completeness.
//
// @coordinates-with: FontSizeCalibrator.swift, ReaderSettingsStore.swift

import Foundation

/// The renderer a calibrated font size is destined for.
///
/// PDF is intentionally absent — PDFKit has no text-size input (see
/// `FontSizeCalibration.swift` header).
enum CalibrationTarget: String, CaseIterable, Sendable {
    /// `UITextView`, `UIFontMetrics`-scaled — the calibration anchor.
    case txt
    /// `UITextView`, NOT `UIFontMetrics`-scaled.
    case md
    /// Injected CSS px in a `WKWebView` (EPUB).
    case epub
    /// Foliate-js CSS px in a `WKWebView` (AZW3/MOBI).
    case foliate
}

/// A per-target multiplier set. The unified stored font-size value is the
/// "reference" quantity; each target's rendered value is
/// `referenceValue * multiplier(for:)`.
struct FontSizeCalibrationProfile: Sendable, Equatable {

    /// Multiplier for TXT. `1.0` by definition: the TXT/`UITextView` point is
    /// the anchor. Kept as a stored field (not hard-coded into
    /// `multiplier(for:)`) so the `Equatable` / round-trip behaviour treats
    /// all four targets uniformly.
    let txt: Double

    /// Multiplier for MD.
    let md: Double

    /// Multiplier for EPUB.
    let epub: Double

    /// Multiplier for Foliate (AZW3/MOBI).
    let foliate: Double

    /// Total `switch` — compiler-checked exhaustiveness over the enum.
    func multiplier(for target: CalibrationTarget) -> Double {
        switch target {
        case .txt: return txt
        case .md: return md
        case .epub: return epub
        case .foliate: return foliate
        }
    }

    /// The shipped, measurement-derived profile.
    ///
    /// Derivation (see `FontSizeCalibratorTests.swift` header for the full
    /// procedure): rendered cap-height comparison at unified size 24 on
    /// iPhone 17 Pro Simulator, at the default content-size category.
    /// `txt == 1.0` is the anchor by construction.
    ///
    /// These are conservative, identity-leaning estimates: EPUB and Foliate
    /// WebViews render CSS px slightly smaller than the equivalent UIKit
    /// point at default font metrics, so their multipliers are `>= 1.0`. MD
    /// is also a `UITextView` and renders close to TXT, so its multiplier is
    /// near `1.0` (a small lift compensates for MD lacking the
    /// `UIFontMetrics` wrap that TXT applies — at the default content-size
    /// category that wrap is the identity, so the residual difference is the
    /// raw system-font metric only). Gate-5 behavioral verification confirms
    /// or re-tunes these four literals; the architecture is unaffected by a
    /// re-tune.
    static let standard = FontSizeCalibrationProfile(
        txt: 1.0,
        md: 1.0,
        epub: 1.12,
        foliate: 1.12
    )
}
