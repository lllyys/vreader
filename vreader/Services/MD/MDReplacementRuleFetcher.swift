// Purpose: Fetches the content replacement rules that apply to a Markdown
// book and maps them to the persistence-free `ReplacementRuleDescriptor`
// the MD render pipeline consumes (feature #54 WI-7).
//
// Key decisions:
// - Pure enum namespace — no state, no MainActor. Callable from a view's
//   `.task` and from tests with an in-memory ModelContainer.
// - The `enabled` + global-or-book-scope filter runs in the SwiftData
//   `FetchDescriptor` predicate, so an MD open fetches only the applicable
//   rows rather than scanning the full rule table.
// - The SwiftData fetch runs on a detached task with its own ModelContext:
//   `ContentReplacementRule` is a context-bound `@Model` and not Sendable,
//   so only the value-type `ReplacementRuleDescriptor` array crosses back.
//
// @coordinates-with: ContentReplacementRule.swift, ReplacementTransform.swift,
//   MDReaderContainerView.swift, MDFileLoader.swift

import Foundation
import SwiftData

/// Loads the content replacement rules applicable to one Markdown book.
enum MDReplacementRuleFetcher {

    /// Fetches the enabled `ContentReplacementRule` rows that apply to the
    /// book identified by `bookKey` — global rules (empty `scopeKey`) plus
    /// rules scoped to that exact fingerprint key — sorted by `order`, and
    /// maps them to `ReplacementRuleDescriptor`.
    ///
    /// Returns `[]` when `container` is nil (an identity passthrough in
    /// `MDFileLoader.load`).
    static func rules(
        container: ModelContainer?,
        bookKey: String
    ) async -> [ReplacementRuleDescriptor] {
        guard let container else { return [] }
        return await Task.detached {
            let ctx = ModelContext(container)
            return descriptors(context: ctx, bookKey: bookKey)
        }.value
    }

    /// Synchronous core: runs the scoped fetch against an already-built
    /// `ModelContext` and maps the rows. Separated from `rules(container:
    /// bookKey:)` so tests can drive it directly with an in-memory context
    /// without a detached-task hop.
    static func descriptors(
        context: ModelContext,
        bookKey: String
    ) -> [ReplacementRuleDescriptor] {
        // Filter at the store: enabled rows whose scope is global
        // (`scopeKey` empty) or this exact book. The `order` sort keeps the
        // returned list ordered; `ReplacementTransform` also sorts by
        // `order` defensively.
        //
        // The global check compares `scopeKey == ""` rather than
        // `scopeKey.isEmpty`: SwiftData's `#Predicate` does not reliably
        // translate `String.isEmpty` to the backing store query (it
        // silently matched nothing), so an explicit empty-string compare
        // is used.
        let emptyScope = ""
        let descriptor = FetchDescriptor<ContentReplacementRule>(
            predicate: #Predicate { rule in
                rule.enabled && (rule.scopeKey == emptyScope || rule.scopeKey == bookKey)
            },
            sortBy: [SortDescriptor(\.order)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map {
            ReplacementRuleDescriptor(
                pattern: $0.pattern,
                replacement: $0.replacement,
                isRegex: $0.isRegex,
                enabled: $0.enabled,
                order: $0.order
            )
        }
    }
}
