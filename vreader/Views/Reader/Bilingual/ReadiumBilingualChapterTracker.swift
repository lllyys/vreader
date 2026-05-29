// Purpose: Feature #42 WI-11b — chapter-change dedup state + pure decision logic
// for the Readium bilingual enumerate/inject loop, split out of
// `ReadiumEPUBHost+Bilingual.swift` for the 300-line budget. A reference type so
// the host's `onLocationChange` closure mutates the live instance rather than a
// stale value snapshot; the static helpers are pure and unit-tested in
// `ReadiumBilingualChapterTrackerTests`.
//
// @coordinates-with: ReadiumEPUBHost+Bilingual.swift,
//   ReadiumEPUBHost+BilingualDriver.swift, EPUBLayoutPreference.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import Foundation

/// Reference-type chapter-change dedup + pure decision logic for the Readium
/// bilingual loop. A class (not a value `@State`) so the `onLocationChange`
/// closure — captured at body-eval — mutates the live instance rather than a
/// stale value snapshot. The static helpers are pure (unit-tested in
/// `ReadiumBilingualChapterTrackerTests`).
@MainActor
final class ReadiumBilingualChapterTracker {
    /// The spine href the bilingual loop last enumerated (or has IN FLIGHT). `nil`
    /// until the first enumerate. An intra-chapter location change (same href) is
    /// deduped. Gate-4 MED-3: this is written SYNCHRONOUSLY in `shouldEnumerate`
    /// BEFORE the async enumerate launches, so a repeated `locationDidChange` for
    /// the same href before the eval completes does not schedule a second run.
    private(set) var lastEnumeratedHref: String?
    init() {}

    /// MED-3: synchronous dedupe gate. Returns whether an enumerate should run for
    /// `href` and, when it should, records the href immediately so a duplicate
    /// organic trigger arriving before the async enumerate completes is deduped.
    /// A `force` enumerate (the toggle/confirm path, where the user just enabled
    /// bilingual on the chapter they were already reading) bypasses the dedupe and
    /// still records the in-flight href.
    @discardableResult
    func shouldEnumerate(forHref href: String?, force: Bool) -> Bool {
        if !force, let href, href == lastEnumeratedHref { return false }
        lastEnumeratedHref = href
        return true
    }

    /// Records the href an enumerate actually ran for (the resolved spine href),
    /// keeping the dedupe key consistent after the async enumerate returns.
    func markEnumerated(href: String?) {
        if let href { lastEnumeratedHref = href }
    }

    /// Clears the dedupe state so the next location change re-enumerates (disable
    /// + the prefetch-disabled path).
    func reset() {
        lastEnumeratedHref = nil
    }

    /// Gate-4 round-3 MED-2: reverts the in-flight mark recorded by
    /// `shouldEnumerate` when that href's enumerate FAILED (eval returned nil), so
    /// a later `locationDidChange` for the same chapter retries instead of being
    /// permanently deduped (the chapter would otherwise stay blank forever). Only
    /// reverts when the current in-flight href still matches — a newer chapter that
    /// already moved on (its own enumerate legitimately in flight) is left intact.
    func clearInFlight(href: String?) {
        if lastEnumeratedHref == href {
            lastEnumeratedHref = nil
        }
    }

    /// HIGH-1: resolve the visible-chapter href for the bilingual unit lookup.
    /// Prefers the supplied Readium locator href, then the host's last-known
    /// locator href (the toggle/confirm first-enable path), then the
    /// last-enumerated href (a prefetch-landed inject that carries no locator).
    /// Never resets the only available source before reading it.
    nonisolated static func selectedHref(
        supplied: String?, lastKnown: String?, lastEnumerated: String?
    ) -> String? {
        supplied ?? lastKnown ?? lastEnumerated
    }

    /// MED-4: PAGED-only gate. Continuous-scroll bilingual is WI-12, so the
    /// enumerate/inject path no-ops in `.scroll` (the paged single-spine block
    /// assumptions do not hold there).
    nonisolated static func isBilingualSupported(forLayout layout: EPUBLayoutPreference) -> Bool {
        layout == .paged
    }

