// Purpose: Tests for FontSizeCalibration value types — CalibrationTarget enum
// exhaustiveness, FontSizeCalibrationProfile field mapping, anchor invariant,
// and Equatable round-trip. Feature #70 WI-1.

import Testing
import Foundation
@testable import vreader

@Suite("FontSizeCalibration")
struct FontSizeCalibrationTests {

    // MARK: - CalibrationTarget

    /// PDF is intentionally absent — PDFKit has no text-size input. Guards
    /// the "PDF is not calibratable" decision against accidental extension.
    @Test func calibrationTargetHasExactlyFourCases() {
        #expect(CalibrationTarget.allCases.count == 4)
        #expect(Set(CalibrationTarget.allCases) == [.txt, .md, .epub, .foliate])
    }

    @Test func calibrationTargetRawValuesAreStable() {
        #expect(CalibrationTarget.txt.rawValue == "txt")
        #expect(CalibrationTarget.md.rawValue == "md")
        #expect(CalibrationTarget.epub.rawValue == "epub")
        #expect(CalibrationTarget.foliate.rawValue == "foliate")
    }

    // MARK: - Anchor Invariant

    /// TXT/UITextView point is the anchor — its multiplier is 1.0 by
    /// definition, so the calibration system is re-anchored on (not changed
    /// from) the existing TXT appearance.
    @Test func standardProfileTXTMultiplierIsAnchorIdentity() {
        #expect(FontSizeCalibrationProfile.standard.multiplier(for: .txt) == 1.0)
        #expect(FontSizeCalibrationProfile.standard.txt == 1.0)
    }

    // MARK: - multiplier(for:)

    /// The total `switch` in `multiplier(for:)` is compiler-checked for
    /// exhaustiveness; this parameterized test proves each case maps to the
    /// matching stored field.
    @Test(arguments: CalibrationTarget.allCases)
    func multiplierReturnsMatchingField(_ target: CalibrationTarget) {
        let probe = FontSizeCalibrationProfile(txt: 1.1, md: 2.2, epub: 3.3, foliate: 4.4)
        let expected: Double
        switch target {
        case .txt: expected = 1.1
        case .md: expected = 2.2
        case .epub: expected = 3.3
        case .foliate: expected = 4.4
        }
        #expect(probe.multiplier(for: target) == expected)
    }

    // MARK: - Standard Profile Sanity

    /// All four shipped multipliers must be finite and strictly positive — a
    /// zero, negative, or NaN multiplier would produce a nonsense rendered
    /// size.
    @Test(arguments: CalibrationTarget.allCases)
    func standardProfileMultipliersAreFiniteAndPositive(_ target: CalibrationTarget) {
        let value = FontSizeCalibrationProfile.standard.multiplier(for: target)
        #expect(value.isFinite)
        #expect(value > 0)
    }

    // MARK: - Equatable

    @Test func profileEquatableRoundTrips() {
        let a = FontSizeCalibrationProfile(txt: 1.0, md: 1.05, epub: 1.12, foliate: 1.12)
        let b = FontSizeCalibrationProfile(txt: 1.0, md: 1.05, epub: 1.12, foliate: 1.12)
        #expect(a == b)
    }

    @Test func profileEquatableDistinguishesEveryField() {
        let base = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.0)
        #expect(base != FontSizeCalibrationProfile(txt: 2.0, md: 1.0, epub: 1.0, foliate: 1.0))
        #expect(base != FontSizeCalibrationProfile(txt: 1.0, md: 2.0, epub: 1.0, foliate: 1.0))
        #expect(base != FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 2.0, foliate: 1.0))
        #expect(base != FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 2.0))
    }
}
