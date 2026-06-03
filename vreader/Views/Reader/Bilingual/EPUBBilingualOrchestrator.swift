// Purpose: Feature #56 WI-10 — host-side orchestrator that joins
// the EPUB WKWebView's `bilingualEnumerate` channel to
// `BilingualReadingViewModel`'s `translationsByUnit` cache and
// emits the inject / clear JS the bridge evaluates.
//
// The container owns one instance per open book. It calls:
//
//   - `enumerateJS()` after each chapter-load `didFinish` (when
//     bilingual is on) to start the enumerate/translate/inject
//     pipeline. The WKWebView posts `[{bid, text}]` back to Swift
//     via the bridge's `bilingualEnumerate` message handler.
//   - `updateBlocks(_:)` with the parsed `[BilingualBlock]`.
//   - `buildInjectJS(translatedSegments:)` once the VM has
//     translations cached for the current unit (`.readerBilingualDidChange`
//     posts when the prefetch lands).
//   - `clearJS()` when bilingual flips off / language changes /
//     chapter changes (chapter swap implicitly re-enumerates).
//
// Key decisions:
// - `@MainActor` so the container can touch it from observers
//   without ceremony.
// - **No SwiftData / network dependency.** The orchestrator never
//   reaches into the VM or the translation service directly; the
//   container passes translations in. This keeps the orchestrator
//   independently testable.
// - **Block state is replace-on-update.** The enumerate JS produces
//   a fresh block list each time it runs (chapter-load, bilingual
//   re-enable); the orchestrator replaces its block array rather
//   than merging. A merge would risk stale `bid`s leaking across
//   chapters.
// - **Per-section block caches (feature #71 WI-7).** Continuous-scroll
//   mode stitches multiple chapter `<section data-vreader-spine-index
//   ="N">` blocks into ONE document. Each section materializes
//   independently and drives its own per-section enumerate. A single
//   `currentBlocks` array would let a re-enumerate of one section
//   clobber another's stamped blocks (cross-section `bid` bleed).
//   Mirroring `FoliateBilingualOrchestrator`, blocks are bucketed by
//   `sectionIndex` so `updateBlocks(_:forSection:)` replaces only one
//   section, and `buildInjectJS(...:forSection:)` injects one
//   section's translations without touching the others. The paged
//   path (one chapter per document, no section tags) buckets under
//   `-1` and reads back through the flattened `currentBlocks`.
//
// @coordinates-with: EPUBBilingualJS.swift, EPUBBilingualPipeline.swift,
//   BilingualReadingViewModel.swift, EPUBReaderContainerView.swift,
//   EPUBReaderContainerView+Bilingual.swift,
//   FoliateBilingualOrchestrator.swift (sibling per-section template),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Foundation
import Observation

/// Host-side orchestrator for EPUB bilingual rendering. One per
/// open book, owned by the EPUB reader container.
@MainActor
@Observable
final class EPUBBilingualOrchestrator {

    /// Per-section block caches keyed by `sectionIndex`. Feature #71
    /// WI-7: continuous-scroll mode stitches multiple chapter sections
    /// into one document, each materializing independently; per-section
    /// storage keeps every stitched section's enumeration available so
    /// a re-enumerate of one section cannot clobber another's stamped
    /// blocks (cross-section `bid` bleed).
    ///
    /// `sectionIndex == -1` is the bucket for untagged payloads (the
    /// paged/global path — one chapter per document) so the legacy
    /// behaviour is preserved.
    private(set) var blocksBySection: [Int: [BilingualBlock]] = [:]

    /// Default initializer — no setup; the container wires inputs
    /// directly via `updateBlocks` / `updateBlocks(_:forSection:)`
    /// and `buildInjectJS`.
    init() {}

    /// Flattened view of every section's enumerated blocks, sorted by
    /// section key (ascending = render order). The paged path keeps
    /// reading this exactly as before — its single chapter buckets
    /// under `-1` and flattens to the same array `updateBlocks(_:)`
    /// stored.
    var currentBlocks: [BilingualBlock] {
        blocksBySection.keys.sorted().flatMap { blocksBySection[$0] ?? [] }
    }

