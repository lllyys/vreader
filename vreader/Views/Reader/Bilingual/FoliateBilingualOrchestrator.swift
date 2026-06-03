// Purpose: Feature #56 WI-11 — host-side orchestrator that joins
// the Foliate WKWebView's `bilingualEnumerate` channel to
// `BilingualReadingViewModel`'s `translationsByUnit` cache and
// emits the inject / clear JS the spike's pending-JS seam
// evaluates.
//
// Mirror of `EPUBBilingualOrchestrator` for the AZW3/MOBI live
// path. The container owns one instance per open book. It calls:
//
//   - `enumerateJS()` after each section load (when bilingual is
//     on) to start the enumerate/translate/inject pipeline. The
//     WKWebView posts `[{bid, text}]` back to Swift via the spike's
//     `bilingualEnumerate` message handler.
//   - `updateBlocks(_:)` with the parsed `[BilingualBlock]`.
//   - `buildInjectJS(translatedSegments:)` once the VM has
//     translations cached for the current unit
//     (`.readerBilingualDidChange` posts when the prefetch lands).
//   - `clearJS()` when bilingual flips off / language changes /
//     unit changes.
//
// Key decisions:
// - `@MainActor` so the container can touch it from observers
//   without ceremony.
// - **No SwiftData / network dependency.** The orchestrator never
//   reaches into the VM or the translation service directly; the
//   container passes translations in. This keeps the orchestrator
//   independently testable.
// - **Block state is replace-on-update.** The enumerate JS produces
//   a fresh block list each time it runs (section-load, bilingual
//   re-enable); the orchestrator replaces its block array rather
//   than merging.
//
// @coordinates-with: FoliateBilingualJS.swift,
//   FoliateBilingualPipeline.swift, BilingualReadingViewModel.swift,
//   FoliateSpikeView.swift, FoliateSpikeView+Bilingual.swift,
//   EPUBBilingualOrchestrator.swift (sibling renderer),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import Foundation
import Observation

/// Host-side orchestrator for AZW3/MOBI bilingual rendering. One
/// per open book, owned by the Foliate spike host.
@MainActor
@Observable
final class FoliateBilingualOrchestrator {

    /// Per-section block caches keyed by `sectionIndex`. Gate-4
    /// round-2 audit fix: in paginated mode, foliate-js preloads
    /// adjacent sections — `section-load` can fire for an
    /// off-screen section before the user relocates there. A single
    /// `currentBlocks` field would let the preload clobber the
    /// active section's stamped block list. Per-section storage
    /// keeps every loaded section's enumeration available, so the
    /// container can inject against any of them when its translation
    /// cache lands.
    ///
    /// `sectionIndex == -1` is used as the bucket for untagged
    /// payloads (older bundles) to preserve legacy behaviour.
    private(set) var blocksBySection: [Int: [BilingualBlock]] = [:]

    /// Default initializer — no setup; the container wires inputs
    /// directly via `updateBlocks(_:)` / `updateBlocks(_:forSection:)`
    /// and `buildInjectJS`.
    init() {}

    /// Flattened view of every section's enumerated blocks. Used by
    /// the orchestrator tests + the bulk inject paths that don't
    /// scope by section.
    var currentBlocks: [BilingualBlock] {
        // Preserve insertion order: section keys are integers; the
        // JS enumerate walks contents in render order so iterating
        // sorted ascending matches the user-visible flow.
        blocksBySection.keys.sorted().flatMap { blocksBySection[$0] ?? [] }
    }

    /// The JS the container evaluates on section load to start the
    /// enumerate/translate/inject pipeline. The WKWebView posts the
    /// resulting `[{bid, text, sectionIndex}]` back to Swift via the
    /// spike's `bilingualEnumerate` script-message handler.
    ///
    /// Gate-4 audit finding H2: pass
    /// `sectionIndex` to scope the enumerate to one section's DOM.
    /// `nil` (default) walks every loaded section — the original
    /// WI-11 r0 behaviour, kept for the JS-source-string pin tests
    /// and for the on-disable bulk clear path.
    func enumerateJS(sectionIndex: Int? = nil) -> String {
        FoliateBilingualJS.bilingualEnumerateJS(
            targetSectionIndex: sectionIndex)
    }

    /// The JS the container evaluates to remove bilingual decoration
    /// nodes. Idempotent — safe to run on a section without any
    /// decorations. `sectionIndex == nil` clears every loaded
    /// section (the safe disable / book-close default).
    func clearJS(sectionIndex: Int? = nil) -> String {
        FoliateBilingualJS.bilingualClearJS(
            targetSectionIndex: sectionIndex)
    }

