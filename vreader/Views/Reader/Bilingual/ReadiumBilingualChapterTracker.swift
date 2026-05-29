// Purpose: Feature #42 WI-11b/WI-12 — chapter-change dedup state + pure decision
// logic for the Readium bilingual enumerate/inject loop, split out of
// `ReadiumEPUBHost+Bilingual.swift` for the 300-line budget. A reference type so
// the host's `onLocationChange` closure mutates the live instance rather than a
// stale value snapshot; the static helpers are pure and unit-tested in
// `ReadiumBilingualChapterTrackerTests`.
//
// WI-12 behavior delta (Readium engine, `readiumEPUBEngine` flag ON): Readium
// scroll-mode bilingual enumerates PER-SPINE — one chapter at a time, on
// scroll-into-view (Readium emits `locationDidChange` at spine boundaries in
// scroll mode, which drives the same `handleBilingualLocationChange` enumerate
// the paged path uses). It does NOT reproduce legacy #71's stitched
// cross-chapter continuous bilingual: Readium has no multi-spine-stitch API, so
// off-screen spines enumerate only when scrolled into view, not eagerly across
// the whole book. Legacy #71 (EPUBWebViewBridge, `readiumEPUBEngine` flag OFF)
// is unaffected and keeps its full continuous-scroll bilingual. A paged↔scroll
// layout change re-renders the spine (stale `data-vreader-bid` stamps +
// decorations are discarded), so the layout-change handler RE-ENUMERATES the
// current spine in BOTH directions.
//
// @coordinates-with: ReadiumEPUBHost+Bilingual.swift,
//   ReadiumEPUBHost+BilingualDriver.swift, EPUBLayoutPreference.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11/WI-12)

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

    /// Gate-4 (WI-12 audit) Finding 1: monotonically-increasing token that
    /// disambiguates concurrent in-flight enumerates. In scroll mode rapid spine
    /// changes leave multiple `await enumerate()` tasks in flight at once; without
    /// this guard a chapter-1 enumerate completing AFTER chapter-2 was scheduled
    /// would overwrite the shared single-bucket orchestrator and inject chapter-1's
    /// bid→translation pairs into the now-visible chapter-2 (stale cross-spine
    /// injection). The driver captures `currentGeneration` SYNCHRONOUSLY at schedule
    /// time and, after the `await` returns, discards the result if the captured
    /// value no longer matches (`isCurrentGeneration(_:) == false`). This composes
    /// with — but is separate from — the `lastEnumeratedHref` dedupe: the href
    /// dedupe prevents DOUBLE-SCHEDULING the same chapter; the generation token
    /// DISCARDS STALE RESULTS of superseded schedules. The token bumps only when a
    /// NEW enumerate is actually scheduled (a `shouldEnumerate` that returns true)
    /// or on a `reset()`; a deduped same-href trigger does NOT bump it, so a
    /// legitimate retry is never blocked.
    private(set) var currentGeneration: Int = 0
    init() {}

    /// Bumps + returns the next generation. Called whenever a fresh enumerate is
    /// scheduled (a superseding event for any older in-flight task).
    @discardableResult
    func nextGeneration() -> Int {
        currentGeneration += 1
        return currentGeneration
    }

    /// Whether `generation` (captured at an enumerate's schedule time) is still the
    /// latest — i.e. no superseding enumerate / reset has happened since. A stale
    /// result (an older spine's enumerate completing after a newer spine was
    /// scheduled) returns false and is discarded by the driver.
    func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == currentGeneration
    }

    /// MED-3: synchronous dedupe gate. Returns whether an enumerate should run for
    /// `href` and, when it should, records the href immediately so a duplicate
    /// organic trigger arriving before the async enumerate completes is deduped.
    /// A `force` enumerate (the toggle/confirm path, where the user just enabled
    /// bilingual on the chapter they were already reading) bypasses the dedupe and
    /// still records the in-flight href. Finding 1: a schedule that actually runs
    /// (returns true) ALSO bumps the generation so any older in-flight enumerate
    /// for a different spine is superseded; a deduped (returns false) trigger does
    /// NOT bump, so a legitimate retry of the same chapter is never invalidated.
    @discardableResult
    func shouldEnumerate(forHref href: String?, force: Bool) -> Bool {
        if !force, let href, href == lastEnumeratedHref { return false }
        lastEnumeratedHref = href
        nextGeneration()
        return true
    }

    /// Records the href an enumerate actually ran for (the resolved spine href),
    /// keeping the dedupe key consistent after the async enumerate returns.
    func markEnumerated(href: String?) {
        if let href { lastEnumeratedHref = href }
    }

    /// Clears the dedupe state so the next location change re-enumerates (disable
    /// + the prefetch-disabled path). Finding 1: also bumps the generation so any
    /// enumerate that was in flight before a layout-change reset / disable has its
    /// captured generation invalidated and its (now-stale) result discarded.
    func reset() {
        lastEnumeratedHref = nil
        nextGeneration()
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

    /// WI-12: bilingual is now supported in BOTH `.paged` and `.scroll`. Readium
    /// scroll mode enumerates per-spine on scroll-into-view (the orchestrator's
    /// single-bucket paged block model holds for one spine at a time), so the
    /// enumerate/inject path is no longer paged-gated. (Was paged-only in WI-11.)
    /// Retained as the single source of truth for "can the engine do bilingual in
    /// this layout" so the driver guards read intent, not a bare literal.
    nonisolated static func isBilingualSupported(forLayout layout: EPUBLayoutPreference) -> Bool {
        layout == .paged || layout == .scroll
    }

    /// WI-12: pure decision for an `epubLayout` change while bilingual is enabled.
    /// A paged↔scroll switch re-renders the spine in Readium (the old
    /// `data-vreader-bid` stamps + injected decorations are gone), so a fresh
    /// enumerate of the current spine is required in BOTH directions. The host's
    /// `.reEnumerate` handler clears any stale decorations before re-enumerating
    /// (defensive — the new-layout DOM is fresh). Disabled → no-op.
    ///
    /// Gate-4 (WI-12 audit) Finding 2: `newLayout` is now load-bearing — it FAILS
    /// CLOSED. A layout the engine cannot do bilingual in (a future
    /// `EPUBLayoutPreference` case) returns `.none` even when enabled, rather than
    /// re-enumerating into an unsupported layout. Both current cases
    /// (`.paged`/`.scroll`) are supported, so today this returns `.reEnumerate`
    /// when enabled — but a new case defaults to safe.
    nonisolated static func layoutChangeAction(
        newLayout: EPUBLayoutPreference, isEnabled: Bool
    ) -> BilingualLayoutChangeAction {
        guard isEnabled, isBilingualSupported(forLayout: newLayout) else { return .none }
        return .reEnumerate
    }

    /// Gate-4 round-3 MED (Finding B): pure decision for the More-menu enable
    /// toggle. First-enable confirmation must ALWAYS precede enumeration, so a
    /// first enable (`needsSetupSheet`) PRESENTS the layout-independent setup sheet.
    /// WI-12: an already-configured re-enable ENUMERATES in BOTH layouts (per-spine
    /// bilingual is now supported in scroll too — no more scroll `.clearOnly`).
    nonisolated static func enableToggleAction(needsSetupSheet: Bool) -> BilingualEnableAction {
        needsSetupSheet ? .presentSetup : .enumerate
    }

    /// Gate-4 round-3 MED (Finding B): the `.reEnumerate` (layout-change) path
    /// must NEVER enumerate while the first-enable setup sheet is still pending —
    /// that would prefetch/inject under the DEFAULT language/granularity, skipping
    /// confirmation. The sheet is already showing (raised at enable time); the
    /// enumerate happens after confirm.
    nonisolated static func reEnumerateAllowed(needsSetupSheet: Bool) -> Bool {
        !needsSetupSheet
    }
}

/// WI-12: the action the host takes when `epubLayout` changes while bilingual is
/// enabled. Pure value so the decision is unit-testable apart from the SwiftUI
/// `.onChange` plumbing.
enum BilingualLayoutChangeAction: Equatable {
    /// Enabled: re-enumerate the current spine so translation reappears in the
    /// re-rendered (paged↔scroll) layout. The host clears stale decorations first.
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
    /// Re-enable, already configured: enumerate the current spine (both layouts).
    case enumerate
}
#endif
