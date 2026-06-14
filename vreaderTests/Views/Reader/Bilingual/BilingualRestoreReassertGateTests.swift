// Purpose: Bug #352 — pin the one-shot, href-guarded latch the Readium
// host uses to re-assert the saved reading position AFTER the first
// bilingual inject on the restore-landing spine.
//
// Mechanism: with bilingual ON, the navigator restores to the saved
// (fraction-based) progression against the SOURCE-ONLY spine, fixes the
// page there, then the bilingual inject adds interlinear rows that grow
// the spine content under the just-restored page — so the held page now
// shows EARLIER content (the user lands backward, at the chapter start).
// Re-navigating to the saved locator AFTER the inject makes Readium
// re-resolve the fraction against the now-injected DOM. The gate ensures
// that re-assert fires EXACTLY once and ONLY for the restore-landing
// spine's inject (matched by href).
//
// @coordinates-with: ReadiumEPUBHost+BilingualDriver.swift,
//   ReadiumEPUBHost+Body.swift

#if canImport(UIKit)
import Testing
@testable import vreader

@MainActor
@Suite("Bug #352 — BilingualRestoreReassertGate one-shot href-guarded latch")
struct BilingualRestoreReassertGateTests {

    @Test("Armed + landing href matches the inject href → fires exactly once")
    func firesOnceForLandingSpine() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        gate.recordLanding(href: "ch1.xhtml")
        #expect(gate.isArmed == true)
        #expect(gate.consume(injectHref: "ch1.xhtml") == true)   // restore spine
        #expect(gate.consume(injectHref: "ch1.xhtml") == false)  // already fired
        #expect(gate.isArmed == false)
    }

    @Test("An inject on a DIFFERENT spine does NOT fire (user scrolled away before restore spine injected)")
    func differentSpineDoesNotFire() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        gate.recordLanding(href: "ch1.xhtml")
        #expect(gate.consume(injectHref: "ch2.xhtml") == false)  // not the restore spine
        #expect(gate.isArmed == true)                            // still pending
        #expect(gate.consume(injectHref: "ch1.xhtml") == true)   // the real one still fires
    }

    @Test("Only the FIRST relocate records the landing href")
    func landingHrefRecordedOnce() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        gate.recordLanding(href: "ch1.xhtml")
        gate.recordLanding(href: "ch2.xhtml")  // later relocate must not overwrite
        #expect(gate.landingHref == "ch1.xhtml")
        #expect(gate.consume(injectHref: "ch1.xhtml") == true)
    }

    @Test("Armed but no landing recorded yet → fires for the same-relocate inject (defensive)")
    func firesWhenLandingNotYetRecorded() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        // recordLanding never called (or href was nil) — the inject that
        // immediately follows the restore relocate should still re-assert.
        #expect(gate.consume(injectHref: "ch1.xhtml") == true)
    }

    @Test("An un-armed gate never fires (bilingual-off / nothing to restore)")
    func unarmedNeverFires() {
        let gate = BilingualRestoreReassertGate()
        #expect(gate.isArmed == false)
        #expect(gate.consume(injectHref: "ch1.xhtml") == false)
    }

    @Test("recordLanding is a no-op when not armed")
    func recordLandingNoOpWhenUnarmed() {
        let gate = BilingualRestoreReassertGate()
        gate.recordLanding(href: "ch1.xhtml")
        #expect(gate.landingHref == nil)
    }

    @Test("noteRelocate to a DIFFERENT chapter before consume disarms (left the restore chapter)")
    func noteRelocateToDifferentChapterDisarms() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        gate.recordLanding(href: "ch1.xhtml")
        gate.noteRelocate(href: "ch2.xhtml")   // user paged out of the restore chapter
        #expect(gate.isArmed == false)
        // A later RETURN to ch1 must NOT fire a stale re-assert.
        gate.recordLanding(href: "ch1.xhtml")
        #expect(gate.consume(injectHref: "ch1.xhtml") == false)
    }

    @Test("noteRelocate on the SAME landing chapter is a no-op (incl. the re-assert's own relocate)")
    func noteRelocateSameChapterNoOp() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        gate.recordLanding(href: "ch1.xhtml")
        gate.noteRelocate(href: "ch1.xhtml")
        #expect(gate.isArmed == true)
        #expect(gate.consume(injectHref: "ch1.xhtml") == true)
    }

    @Test("noteRelocate is a no-op when not armed or before a landing is recorded")
    func noteRelocateNoOpWhenUnarmedOrNoLanding() {
        let unarmed = BilingualRestoreReassertGate()
        unarmed.noteRelocate(href: "ch2.xhtml")
        #expect(unarmed.isArmed == false)  // stays disarmed, no crash

        let armedNoLanding = BilingualRestoreReassertGate()
        armedNoLanding.arm()
        armedNoLanding.noteRelocate(href: "ch2.xhtml")  // no landing recorded yet
        #expect(armedNoLanding.isArmed == true)         // can't tell it left → stays armed
    }

    @Test("disarm() cancels a pending re-assert (teardown / layout change)")
    func disarmCancels() {
        let gate = BilingualRestoreReassertGate()
        gate.arm()
        gate.recordLanding(href: "ch1.xhtml")
        gate.disarm()
        #expect(gate.consume(injectHref: "ch1.xhtml") == false)
        #expect(gate.landingHref == nil)
    }
}
#endif
