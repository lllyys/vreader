// Purpose: Feature #42 WI-11a/WI-12 — pin the pure decision logic the Readium
// bilingual driver depends on, factored out of the SwiftUI host so it is
// unit-testable:
//   - MED-3 same-chapter dedupe: `shouldEnumerate(forHref:force:)` records the
//     in-flight href SYNCHRONOUSLY so a repeated `locationDidChange` for the same
//     href before the async enumerate completes does NOT schedule a second
//     enumerate; a `force` (toggle/confirm) bypasses the dedupe.
//   - HIGH-1 visible-chapter resolution: `selectedHref` prefers the supplied
//     Readium href, then the last-known locator href, then the last-enumerated
//     href — so a first-enable on the currently-rendered chapter resolves a unit
//     instead of nil.
//   - WI-12 per-spine parity: `isBilingualSupported(forLayout:)` is now true for
//     BOTH `.paged` and `.scroll` (Readium scroll mode enumerates per-spine on
//     scroll-into-view; it does NOT reproduce legacy #71's stitched cross-chapter
//     continuous bilingual). A layout change while enabled RE-ENUMERATES in BOTH
//     directions (Readium re-renders the spine on a layout change → stale stamps
//     are gone).
//
// @coordinates-with: ReadiumEPUBHost+Bilingual.swift,
//   ReadiumEPUBHost+BilingualDriver.swift, EPUBLayoutPreference.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #42 WI-11a/WI-12 — ReadiumBilingualChapterTracker decision logic")
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

    // MARK: - Gate-4 round-3 MED-2: revert in-flight on a FAILED enumerate

    @Test("clearInFlight after a FAILED same-href enumerate lets the next same-href change retry")
    func clearInFlightAllowsRetryAfterFailure() {
        let tracker = ReadiumBilingualChapterTracker()
        // Organic change for chapter1 → enumerate scheduled, in-flight href recorded.
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
        // The async enumerate FAILED (eval returned nil). The driver reverts the
        // in-flight mark for that href so the chapter is not stuck blank forever.
        tracker.clearInFlight(href: "chapter1.xhtml")
        #expect(tracker.lastEnumeratedHref == nil)
        // A later location change for the SAME chapter must now re-enumerate.
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
    }

    @Test("clearInFlight does NOT revert when a newer href already moved on (stale failure)")
    func clearInFlightIgnoresStaleHref() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: "chapter1.xhtml", force: false) == true)
        // The user already navigated to chapter2 (a fresh enumerate is in flight)
        // before chapter1's enumerate failed. Reverting chapter1 must NOT clobber
        // the chapter2 in-flight mark.
        #expect(tracker.shouldEnumerate(forHref: "chapter2.xhtml", force: false) == true)
        tracker.clearInFlight(href: "chapter1.xhtml")
        #expect(tracker.lastEnumeratedHref == "chapter2.xhtml")
        // chapter2 still deduped (its enumerate is legitimately in flight).
        #expect(tracker.shouldEnumerate(forHref: "chapter2.xhtml", force: false) == false)
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

    // MARK: - WI-12: per-spine bilingual supported in BOTH layouts

    @Test("bilingual is supported in the paged layout")
    func bilingualSupportedPaged() {
        #expect(ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: .paged) == true)
    }

    @Test("bilingual is now supported in the scroll layout (WI-12 per-spine parity)")
    func bilingualSupportedScroll() {
        // WI-12: Readium scroll mode enumerates per-spine on scroll-into-view, so
        // bilingual is supported in scroll too (was false in WI-11's paged-only gate).
        #expect(ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: .scroll) == true)
    }

    // MARK: - WI-12: layout-change re-enumerates in BOTH directions

    @Test("paged→scroll while enabled re-enumerates the current spine (Readium re-renders)")
    func layoutChangePagedToScrollReEnumerates() {
        // WI-12: a layout change re-renders the spine, so the old data-vreader-bid
        // stamps + decorations are gone — a fresh enumerate is required in BOTH
        // directions (was `.clearAndReset` in WI-11's paged-only gate).
        let action = ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: .scroll, isEnabled: true)
        #expect(action == .reEnumerate)
    }

    @Test("scroll→paged while enabled re-enumerates the current spine")
    func layoutChangeScrollToPagedReEnumerates() {
        let action = ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: .paged, isEnabled: true)
        #expect(action == .reEnumerate)
    }

    @Test("a layout change while DISABLED does nothing (no stale decorations to manage)")
    func layoutChangeDisabledNoop() {
        #expect(ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: .scroll, isEnabled: false) == BilingualLayoutChangeAction.none)
        #expect(ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: .paged, isEnabled: false) == BilingualLayoutChangeAction.none)
    }

    // MARK: - WI-12: first-enable confirmation must ALWAYS precede enumeration.
    // The setup sheet is layout-independent; with both layouts now supported, an
    // already-configured re-enable enumerates in BOTH layouts (no more scroll
    // `.clearOnly`). The invariant: never enumerate while `needsSetupSheet == true`.

    @Test("enable while NEEDS SETUP presents the setup sheet in scroll (no enumerate)")
    func enableInScrollPresentsSetupNoEnumerate() {
        // First enable (needsSetupSheet) while the layout is scroll. The sheet is
        // layout-independent — it MUST be presented; enumerate runs post-confirm.
        let action = ReadiumBilingualChapterTracker.enableToggleAction(needsSetupSheet: true)
        #expect(action == .presentSetup)
    }

    @Test("enable while NEEDS SETUP in paged presents the setup sheet (no direct enumerate)")
    func enableInPagedNeedsSetupPresentsSetup() {
        let action = ReadiumBilingualChapterTracker.enableToggleAction(needsSetupSheet: true)
        #expect(action == .presentSetup)
    }

    @Test("re-enable (already configured) enumerates straight away in both layouts")
    func reEnableConfiguredEnumerates() {
        // WI-12: scroll no longer `.clearOnly` — both layouts enumerate per-spine.
        let action = ReadiumBilingualChapterTracker.enableToggleAction(needsSetupSheet: false)
        #expect(action == .enumerate)
    }

    @Test("reEnumerate is BLOCKED while setup is still pending (first-enable not yet confirmed)")
    func reEnumerateBlockedWhileSetupPending() {
        // The user first-enabled (setup raised) then a layout change fired before
        // confirming. The `.reEnumerate` path must NOT enumerate while the setup
        // sheet is still pending — that would use default settings.
        #expect(ReadiumBilingualChapterTracker.reEnumerateAllowed(needsSetupSheet: true) == false)
    }

    @Test("reEnumerate is allowed once setup is no longer pending")
    func reEnumerateAllowedAfterSetup() {
        #expect(ReadiumBilingualChapterTracker.reEnumerateAllowed(needsSetupSheet: false) == true)
    }
}
#endif
