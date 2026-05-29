// Purpose: Feature #42 WI-11a (Gate-4 audit fixes) — pin the pure decision logic
// the Readium bilingual driver depends on, factored out of the SwiftUI host so it
// is unit-testable:
//   - MED-3 same-chapter dedupe: `shouldEnumerate(forHref:force:)` records the
//     in-flight href SYNCHRONOUSLY so a repeated `locationDidChange` for the same
//     href before the async enumerate completes does NOT schedule a second
//     enumerate; a `force` (toggle/confirm) bypasses the dedupe.
//   - HIGH-1 visible-chapter resolution: `selectedHref` prefers the supplied
//     Readium href, then the last-known locator href, then the last-enumerated
//     href — so a first-enable on the currently-rendered chapter resolves a unit
//     instead of nil.
//   - MED-4 paged-only gate: `isBilingualSupported(forLayout:)` is true only for
//     `.paged` (continuous-scroll bilingual is WI-12).
//
// @coordinates-with: ReadiumEPUBHost+Bilingual.swift,
//   ReadiumEPUBHost+BilingualDriver.swift, EPUBLayoutPreference.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #42 WI-11a — ReadiumBilingualChapterTracker decision logic")
struct ReadiumBilingualChapterTrackerTests {

    // MARK: - MED-3 same-chapter dedupe

    @Test("two same-href organic triggers enumerate once (dedupe is synchronous)")
    func sameHrefDedupesSynchronously() {
        let tracker = ReadiumBilingualChapterTracker()
        // First organic location change for chapter1 → should enumerate.
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
        // A repeated location change for the SAME href arrives BEFORE the async
        // enumerate has called markEnumerated — must be deduped (race that MED-3
        // reported), because the in-flight href was recorded synchronously.
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == false)
    }

    @Test("a different href after a pending enumerate re-enumerates")
    func differentHrefReEnumerates() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
        #expect(tracker.shouldEnumerate(forHref: "chapter2.xhtml", force: false) == true)
    }

    @Test("force bypasses the dedupe even for the same href (toggle/confirm path)")
    func forceBypassesDedupe() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
        // The user enabled bilingual on the chapter they were already reading —
        // a forced enumerate must run even though the href matches.
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: true) == true)
    }

    @Test("a nil href forced (toggle with no locator yet) is allowed once")
    func nilHrefForcedAllowed() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: nil, force: true) == true)
    }

    @Test("markEnumerated updates the dedupe key so a later same-href organic change dedupes")
    func markEnumeratedUpdatesKey() {
        let tracker = ReadiumBilingualChapterTracker()
        _ = tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false)
        tracker.markEnumerated(href: "chapter1.xhtml")
        #expect(tracker.lastEnumeratedHref == "chapter1.xhtml")
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == false)
    }

    @Test("reset clears the dedupe state so the next change re-enumerates")
    func resetClears() {
        let tracker = ReadiumBilingualChapterTracker()
        _ = tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false)
        tracker.markEnumerated(href: "chapter1.xhtml")
        tracker.reset()
        #expect(tracker.lastEnumeratedHref == nil)
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
    }

    // MARK: - HIGH-1 visible-chapter href selection

    @Test("selectedHref prefers the supplied Readium locator href")
    func selectedHrefPrefersSupplied() {
        let href = ReadiumBilingualChapterTracker.selectedHref(
            supplied: "OEBPS/c3.xhtml", lastKnown: "OEBPS/c1.xhtml",
            lastEnumerated: "c2.xhtml")
        #expect(href == "OEBPS/c3.xhtml")
    }

    @Test("selectedHref falls back to the last-known locator when none supplied (first-enable)")
    func selectedHrefFallsBackToLastKnown() {
        // The toggle/confirm path passes the last-known locator, NOT nil — the
        // HIGH-1 fix. With no supplied href but a last-known one, that resolves.
        let href = ReadiumBilingualChapterTracker.selectedHref(
            supplied: nil, lastKnown: "OEBPS/c1.xhtml", lastEnumerated: nil)
        #expect(href == "OEBPS/c1.xhtml")
    }

    @Test("selectedHref falls back to the last-enumerated href last (prefetch-landed inject, no locator)")
    func selectedHrefFallsBackToLastEnumerated() {
        let href = ReadiumBilingualChapterTracker.selectedHref(
            supplied: nil, lastKnown: nil, lastEnumerated: "c2.xhtml")
        #expect(href == "c2.xhtml")
    }

    @Test("selectedHref is nil only when every source is nil")
    func selectedHrefNilWhenAllNil() {
        let href = ReadiumBilingualChapterTracker.selectedHref(
            supplied: nil, lastKnown: nil, lastEnumerated: nil)
        #expect(href == nil)
    }

    // MARK: - MED-4 paged-only gate

    @Test("bilingual is supported in the paged layout")
    func bilingualSupportedPaged() {
        #expect(ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: .paged) == true)
    }

    @Test("bilingual is NOT supported in the scroll layout (continuous is WI-12)")
    func bilingualUnsupportedScroll() {
        #expect(ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: .scroll) == false)
    }
}
#endif
