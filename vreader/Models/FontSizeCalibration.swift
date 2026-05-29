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
    /// **Bug #280 re-tune (sim-measured 2026-05-30, iPhone 17 Pro):** the
    /// prior EPUB/Foliate multipliers were both `1.12`, a "conservative
    /// estimate" that was never device-verified. A direct cap-height
    /// measurement (`FontSizeCalibrationMeasurementTests`, a live WKWebView
    /// rendering the SAME body CSS the engines inject, cap-height read via
    /// Canvas `actualBoundingBoxAscent`, size-invariance control at 40px)
    /// showed:
    ///   - EPUB: `capHeight(txt 24pt) / capHeight(epub 24px)` =
    ///     `16.910 / 16.906` = `1.0002` → the `-apple-system` CSS stack
    ///     resolves to the SAME SF Pro face UIKit uses and 1 CSS px = 1 UIKit
    ///     point, so EPUB is already at cap-height parity with TXT. The old
    ///     `1.12` over-inflated EPUB by 12% — the "default body font too
    ///     large" report (bug #280).
    ///   - Foliate: `16.910 / 15.891` = `1.064` → the default UA font renders
    ///     marginally smaller-capped than UIKit at the same px, so a small
    ///     `> 1.0` lift restores parity. The old `1.12` over-inflated it ~5%.
    /// MD is a `UITextView` like TXT, so it stays at `1.0` (at the default
    /// content-size category the `UIFontMetrics` wrap TXT applies is the
    /// identity, so MD and TXT share the same system-font metric). The
    /// architecture is unaffected by the literal change.
    static let standard = FontSizeCalibrationProfile(
        txt: 1.0,
        md: 1.0,
        epub: 1.0,
        foliate: 1.06
    )
}
