// Purpose: The boundary protocol + UTF-16 budget constant for AI
// context extraction. Extracted from AIContextExtractor (feature #69)
// so AIAssistantViewModel can depend on the seam without pulling in the
// concrete struct, and so the extractor file stays small.
//
// Key decisions:
// - AIContextBudget.defaultMaxUTF16 is a named constant, NOT a Swift
//   default argument on the protocol requirement: a protocol-requirement
//   default argument is not visible through `any AIContextExtracting`.
// - The protocol requirement takes maxUTF16 with NO default; a
//   protocol-EXTENSION convenience overload (which IS dispatched through
//   the existential) supplies the default budget.
//
// @coordinates-with: AIContextExtractor.swift, AIAssistantViewModel.swift,
//   SummaryScope.swift, ChapterBounds.swift

import Foundation

/// The default UTF-16 context budget for scoped extraction.
///
/// A named constant rather than a Swift default argument on the
/// `AIContextExtracting` protocol requirement: a protocol-requirement
/// default argument is NOT visible through an existential
/// (`any AIContextExtracting`), so callers that go through the
/// existential supply this constant — either via the protocol-extension
/// convenience overload or by passing it explicitly.
enum AIContextBudget {
    /// ~12 000 UTF-16 units. Conservative ceiling for a single AI request;
    /// the provider still returns a clean error if the model rejects it.
    static let defaultMaxUTF16 = 12_000
}

/// A seam for the AI context extractor so `AIAssistantViewModel` can
/// depend on the boundary protocol rather than the concrete struct
/// (the codebase's standard boundary-protocol move — `LibraryPersisting`,
/// `BookImporting`). `Sendable`, so `any AIContextExtracting` is
/// `Sendable` and a `@MainActor` view model can hold it cleanly.
protocol AIContextExtracting: Sendable {
    /// The single required entry point. `maxUTF16` is REQUIRED here
    /// (no default argument) — a protocol-requirement default argument
    /// does not survive through `any AIContextExtracting`.
    func extractContext(
        locator: Locator,
        fullText: String,
        format: BookFormat,
        scope: SummaryScope,
        chapterBounds: ChapterBounds?,
        maxUTF16: Int
    ) -> String
}

extension AIContextExtracting {
    /// Convenience overload supplying `AIContextBudget.defaultMaxUTF16`.
    /// A protocol-EXTENSION method IS dispatched through the existential,
    /// so callers that don't care about the budget call this 5-arg form.
    func extractContext(
        locator: Locator,
        fullText: String,
        format: BookFormat,
        scope: SummaryScope,
        chapterBounds: ChapterBounds?
    ) -> String {
        extractContext(
            locator: locator, fullText: fullText, format: format,
            scope: scope, chapterBounds: chapterBounds,
            maxUTF16: AIContextBudget.defaultMaxUTF16
        )
    }
}
