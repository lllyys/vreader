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

    // MARK: - Gate-4 (WI-12 audit) Finding 1: generation token discards stale
    // cross-spine enumerate results. In scroll mode rapid spine changes leave
    // multiple `await enumerate()` tasks in flight; a result is committed only if
    // its captured generation still matches the tracker's current generation.

    @Test("a fresh tracker starts at generation 0 and recognizes it as current")
    func generationStartsAtZero() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.currentGeneration == 0)
        #expect(tracker.isCurrentGeneration(0) == true)
    }

    @Test("scheduling an enumerate for a NEW href bumps the generation")
    func differentHrefBumpsGeneration() {
        let tracker = ReadiumBilingualChapterTracker()
        let g0 = tracker.currentGeneration
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: false) == true)
        let g1 = tracker.currentGeneration
        #expect(g1 > g0)
        #expect(tracker.shouldEnumerate(forHref: "c2.xhtml", force: false) == true)
        #expect(tracker.currentGeneration > g1)
    }

    @Test("a deduped same-href schedule does NOT bump the generation")
    func dedupedScheduleDoesNotBumpGeneration() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: false) == true)
        let g = tracker.currentGeneration
        // Repeated same-href organic trigger is deduped — no new enumerate
        // scheduled, so the generation must not advance.
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: false) == false)
        #expect(tracker.currentGeneration == g)
    }

    @Test("a forced (toggle/confirm) re-enumerate bumps the generation even for the same href")
    func forcedScheduleBumpsGeneration() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: false) == true)
        let g = tracker.currentGeneration
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: true) == true)
        #expect(tracker.currentGeneration > g)
    }

    @Test("reset bumps the generation (layout-change / disable invalidates in-flight tasks)")
    func resetBumpsGeneration() {
        let tracker = ReadiumBilingualChapterTracker()
        _ = tracker.shouldEnumerate(forHref: "c1.xhtml", force: false)
        let g = tracker.currentGeneration
        tracker.reset()
        #expect(tracker.currentGeneration > g)
    }

    @Test("chapter-1's STALE result is discarded after chapter-2 was scheduled (cross-spine guard)")
    func staleCrossSpineResultDiscarded() {
        let tracker = ReadiumBilingualChapterTracker()
        // Scroll mode: chapter-1 enumerate is scheduled; capture its generation
        // SYNCHRONOUSLY (this is what the driver does before the `await`).
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: false) == true)
        let chapter1Generation = tracker.currentGeneration
        // The user scrolls into chapter-2 before chapter-1's async enumerate
        // returns — a newer enumerate is scheduled, bumping the generation.
        #expect(tracker.shouldEnumerate(forHref: "c2.xhtml", force: false) == true)
        // chapter-1's enumerate now returns. Its captured generation is stale, so
        // the driver MUST discard the result (no updateBlocks/markEnumerated/inject).
        #expect(tracker.isCurrentGeneration(chapter1Generation) == false)
        // chapter-2's own result (captured at the current generation) still commits.
        #expect(tracker.isCurrentGeneration(tracker.currentGeneration) == true)
    }

    @Test("a generation captured before a chapter change is stale at EVERY post-await re-check (inject-chain guard)")
    func generationCapturedBeforeChangeStaleAtEachInjectCheck() {
        // Gate-4 round-2 MEDIUM (post-enumerate stale inject window): after a
        // CURRENT enumerate result passes the enumerate-boundary guard and calls
        // updateBlocks, the driver continues into drivePrefetchAndInject →
        // injectBilingualIfCached, which have MORE suspension points
        // (handlePositionChange, textProvider.unit, inject). If a newer spine is
        // scheduled DURING one of those later awaits, the older task can resume
        // and inject stale pairs into the now-visible chapter. The fix threads the
        // captured generation through the whole post-enumerate chain and re-checks
        // isCurrentGeneration after EACH suspension. This pins the decision: a
        // generation captured for chapter-1 is NOT current after chapter-2 was
        // scheduled, so EVERY downstream re-check (handlePositionChange,
        // textProvider.unit, pre-inject) discards.
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.shouldEnumerate(forHref: "c1.xhtml", force: false) == true)
        let chapter1Generation = tracker.currentGeneration
        // The enumerate-boundary check (round 2) passes: chapter-1 is still current
        // here, so the driver proceeds into the inject chain.
        #expect(tracker.isCurrentGeneration(chapter1Generation) == true)
        // The user scrolls into chapter-2 DURING the inject chain's first await
        // (handlePositionChange). A newer enumerate is scheduled.
        #expect(tracker.shouldEnumerate(forHref: "c2.xhtml", force: false) == true)
        // EVERY subsequent re-check in the chain — after handlePositionChange,
        // after textProvider.unit, immediately before inject — must now report
        // chapter-1 as stale and discard rather than inject c1's pairs into c2.
        #expect(tracker.isCurrentGeneration(chapter1Generation) == false)
        // A further spine change (chapter-3) keeps it stale at all later checks too.
        #expect(tracker.shouldEnumerate(forHref: "c3.xhtml", force: false) == true)
        #expect(tracker.isCurrentGeneration(chapter1Generation) == false)
    }

    // MARK: - Gate-4 round-4 (WI-12 audit) ROOT CAUSE: block-ownership invariant.
    // The shared `EPUBBilingualOrchestrator` holds ONE set of blocks in its paged
    // `-1` bucket. In Readium scroll mode rapid spine changes can leave spine A's
    // blocks committed while an inject runs for spine B's current locator — pairing
    // spine-B translations against spine-A bids (or `translateBlocksDirectly` on
    // spine-A block text for spine-B). The owner-href invariant records the href the
    // CURRENT committed blocks belong to and rejects an inject whose locator href
    // doesn't match. This closes BOTH inject entry points (the generation-guarded
    // enumerate chain AND the nil-generation `.readerBilingualDidChange` path) with
    // one invariant: an owner-href mismatch ALWAYS implies stale blocks.

    @Test("a fresh tracker owns no blocks, so blocksMatch is false for any href")
    func freshTrackerOwnsNoBlocks() {
        let tracker = ReadiumBilingualChapterTracker()
        #expect(tracker.blocksOwnerHref == nil)
        #expect(tracker.blocksMatch(locatorHref: "chapter1.xhtml") == false)
        #expect(tracker.blocksMatch(locatorHref: nil) == false)
    }

    @Test("after blocks committed for href A, an inject for A proceeds and for B is rejected")
    func ownerHrefGatesInjectByChapter() {
        let tracker = ReadiumBilingualChapterTracker()
        // The driver commits spine A's blocks and records the owner href at the
        // `updateBlocks` site.
        tracker.setBlocksOwner(href: "chapterA.xhtml")
        #expect(tracker.blocksOwnerHref == "chapterA.xhtml")
        // A settled inject for the SAME chapter (owner == locator href) proceeds.
        #expect(tracker.blocksMatch(locatorHref: "chapterA.xhtml") == true)
        // An inject for chapter B (current locator moved on, but A's blocks are
        // still in the shared bucket) is REJECTED — pairing B's translations
        // against A's bids would be the stale-cross-spine bug.
        #expect(tracker.blocksMatch(locatorHref: "chapterB.xhtml") == false)
    }

    @Test("blocksMatch is false against a nil locator href even when blocks are owned")
    func ownerHrefRejectsNilLocator() {
        let tracker = ReadiumBilingualChapterTracker()
        tracker.setBlocksOwner(href: "chapterA.xhtml")
        #expect(tracker.blocksMatch(locatorHref: nil) == false)
    }

    @Test("committing blocks for href B re-points the owner so B injects and A no longer matches")
    func ownerHrefRepointsOnNewCommit() {
        let tracker = ReadiumBilingualChapterTracker()
        tracker.setBlocksOwner(href: "chapterA.xhtml")
        // Scroll into B: the enumerate for B commits B's blocks + sets owner = B.
        tracker.setBlocksOwner(href: "chapterB.xhtml")
        #expect(tracker.blocksMatch(locatorHref: "chapterB.xhtml") == true)
        #expect(tracker.blocksMatch(locatorHref: "chapterA.xhtml") == false)
    }

    @Test("reset clears the block owner so no inject proceeds until blocks are re-committed")
    func resetClearsBlockOwner() {
        let tracker = ReadiumBilingualChapterTracker()
        tracker.setBlocksOwner(href: "chapterA.xhtml")
        tracker.reset()
        #expect(tracker.blocksOwnerHref == nil)
        #expect(tracker.blocksMatch(locatorHref: "chapterA.xhtml") == false)
    }

    @Test("clearing the block owner (disable / clear decorations) blocks subsequent injects")
    func clearBlockOwnerBlocksInject() {
        let tracker = ReadiumBilingualChapterTracker()
        tracker.setBlocksOwner(href: "chapterA.xhtml")
        tracker.clearBlocksOwner()
        #expect(tracker.blocksOwnerHref == nil)
        #expect(tracker.blocksMatch(locatorHref: "chapterA.xhtml") == false)
    }

    @Test("owner-href mismatch closes the nil-generation (.readerBilingualDidChange) inject path")
    func ownerHrefClosesNilGenerationPath() {
        // The `.readerBilingualDidChange` inject entry point passes generation: nil,
        // so the generation guards never fire for it. The owner-href invariant is
        // what stops it from pairing the current spine's translations against an
        // older spine's still-committed blocks: blocks owned by A, current locator
        // resolves to B → reject regardless of generation.
        let tracker = ReadiumBilingualChapterTracker()
        tracker.setBlocksOwner(href: "chapterA.xhtml")
        #expect(tracker.blocksMatch(locatorHref: "chapterB.xhtml") == false)
        // Once B's enumerate commits B's blocks, the prefetch-landed re-inject for B
        // proceeds.
        tracker.setBlocksOwner(href: "chapterB.xhtml")
        #expect(tracker.blocksMatch(locatorHref: "chapterB.xhtml") == true)
    }

    // MARK: - Gate-4 (WI-12 audit) Finding 2: layoutChangeAction uses newLayout to
    // FAIL CLOSED for any future unsupported layout case.

    @Test("layoutChangeAction fails closed (.none) for an unsupported layout even when enabled")
    func layoutChangeFailsClosedForUnsupportedLayout() {
        // The two current EPUBLayoutPreference cases (.paged/.scroll) are both
        // supported, so this asserts the supported branch returns .reEnumerate when
        // enabled — and that the decision is keyed on `newLayout` via
        // isBilingualSupported, so a future unsupported case would return .none.
        for layout in EPUBLayoutPreference.allCases {
            let supported = ReadiumBilingualChapterTracker.isBilingualSupported(forLayout: layout)
            let action = ReadiumBilingualChapterTracker.layoutChangeAction(
                newLayout: layout, isEnabled: true)
            if supported {
                #expect(action == .reEnumerate)
            } else {
                #expect(action == BilingualLayoutChangeAction.none)
            }
        }
    }

    @Test("layoutChangeAction is .none when disabled regardless of layout support")
    func layoutChangeNoneWhenDisabledAllLayouts() {
        for layout in EPUBLayoutPreference.allCases {
            #expect(ReadiumBilingualChapterTracker.layoutChangeAction(
                newLayout: layout, isEnabled: false) == BilingualLayoutChangeAction.none)
        }
    }
}
#endif
