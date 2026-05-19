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
//
// @coordinates-with: EPUBBilingualJS.swift, EPUBBilingualPipeline.swift,
//   BilingualReadingViewModel.swift, EPUBReaderContainerView.swift,
//   EPUBReaderContainerView+Bilingual.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Foundation
import Observation

/// Host-side orchestrator for EPUB bilingual rendering. One per
/// open book, owned by the EPUB reader container.
@MainActor
@Observable
final class EPUBBilingualOrchestrator {

    /// The current chapter's enumerated blocks (last `updateBlocks`
    /// call). Empty before the first enumerate runs.
    private(set) var currentBlocks: [BilingualBlock] = []

    /// Default initializer — no setup; the container wires inputs
    /// directly via `updateBlocks` and `buildInjectJS`.
    init() {}

    /// The JS the container evaluates on `didFinish` to start the
    /// enumerate/translate/inject pipeline. The WKWebView posts the
    /// resulting `[{bid, text}]` back to Swift via the bridge's
    /// `bilingualEnumerate` script-message handler.
    func enumerateJS() -> String {
        EPUBBilingualJS.bilingualEnumerateJS()
    }

    /// The JS the container evaluates to remove every bilingual
    /// decoration node. Idempotent — safe to run on a chapter
    /// without any decorations.
    func clearJS() -> String {
        EPUBBilingualJS.bilingualClearJS()
    }

    /// Replaces the current chapter's enumerated blocks. Called from
    /// the `onBilingualEnumerate` callback after parsing the JS
    /// payload. A chapter swap re-enumerates and replaces.
    func updateBlocks(_ blocks: [BilingualBlock]) {
        currentBlocks = blocks
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
    func buildInjectJS(translatedSegments: [String]?) -> String? {
        guard !currentBlocks.isEmpty else { return nil }
        guard let segments = translatedSegments, !segments.isEmpty else {
            return nil
        }
        let map = EPUBBilingualPipeline.translationsByBid(
            blocks: currentBlocks,
            translatedSegments: segments
        )
        guard !map.isEmpty else { return nil }
        return EPUBBilingualJS.bilingualInjectJS(translationsByBid: map)
    }
}