    /// Replaces every section's blocks with the supplied list. Used
    /// by tests and by the legacy-bundle path where the JS payload
    /// has no per-block `sectionIndex` tag (we then bucket
    /// everything under `-1`). Production code uses the partitioning
    /// variant below.
    func updateBlocks(_ blocks: [BilingualBlock]) {
        blocksBySection = Dictionary(grouping: blocks, by: { $0.sectionIndex ?? -1 })
    }

    /// Gate-4 round-2 audit fix: replace the
    /// enumerated blocks for a specific section. Other sections'
    /// caches are preserved. Used by the container's
    /// `section-load` handler so an adjacent preloaded section
    /// cannot clobber the active section's enumeration.
    func updateBlocks(
        _ blocks: [BilingualBlock], forSection sectionIndex: Int
    ) {
        // Drop empty bucketing so `blocksBySection[sectionIndex]` is
        // either present-and-non-empty or absent.
        if blocks.isEmpty {
            blocksBySection[sectionIndex] = nil
        } else {
            blocksBySection[sectionIndex] = blocks
        }
    }

    /// Clear the cached blocks for one section (e.g. after the
    /// section is unloaded). Idempotent.
    func clearBlocks(forSection sectionIndex: Int) {
        blocksBySection[sectionIndex] = nil
    }

    /// Builds inject JS for the current blocks given an ordered
    /// `[String]` of translated segments (the VM's cache for the
    /// current unit). Returns `nil` when there is nothing to inject
    /// — either no enumerate has run yet or no translations are
    /// available.
    ///
    /// Gate-4 audit finding H2: when `sectionIndex`
    /// is provided, blocks are scoped via
    /// `FoliateBilingualPipeline.blocks(_:forSection:)` so a unit's
    /// translation never spills into an adjacent section that
    /// happens to be loaded at the same time (paginated mode).
    /// `sectionIndex == nil` keeps the original semantics for the
    /// callers that don't track section identity.
    ///
    /// A short translation array maps the prefix and leaves the rest
    /// as source-only (silent-source-fallback semantics — plan
    /// Decision 2).
    func buildInjectJS(
        translatedSegments: [String]?,
        sectionIndex: Int? = nil
    ) -> String? {
        guard let segments = translatedSegments, !segments.isEmpty else {
            return nil
        }
        let scoped: [BilingualBlock]
        if let sectionIndex {
            // Prefer the per-section cache; fall back to the
            // legacy `-1` bucket (older bundle, untagged blocks).
            scoped = blocksBySection[sectionIndex]
                ?? blocksBySection[-1]
                ?? []
        } else {
            scoped = currentBlocks
        }
        guard !scoped.isEmpty else { return nil }
        let map = FoliateBilingualPipeline.translationsByBid(
            blocks: scoped,
            translatedSegments: segments
        )
        guard !map.isEmpty else { return nil }
        return FoliateBilingualJS.bilingualInjectJS(
            translationsByBid: map,
            targetSectionIndex: sectionIndex
        )
    }

    // MARK: - loading shimmer (Feature #77 WI-3)

    /// Feature #77: build the LOADING-shimmer inject JS for a section's enumerated
    /// bids (the in-flight unit's blocks get a shimmer until each translation
    /// lands and replaces it in place). `sectionIndex == nil` uses the flattened
    /// `currentBlocks`. Returns `nil` when the scope has no blocks. The host's
    /// `bilingualInjectLoading` skips any bid that already has a decoration, so it
    /// never downgrades a landed translation. Mirrors `buildInjectJS`'s scoping
    /// (per-section cache → legacy `-1` bucket fallback).
    func buildLoadingJS(sectionIndex: Int? = nil) -> String? {
        let scoped: [BilingualBlock]
        if let sectionIndex {
            scoped = blocksBySection[sectionIndex]
                ?? blocksBySection[-1]
                ?? []
        } else {
            scoped = currentBlocks
        }
        guard !scoped.isEmpty else { return nil }
        return FoliateBilingualJS.bilingualInjectLoadingJS(
            loadingBids: scoped.map(\.bid),
            targetSectionIndex: sectionIndex
        )
    }

    /// Feature #77: JS that removes ONLY the loading-shimmer decorations (a
    /// failed / cancelled prefetch), leaving landed translations intact.
    func clearLoadingJS(sectionIndex: Int? = nil) -> String {
        FoliateBilingualJS.bilingualClearLoadingJS(targetSectionIndex: sectionIndex)
    }

}
#endif
