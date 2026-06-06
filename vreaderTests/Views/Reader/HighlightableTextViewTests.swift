// Purpose: Tests for HighlightableTextView and HighlightingLayoutManager.
// Validates highlight range updates, source text setting, and isReplacingText guard.

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("HighlightableTextView")
struct HighlightableTextViewTests {

    // MARK: - HighlightingLayoutManager

    @Test @MainActor func layoutManagerStartsWithEmptyHighlights() {
        let tv = HighlightableTextView()
        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.isEmpty)
        #expect(lm.searchHighlightRange == nil)
    }

    // MARK: - setHighlightRanges

    @Test @MainActor func setHighlightRangesUpdatesLayoutManager() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let persisted = [PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "yellow")]
        tv.setHighlightRanges(persisted: persisted, active: nil)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.count == 1)
        #expect(lm.persistedHighlights[0].range == NSRange(location: 0, length: 5))
        #expect(lm.searchHighlightRange == nil)
    }

    @Test @MainActor func setHighlightRangesCarriesPersistedColor() {
        // Bug #208 / GH #776: a persisted highlight's color must reach the
        // layout-manager painter unchanged.
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        tv.setHighlightRanges(
            persisted: [PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "pink")],
            active: nil
        )

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.first?.colorName == "pink")
    }

    @Test @MainActor func setHighlightRangesSetsActiveRangeSeparately() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let persisted = [PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "green")]
        let active = NSRange(location: 6, length: 5)
        tv.setHighlightRanges(persisted: persisted, active: active)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.count == 1)
        #expect(lm.persistedHighlights[0].range == NSRange(location: 0, length: 5))
        #expect(lm.searchHighlightRange == NSRange(location: 6, length: 5))
    }

    @Test @MainActor func setHighlightRangesIgnoresZeroLengthActive() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello"))
        tv.setHighlightRanges(persisted: [], active: NSRange(location: 0, length: 0))

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.isEmpty)
        #expect(lm.searchHighlightRange == nil)
    }

    @Test @MainActor func setHighlightRangesWithEmptyInputsClearsRanges() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello"))
        tv.setHighlightRanges(
            persisted: [PaintedHighlight(range: NSRange(location: 0, length: 3), colorName: "blue")],
            active: nil
        )
        tv.setHighlightRanges(persisted: [], active: nil)

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.isEmpty)
        #expect(lm.searchHighlightRange == nil)
    }

    // MARK: - setSourceText

    @Test @MainActor func setSourceTextSetsTextStorageContent() {
        let tv = HighlightableTextView()
        let text = NSAttributedString(string: "Test content")
        tv.setSourceText(text)

        #expect(tv.textStorage.string == "Test content")
    }

    @Test @MainActor func setSourceTextPreservesContentOffset() {
        let tv = HighlightableTextView()
        tv.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        tv.setSourceText(NSAttributedString(string: String(repeating: "Line\n", count: 100)))
        tv.contentOffset = CGPoint(x: 0, y: 50)

        tv.setSourceText(NSAttributedString(string: String(repeating: "Line\n", count: 100)))
        #expect(tv.contentOffset.y == 50)
    }

    // MARK: - isReplacingText guard

    @Test @MainActor func isReplacingTextStartsFalse() {
        let tv = HighlightableTextView()
        #expect(tv.isReplacingText == false)
    }

    @Test @MainActor func isReplacingTextResetsAfterSetSourceText() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "test"))
        #expect(tv.isReplacingText == false)
    }

    // MARK: - Bounds safety (audit fix)

    @Test @MainActor func setHighlightRangesDeduplicatesActiveMatchingPersisted() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let range = NSRange(location: 0, length: 5)
        tv.setHighlightRanges(
            persisted: [PaintedHighlight(range: range, colorName: "yellow")],
            active: range
        )

        let lm = tv.layoutManager as! HighlightingLayoutManager
        // Active duplicates a persisted range — it must not also paint as
        // a search highlight (two translucent fills would stack).
        #expect(lm.persistedHighlights.count == 1)
        #expect(lm.searchHighlightRange == nil)
    }

    @Test @MainActor func outOfBoundsRangeDoesNotCrashDrawBackground() {
        let tv = HighlightableTextView()
        tv.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        tv.setSourceText(NSAttributedString(string: "Short"))
        // Range extends way past text storage length
        tv.setHighlightRanges(
            persisted: [PaintedHighlight(range: NSRange(location: 0, length: 9999), colorName: "yellow")],
            active: nil
        )

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.persistedHighlights.count == 1)
        // Force layout — this would crash without bounds clamping
        lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: 5))
    }

    // MARK: - Feature #74: locate-bloom readback (DEBUG verification harness)

    #if DEBUG
    @Test @MainActor func bloomReadbackStartsAtZero() {
        let tv = HighlightableTextView()
        #expect(tv.bloomPlayCount == 0)
        #expect(tv.lastBloomPeakIntensity == 0)
    }

    @Test @MainActor func playLandingBloomIncrementsPlayCount() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        tv.playLandingBloom(
            range: NSRange(location: 0, length: 5), colorName: "yellow",
            family: .light, reduceMotion: false
        )
        #expect(tv.bloomPlayCount == 1)
        // Seeding frame 0 (motion curve t=0 → intensity 0) shouldn't yet lift
        // the recorded peak above resting; a driven tick does.
        tv.recordBloomTickForTests(elapsedMs: 200)  // hold band → intensity 1
        #expect(tv.lastBloomPeakIntensity > 0.4)
        tv.cancelLandingBloom()
    }

    @Test @MainActor func bloomPeakPersistsAfterCancel() {
        // The readback must survive teardown so a POST-settle snapshot proves
        // the bloom fired + reached a peak.
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        tv.playLandingBloom(
            range: NSRange(location: 0, length: 5), colorName: "yellow",
            family: .light, reduceMotion: false
        )
        tv.recordBloomTickForTests(elapsedMs: 200)
        let peak = tv.lastBloomPeakIntensity
        tv.cancelLandingBloom()
        #expect(tv.lastBloomPeakIntensity == peak)
        #expect(tv.bloomPlayCount == 1)
    }

    @Test @MainActor func bloomPlayCountAccumulatesAcrossPlays() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        let range = NSRange(location: 0, length: 5)
        tv.playLandingBloom(range: range, colorName: "yellow", family: .light, reduceMotion: false)
        tv.cancelLandingBloom()
        tv.playLandingBloom(range: range, colorName: "yellow", family: .light, reduceMotion: false)
        #expect(tv.bloomPlayCount == 2)
        tv.cancelLandingBloom()
    }

    @Test @MainActor func bloomPeakRecordsMaxAcrossTicks() {
        let tv = HighlightableTextView()
        tv.setSourceText(NSAttributedString(string: "Hello World"))
        tv.playLandingBloom(
            range: NSRange(location: 0, length: 5), colorName: "yellow",
            family: .light, reduceMotion: false
        )
        tv.recordBloomTickForTests(elapsedMs: 200)  // intensity 1 (hold)
        tv.recordBloomTickForTests(elapsedMs: 1400) // decaying — lower intensity
        // Peak must hold the max, not the most-recent tick value.
        #expect(tv.lastBloomPeakIntensity > 0.4)
        tv.cancelLandingBloom()
    }
    #endif

    // MARK: - Convenience init

    @Test @MainActor func convenienceInitCreatesHighlightingLayoutManager() {
        let tv = HighlightableTextView()
        #expect(tv.layoutManager is HighlightingLayoutManager)
    }

    @Test @MainActor func convenienceInitHasTextContainer() {
        let tv = HighlightableTextView()
        #expect(tv.textContainer.layoutManager === tv.layoutManager)
    }

}