    /// The JS the container evaluates on `didFinish` to start the
    /// enumerate/translate/inject pipeline. The WKWebView posts the
    /// resulting `[{bid, text, sectionIndex}]` back to Swift via the
    /// bridge's `bilingualEnumerate` script-message handler.
    ///
    /// Feature #71 WI-7: `spineIndex` scopes the enumerate to one
    /// stitched chapter section (continuous-scroll mode). `nil`
    /// (default) is the paged/global walk — the original WI-10
    /// behaviour.
    func enumerateJS(spineIndex: Int? = nil) -> String {
        EPUBBilingualJS.bilingualEnumerateJS(spineIndex: spineIndex)
    }

    /// The JS the container evaluates to remove every bilingual
    /// decoration node. Idempotent — safe to run on a chapter
    /// without any decorations.
    ///
    /// Feature #71 WI-7: `spineIndex` scopes the clear to one stitched
    /// chapter section. `nil` (default) clears the whole document —
    /// the safe disable / book-close default.
    func clearJS(spineIndex: Int? = nil) -> String {
        EPUBBilingualJS.bilingualClearJS(spineIndex: spineIndex)
    }

    /// Replaces every section's blocks with the supplied list. Used by
    /// the paged/global path (the JS payload has no per-block
    /// `sectionIndex` tag, so everything buckets under `-1`) and by
    /// tests. The continuous-scroll path uses the partitioning variant
    /// below.
    func updateBlocks(_ blocks: [BilingualBlock]) {
        blocksBySection = Dictionary(grouping: blocks, by: { $0.sectionIndex ?? -1 })
    }

    /// Feature #71 WI-7: replace the enumerated blocks for a specific
    /// stitched section. Other sections' caches are preserved. Used by
    /// the container's `sectionMaterialized` handler so a re-enumerate
    /// of one section cannot clobber an adjacent stitched section's
    /// enumeration.
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

    /// Clear the cached blocks for one stitched section (e.g. after the
    /// section is evicted from the continuous-scroll window). Idempotent.
    func clearBlocks(forSection sectionIndex: Int) {
        blocksBySection[sectionIndex] = nil
    }

    /// Feature #71 WI-7 (Gate-4 round-2): the section keys currently cached,
    /// ascending (render order). The container iterates these to reinject every
    /// MATERIALIZED stitched section whose translation unit just resolved — a
    /// `.readerBilingualDidChange` (prefetch lands) for one section must
    /// reinject only the sections that have blocks, not assume the current
    /// visible locator's section. The paged path's single `-1` bucket appears
    /// here too, so an unscoped caller is unaffected.
    var materializedSections: [Int] {
        blocksBySection.keys.sorted()
    }

    /// Builds inject JS for the current blocks given an ordered
    /// `[String]` of translated segments (the VM's cache for the
    /// current unit). Returns `nil` when there is nothing to inject
    /// — either no enumerate has run yet or no translations are
    /// available.
    ///
    /// A short translation array maps the prefix and leaves the rest
    /// as source-only (silent-source-fallback semantics — plan
    /// Decision 2).
    ///
    /// Feature #71 WI-7: when `sectionIndex` is provided, only that
    /// section's blocks are paired + injected so one stitched
    /// chapter's translation never spills into an adjacent section.
    /// `sectionIndex == nil` keeps the original semantics (the
    /// flattened `currentBlocks`) for the paged path + bulk callers.
    func buildInjectJS(
        translatedSegments: [String]?,
        forSection sectionIndex: Int? = nil
    ) -> String? {
        guard let segments = translatedSegments, !segments.isEmpty else {
            return nil
        }
        let scoped: [BilingualBlock]
        if let sectionIndex {
            scoped = blocksBySection[sectionIndex] ?? []
        } else {
            scoped = currentBlocks
        }
        guard !scoped.isEmpty else { return nil }
        let map = EPUBBilingualPipeline.translationsByBid(
            blocks: scoped,
            translatedSegments: segments
        )
        guard !map.isEmpty else { return nil }
        return EPUBBilingualJS.bilingualInjectJS(
            translationsByBid: map,
            spineIndex: sectionIndex
        )
    }