    /// Gate-4 round-3 MED-3: pure decision for an `epubLayout` change while
    /// bilingual is enabled. Enumerate is paged-gated, so paged→scroll must CLEAR
    /// the injected decorations + reset the tracker (else stale nodes linger), and
    /// scroll→paged must RE-ENUMERATE so translation reappears. Disabled → no-op.
    nonisolated static func layoutChangeAction(
        newLayout: EPUBLayoutPreference, isEnabled: Bool
    ) -> BilingualLayoutChangeAction {
        guard isEnabled else { return .none }
        return isBilingualSupported(forLayout: newLayout) ? .reEnumerate : .clearAndReset
    }

    /// Gate-4 round-3 MED (Finding B): pure decision for the More-menu enable
    /// toggle. First-enable confirmation must ALWAYS precede enumeration, so a
    /// first enable (`needsSetupSheet`) PRESENTS the setup sheet regardless of the
    /// layout (the sheet is layout-independent; only the enumerate is paged-gated).
    /// An already-configured re-enable ENUMERATES in paged, or just CLEARS in
    /// scroll (paged-gated, no enumerate).
    nonisolated static func enableToggleAction(
        needsSetupSheet: Bool, layoutSupported: Bool
    ) -> BilingualEnableAction {
        if needsSetupSheet { return .presentSetup }
        return layoutSupported ? .enumerate : .clearOnly
    }

    /// Gate-4 round-3 MED (Finding B): the `.reEnumerate` (return-to-paged) path
    /// must NEVER enumerate while the first-enable setup sheet is still pending —
    /// that would prefetch/inject under the DEFAULT language/granularity, skipping
    /// confirmation. The sheet is already showing (raised at enable time); the
    /// enumerate happens after confirm.
    nonisolated static func reEnumerateAllowed(needsSetupSheet: Bool) -> Bool {
        !needsSetupSheet
    }

    /// Gate-4 round-3 MED (Finding B): pure decision for the setup-sheet confirm.
    /// After the user confirms language/granularity, run the first enumerate ONLY
    /// when the layout is paged; in scroll, confirm just commits + dismisses and
    /// the enumerate is deferred to the return-to-paged `.reEnumerate` path (now
    /// allowed because `needsSetupSheet` is cleared post-confirm).
    nonisolated static func confirmAction(layoutSupported: Bool) -> BilingualConfirmAction {
        layoutSupported ? .enumerate : .commitOnly
    }
}

/// Gate-4 round-3 MED-3: the action the host takes when `epubLayout` changes while
/// bilingual is enabled. Pure value so the decision is unit-testable apart from the
/// SwiftUI `.onChange` plumbing.
enum BilingualLayoutChangeAction: Equatable {
    /// Leaving paged: clear injected decorations + reset the chapter tracker.
    case clearAndReset
    /// Returning to paged: re-enumerate the current chapter so translation returns.
    case reEnumerate
    /// Disabled, or no observable change — do nothing.
    case none
}

/// Gate-4 round-3 MED (Finding B): the action the host takes for a More-menu
/// enable toggle. Pure value so first-enable-confirmation-before-enumerate is
/// unit-testable apart from the SwiftUI plumbing.
enum BilingualEnableAction: Equatable {
    /// First enable: raise the setup sheet (layout-independent) — do NOT enumerate.
    case presentSetup
    /// Re-enable, already configured, paged: enumerate the current chapter.
    case enumerate
    /// Re-enable, already configured, scroll: clear only (enumerate is paged-gated).
    case clearOnly
}

/// Gate-4 round-3 MED (Finding B): the action the host takes after the user
/// confirms the first-enable setup sheet. Enumerate only in paged; in scroll the
/// settings commit and enumerate defers to the return-to-paged path.
enum BilingualConfirmAction: Equatable {
    /// Paged: run the first enumerate under the chosen settings.
    case enumerate
    /// Scroll: commit settings + dismiss; enumerate deferred to return-to-paged.
    case commitOnly
}
#endif
