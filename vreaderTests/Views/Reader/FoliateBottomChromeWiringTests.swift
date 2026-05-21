// Purpose: Bug #260 / GH #1130 — RED tests for the AZW3/MOBI bottom
// chrome wiring. The live Foliate host (`FoliateBilingualContainerView`
// → `FoliateSpikeView`) never mounted `ReaderBottomChrome`, so AZW3/MOBI
// readers had no Contents / Notes / Display / AI toolbar and no
// reading-progress scrubber. These tests pin the two non-UI seams the
// fix introduces:
//
//   1. `.foliateRelocated` must carry the reading-progress `fraction`
//      (and `tocLabel`) so the container can drive the scrubber + the
//      progress label. Pre-fix the spike forwarded only `sectionIndex`
//      + `tocHref`, so there was no progress source for the bar.
//   2. The scrubber's seek action must build a clamped
//      `readerAPI.goToFraction(...)` JS string. `FoliateBottomChromeSeek`
//      is the pure seam (mirrors `FoliateSpikeView.Coordinator.setStylesJS`)
//      so the seek math + clamping are unit-testable without a live
//      WKWebView.
//
// @coordinates-with: FoliateSpikeView.swift,
//   FoliateBilingualContainerView.swift, FoliateBottomChromeSeek.swift,
//   ReaderNotifications.swift, ReaderBottomChrome.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bug #260 — AZW3/MOBI bottom chrome wiring")
struct FoliateBottomChromeWiringTests {

    /// Captures the userInfo of the first `.foliateRelocated` post.
    @MainActor
    private final class RelocateCapture {
        var fired = false
        var fraction: Double?
        var tocLabel: String?
        var sectionIndex: Int?
        var fingerprintKey: String?
    }

    // MARK: - Seam 1: relocate forwards the progress fraction

    @Test("relocate message forwards `fraction` on .foliateRelocated so the scrubber has a progress source")
    func relocateForwardsFraction() async {
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            onBookReady: { _ in },
            onError: { _ in }
        )
        coordinator.fingerprintKey = "azw3:abc:123"

        let capture = RelocateCapture()
        // Extract userInfo eagerly so the non-Sendable `Notification`
        // doesn't cross the assumeIsolated boundary (Swift 6 strict
        // concurrency) — same pattern as FoliateSpikeViewCreateOverlayTests.
        let token = NotificationCenter.default.addObserver(
            forName: .foliateRelocated, object: nil, queue: nil
        ) { note in
            let fraction = note.userInfo?["fraction"] as? Double
            let tocLabel = note.userInfo?["tocLabel"] as? String
            let sectionIndex = note.userInfo?["sectionIndex"] as? Int
            let fingerprintKey = note.userInfo?["fingerprintKey"] as? String
            MainActor.assumeIsolated {
                capture.fired = true
                capture.fraction = fraction
                capture.tocLabel = tocLabel
                capture.sectionIndex = sectionIndex
                capture.fingerprintKey = fingerprintKey
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // A real foliate-host.js relocate body (see FoliateMessageParser
        // expected keys): cfi, fraction, sectionIndex, sectionTotal,
        // tocLabel, tocHref.
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2)",
            "fraction": 0.42,
            "sectionIndex": 3,
            "sectionTotal": 12,
            "tocLabel": "Chapter 4",
            "tocHref": "ch04.xhtml",
        ]
        await coordinator.handleMessage(name: "relocate", body: body)