    /// Feature #77: builds the LOADING-shimmer inject JS for a section's enumerated
    /// bids (section/unit-scoped — all the in-flight unit's bids get the shimmer
    /// until each translation lands and replaces it in place). `sectionIndex == nil`
    /// uses the flattened `currentBlocks` (paged path). Returns `nil` when there are
    /// no enumerated blocks for the scope. The loading-inject JS itself skips any bid
    /// that already has a decoration, so it never downgrades a landed translation.
    func buildLoadingJS(forSection sectionIndex: Int? = nil) -> String? {
        let scoped: [BilingualBlock]
        if let sectionIndex {
            scoped = blocksBySection[sectionIndex] ?? []
        } else {
            scoped = currentBlocks
        }
        guard !scoped.isEmpty else { return nil }
        return EPUBBilingualJS.bilingualInjectLoadingJS(
            loadingBids: scoped.map(\.bid),
            spineIndex: sectionIndex
        )
    }

    /// Feature #77: JS that removes ONLY the loading-shimmer decoration nodes (a
    /// failed / cancelled prefetch), leaving landed translations intact. The
    /// translation-landed path replaces a shimmer in place, so the shimmer must
    /// NOT be removed there — only here, for the no-translation outcome.
    func clearLoadingJS() -> String {
        EPUBBilingualJS.bilingualClearLoadingJS()
    }

    /// Feature #71 WI-7 (Gate-4 round-2 HIGH 2): build ONE inject JS payload
    /// covering MULTIPLE stitched sections at once, pairing each section's
    /// ordered segments against ONLY that section's bids.
    ///
    /// This is the continuous-scroll reinject path. Two problems the
    /// per-section single-payload approach solved would otherwise recur:
    ///   1. **Single-slot overwrite (MEDIUM 1 sibling).** Pushing one
    ///      per-section inject through the bridge's single `pendingHighlightJS`
    ///      slot means a second section's inject overwrites the first before
    ///      the bridge evaluates it. A combined payload injects every section's
    ///      blocks in one eval.
    ///   2. **Cross-section flatten (the HIGH 2 bug).** Pairing the VM's
    ///      per-unit segments against the FLATTENED `currentBlocks`
    ///      (multi-section) would either no-op the Bug #266 1:1 count guard or
    ///      pair section A's segments against section B's blocks. Scoping each
    ///      section's segments to its own bucket keeps the 1:1 pairing per
    ///      section.
    ///
    /// `translationsBySection` maps `sectionIndex → ordered translated
    /// segments` (the VM's cache for that section's unit). A section whose
    /// segment count does not match its block count is dropped (Bug #266
    /// source-only fallback) — the others still inject. Returns `nil` when no
    /// section produced a non-empty 1:1 map.
    func buildInjectJS(translationsBySection: [Int: [String]]) -> String? {
        var combined: [String: String] = [:]
        for sectionIndex in translationsBySection.keys.sorted() {
            guard let segments = translationsBySection[sectionIndex],
                  !segments.isEmpty,
                  let blocks = blocksBySection[sectionIndex], !blocks.isEmpty else {
                continue
            }
            // Per-section 1:1 pairing (Bug #266): a count mismatch yields an
            // empty map for that section → it stays source-only, the rest still
            // inject. Bids are section-namespaced (`s{N}b…`) so the merge across
            // sections cannot collide keys.
            let map = EPUBBilingualPipeline.translationsByBid(
                blocks: blocks, translatedSegments: segments)
            for (bid, translation) in map { combined[bid] = translation }
        }
        guard !combined.isEmpty else { return nil }
        // bids are already globally unique (section-namespaced), so the global
        // bid-keyed inject resolves each block in its own section.
        return EPUBBilingualJS.bilingualInjectJS(translationsByBid: combined)
    }
}
