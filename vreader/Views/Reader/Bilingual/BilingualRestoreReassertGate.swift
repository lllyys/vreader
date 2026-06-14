// Purpose: Bug #352 — a one-shot latch that makes the Readium host
// re-assert the saved reading position AFTER the first bilingual inject on
// the restore-landing spine.
//
// Why: with bilingual ON, the navigator restores to the saved
// (fraction-based) progression against the SOURCE-ONLY spine and fixes the
// page there; the bilingual inject then adds interlinear rows that grow
// the spine content under the just-restored page, so the held page shows
// EARLIER content (the user lands backward — observed: a deep-in-chapter
// position reopens at the chapter start). Re-navigating to the saved
// locator AFTER the inject makes Readium re-resolve the fraction against
// the now-injected DOM, landing at the correct reading content.
//
// The latch fires EXACTLY once AND only for the restore-landing spine's
// inject (matched by href) — so neither a later chapter's inject nor an
// inject on a spine the user scrolled to before the restore spine injected
// can yank the reader back to the restore target.
//
// @coordinates-with: ReadiumEPUBHost.swift (host state),
//   ReadiumEPUBHost+Body.swift (arm at open),
//   ReadiumEPUBHost+BilingualDriver.swift (record href + consume after inject)

#if canImport(UIKit)
import Foundation

/// One-shot, href-guarded latch for the bug-#352 post-inject position re-assert.
@MainActor
final class BilingualRestoreReassertGate {

    private var armed = false
    /// The restore-landing spine's normalized href, recorded on the first
    /// relocate after arming. `nil` while armed-but-not-yet-landed.
    private(set) var landingHref: String?

    /// Arm the latch: a saved position needs re-asserting after the
    /// restore-landing spine's first bilingual inject. Called at open when a
    /// restore target exists.
    func arm() { armed = true }

    /// Record the spine the restore landed on, the FIRST relocate after
    /// arming. Later relocates do not overwrite it (only the landing spine's
    /// inject should re-assert). No-op when not armed.
    func recordLanding(href: String?) {
        guard armed, landingHref == nil else { return }
        landingHref = href
    }

    /// Cancel a pending re-assert (teardown, or a layout change that
    /// re-renders + re-positions the spine itself).
    func disarm() {
        armed = false
        landingHref = nil
    }

    /// Codex round-4: if a relocate moves to a DIFFERENT chapter than the
    /// recorded landing BEFORE the restore inject consumes the gate, the
    /// restore moment is gone — disarm so a later RETURN to the landing
    /// chapter can't consume a stale gate. No-op when not armed, no landing
    /// recorded yet, or the relocate is still on the landing chapter (incl.
    /// the re-assert's own same-href relocate).
    func noteRelocate(href: String?) {
        guard armed, let landingHref, let href, href != landingHref else { return }
        disarm()
    }

    /// Returns `true` exactly once — when armed AND `injectHref` matches the
    /// recorded restore-landing spine (or no landing href was recorded yet,
    /// the defensive same-relocate case) — then disarms. Otherwise `false`.
    func consume(injectHref: String) -> Bool {
        guard armed else { return false }
        if let landingHref, landingHref != injectHref { return false }
        armed = false
        landingHref = nil
        return true
    }

    /// Whether a re-assert is currently pending.
    var isArmed: Bool { armed }
}
#endif