        #expect(capture.fired, "relocate must post .foliateRelocated")
        #expect(capture.fraction == 0.42,
                "Bug #260: the spike must forward the reading-progress `fraction` so the bottom-chrome scrubber tracks position")
        #expect(capture.tocLabel == "Chapter 4",
                "Bug #260: the spike should forward `tocLabel` so the bottom chrome can show the chapter title")
        #expect(capture.sectionIndex == 3, "existing sectionIndex forwarding must be preserved")
        #expect(capture.fingerprintKey == "azw3:abc:123", "fingerprintKey scoping must be preserved")
    }

    @Test("relocate forwards a zero fraction (book start) without dropping the key")
    func relocateForwardsZeroFraction() async {
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            onBookReady: { _ in },
            onError: { _ in }
        )
        coordinator.fingerprintKey = "azw3:abc:123"

        let capture = RelocateCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .foliateRelocated, object: nil, queue: nil
        ) { note in
            // Distinguish "key absent" from "key present == 0".
            let fraction = note.userInfo?["fraction"] as? Double
            MainActor.assumeIsolated {
                capture.fired = true
                capture.fraction = fraction
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // fraction arrives as Int 0 from JS at the very start of a book.
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": 0,
            "sectionIndex": 0,
            "sectionTotal": 12,
        ]
        await coordinator.handleMessage(name: "relocate", body: body)

        #expect(capture.fired)
        #expect(capture.fraction == 0.0,
                "Bug #260: a zero fraction (Int 0 from JS) at book start must still be forwarded, not dropped")
    }

    // MARK: - Seam 2: seek builds clamped goToFraction JS

    @Test("seek JS calls readerAPI.goToFraction with the seek value")
    func seekJSCallsGoToFraction() {
        let js = FoliateBottomChromeSeek.goToFractionJS(0.5)
        #expect(js == "readerAPI.goToFraction(0.5);",
                "Bug #260: the scrubber seek must drive Foliate-js `goToFraction`")
    }

    @Test("seek JS clamps a fraction above 1 to 1")
    func seekJSClampsHigh() {
        let js = FoliateBottomChromeSeek.goToFractionJS(1.7)
        #expect(js == "readerAPI.goToFraction(1.0);",
                "Bug #260: an out-of-range high seek must clamp to 1.0 (goToFraction expects 0...1)")
    }

    @Test("seek JS clamps a negative fraction to 0")
    func seekJSClampsLow() {
        let js = FoliateBottomChromeSeek.goToFractionJS(-0.3)
        #expect(js == "readerAPI.goToFraction(0.0);",
                "Bug #260: a negative seek must clamp to 0.0")
    }

    @Test("seek JS emits a JS-numeric literal (no injection surface, finite)")
    func seekJSIsFiniteNumericLiteral() {
        // NaN / infinity could otherwise serialize to a non-numeric JS
        // token and break the eval. Defensive: clamp resolves them to a
        // finite literal.
        let nanJS = FoliateBottomChromeSeek.goToFractionJS(.nan)
        let infJS = FoliateBottomChromeSeek.goToFractionJS(.infinity)
        #expect(nanJS == "readerAPI.goToFraction(0.0);",
                "Bug #260: NaN seek must resolve to a finite 0.0 literal")
        #expect(infJS == "readerAPI.goToFraction(1.0);",
                "Bug #260: +inf seek must resolve to the clamped 1.0 literal")
    }

    // MARK: - Seam 3: bottom-chrome position labels

    @Test("leading label uses the chapter title when present")
    func leadingLabelUsesTOCLabel() {
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: "Chapter 4", sectionIndex: 3, sectionTotal: 12, fraction: 0.42)
        #expect(labels.leading == "Chapter 4")
        #expect(labels.trailing == "Chapter 4 of 12")
    }

    @Test("leading label falls back to percentage when no TOC label")
    func leadingLabelFallsBackToPercent() {
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: nil, sectionIndex: 3, sectionTotal: 12, fraction: 0.42)
        #expect(labels.leading == "42%",
                "Bug #260: sparse AZW3/MOBI TOCs omit labels; the leading label must fall back to a reading percentage")
        #expect(labels.trailing == "Chapter 4 of 12")
    }

    @Test("blank TOC label is treated as absent")
    func blankTOCLabelTreatedAsAbsent() {
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: "   ", sectionIndex: 0, sectionTotal: 5, fraction: 0.1)
        #expect(labels.leading == "10%")
    }

    @Test("single-section book has no chapter-position trailing label")
    func singleSectionNoTrailing() {
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: nil, sectionIndex: 0, sectionTotal: 1, fraction: 0.6)
        #expect(labels.trailing == "",
                "Bug #260: a single-section book has no meaningful chapter position — trailing label stays empty")
        #expect(labels.leading == "60%")
    }

    @Test("missing section metadata yields empty trailing label")
    func missingSectionMetadataEmptyTrailing() {
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: nil, sectionIndex: nil, sectionTotal: nil, fraction: 0.5)
        #expect(labels.trailing == "")
        #expect(labels.leading == "50%")
    }

    @Test("section index is clamped into 1...total in the trailing label")
    func sectionIndexClampedInTrailing() {
        // A transient out-of-range relocate index must not print
        // "Chapter 13 of 12".
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: nil, sectionIndex: 99, sectionTotal: 12, fraction: 1.0)
        #expect(labels.trailing == "Chapter 12 of 12")
    }

    @Test("percentage rounds and clamps (NaN -> 0%, >1 -> 100%)")
    func percentRoundsAndClamps() {
        #expect(FoliateBottomChromeLabels.percentLabel(0.456) == "46%")
        #expect(FoliateBottomChromeLabels.percentLabel(.nan) == "0%")
        #expect(FoliateBottomChromeLabels.percentLabel(1.5) == "100%")
        #expect(FoliateBottomChromeLabels.percentLabel(-0.2) == "0%")
        #expect(FoliateBottomChromeLabels.percentLabel(0.0) == "0%")
    }
}
#endif
