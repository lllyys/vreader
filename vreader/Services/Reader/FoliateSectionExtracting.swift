// Purpose: Feature #56 WI-11 — `@MainActor`-isolated facade for the
// live Foliate per-section text extraction seam. Bridges
// `FoliateSpikeView.Coordinator` (`@MainActor`-isolated WKWebView
// access) into the `Sendable` `ChapterTextProviding` adapter.
//
// The plan's Gate-2 round-2 finding N2 + round-3 follow-up: the
// `FoliateChapterTextProvider` cannot store an unconstrained
// existential `any FoliateSectionExtracting` and still be
// `Sendable`, because `WKWebView` access is main-actor isolated.
// Declaring the protocol `@MainActor` + `AnyObject` + `Sendable`
// makes a `@MainActor`-isolated `AnyObject` existential safely
// `Sendable` — its members run on the main actor, which is itself
// a Sendable executor. The provider is an `actor` (not a `struct`),
// so it satisfies `ChapterTextProviding: Sendable` by construction
// and reaches the facade via `await`.
//
// Key decisions:
// - **`@MainActor protocol`, not free functions.** The facade is a
//   class-bound existential so the actor holds a single
//   `any FoliateSectionExtracting` reference (the live
//   `FoliateSpikeView.Coordinator`), not a value copy.
// - **`AnyObject + Sendable`.** A class-bound, `@MainActor`-pinned
//   reference is the safest cross-actor handle: the executor is the
//   main actor, members are main-actor-isolated, so a hop in is the
//   only access. No `nonisolated(unsafe)` needed.
// - **Methods are `@MainActor func ... async`.** The `async` is
//   needed for the WKWebView `callAsyncJavaScript` walk and lets
//   non-main callers `await` without a static-isolation conflict.
// - **No throws.** A `nil` / empty extraction is the right failure
//   mode — translation is a non-critical decoration; throwing here
//   would force every caller into a do/catch for a degraded case.
//
// @coordinates-with: FoliateChapterTextProvider.swift,
//   FoliateSpikeView.swift (the live concrete adapter implements
//     this protocol in an extension on `Coordinator`),
//   TranslationUnitID.swift,
//   ChapterTextProviding.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Foundation

/// Main-actor-isolated facade over the Foliate live per-section
/// text extraction seam. The single concrete implementation is an
/// extension on `FoliateSpikeView.Coordinator`; tests use the
/// in-memory `MockExtractor` (see
/// `FoliateChapterTextProviderTests`).
@MainActor
protocol FoliateSectionExtracting: AnyObject, Sendable {

    /// Ordered list of translation-unit ids for the open book, one
    /// per Foliate section. Returns `[]` if the book hasn't rendered
    /// yet or has no sections.
    func extractSections() async -> [TranslationUnitID]

    /// Plain-text content of one Foliate section. Returns `""` if
    /// the section can't be extracted (renderer gone, section
    /// removed, etc.).
    func extractSectionText(_ unit: TranslationUnitID) async -> String
}
