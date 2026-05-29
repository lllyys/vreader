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

    // MARK: - MED-4 paged-only gate

    @Test("bilingual is supported in the paged layout")
    func bilingualSupportedPaged() {
        #expect(ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: .paged) == true)
    }

    @Test("bilingual is NOT supported in the scroll layout (continuous is WI-12)")
    func bilingualUnsupportedScroll() {
        #expect(ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: .scroll) == false)
    }

    // MARK: - Gate-4 round-3 MED-3: layout-change action decision

    @Test("paged→scroll while enabled clears decorations + resets the tracker")
    func layoutChangePagedToScrollClears() {
        let action = ReadiumBilingualChapterTracker.layoutChangeAction(
            newLayout: .scroll, isEnabled: true)
        #expect(action == .clearAndReset)
    }

    @Test("scroll→paged while enabled re-enumerates the current chapter")
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

    // MARK: - Gate-4 round-3 MED (Finding B): first-enable confirmation must
    // ALWAYS precede enumeration. The unsupported-layout (scroll) enable path used
    // to early-return AFTER clearing without presenting the setup sheet, so a later
    // switch back to paged ran the `.reEnumerate` enumerate with the DEFAULT
    // language/granularity — skipping the first-enable confirmation. The invariant:
    // never enumerate while `needsSetupSheet == true`.

    @Test("enable while NEEDS SETUP presents the setup sheet even in scroll (no enumerate)")
    func enableInScrollPresentsSetupNoEnumerate() {
        // First enable (needsSetupSheet) while the layout is scroll (unsupported).
        // The sheet is layout-independent — it MUST be presented; enumerate is
        // paged-gated and must NOT run.
        let action = ReadiumBilingualChapterTracker.enableToggleAction(
            needsSetupSheet: true, layoutSupported: false)
        #expect(action == .presentSetup)
    }

    @Test("enable while NEEDS SETUP in paged presents the setup sheet (no direct enumerate)")
    func enableInPagedNeedsSetupPresentsSetup() {
        let action = ReadiumBilingualChapterTracker.enableToggleAction(
            needsSetupSheet: true, layoutSupported: true)
        #expect(action == .presentSetup)
    }

    @Test("re-enable (already configured) in paged enumerates straight away")
    func reEnableConfiguredPagedEnumerates() {
        let action = ReadiumBilingualChapterTracker.enableToggleAction(
            needsSetupSheet: false, layoutSupported: true)
        #expect(action == .enumerate)
    }

    @Test("re-enable (already configured) in scroll just clears (paged-gated, no enumerate)")
    func reEnableConfiguredScrollClearsOnly() {
        let action = ReadiumBilingualChapterTracker.enableToggleAction(
            needsSetupSheet: false, layoutSupported: false)
        #expect(action == .clearOnly)
    }

    @Test("reEnumerate is BLOCKED while setup is still pending (returning to paged before confirm)")
    func reEnumerateBlockedWhileSetupPending() {
        // The user first-enabled in scroll (setup raised), then switched back to
        // paged before confirming. The `.reEnumerate` path must NOT enumerate while
        // the setup sheet is still pending — that would use default settings.
        #expect(ReadiumBilingualChapterTracker.reEnumerateAllowed(needsSetupSheet: true) == false)
    }

    @Test("reEnumerate is allowed once setup is no longer pending")
    func reEnumerateAllowedAfterSetup() {
        #expect(ReadiumBilingualChapterTracker.reEnumerateAllowed(needsSetupSheet: false) == true)
    }

    @Test("confirm in scroll commits settings only — enumerate deferred to return-to-paged")
    func confirmInScrollCommitsOnly() {
        let action = ReadiumBilingualChapterTracker.confirmAction(layoutSupported: false)
        #expect(action == .commitOnly)
    }

    @Test("confirm in paged runs the first enumerate under the chosen settings")
    func confirmInPagedEnumerates() {
        let action = ReadiumBilingualChapterTracker.confirmAction(layoutSupported: true)
        #expect(action == .enumerate)
    }
}
#endif
