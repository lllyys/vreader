// Purpose: The single pure funnel that builds the AI Chat tab's injected
// `bookContext` from the selected scope's text + the serialized annotation block,
// and bundles the citation set the assembled context drew on (Feature #86 WI-2+).
// Replaces WI-1's "chatContext is just the chapter text" path with a
// scope+sources-parameterized assembly.
//
// Key decisions:
// - Scope text first, annotation block second (the model reads the book text,
//   then "what the reader marked"), separated by a blank line.
// - Budget-capped to a UTF-16 ceiling, CJK-safe; the scope text is preserved
//   first (it's the primary signal), the annotation block is what gets trimmed.
// - Pure `enum`: no state, fully deterministic, so the funnel is testable and
//   idempotent (a relocate that recomputes the same inputs yields the same output).
//
// @coordinates-with: ChatAnnotationContext.swift, ChatCitation.swift,
//   ReaderAICoordinator.swift (WI-3/4), AIChatViewModel.swift

import Foundation

/// The assembled Chat AI context + its provenance. Feature #86 WI-2+.
struct ChatContextAssembly: Sendable, Equatable {
    let bookContext: String
    let citations: [ChatCitation]

    static let empty = ChatContextAssembly(bookContext: "", citations: [])
}

enum ChatContextAssembler {

    /// The annotation source kinds — citations the annotation block contributes.
    /// (Scope / whole-book citations come from the scope text, not the block.)
    private static let annotationKinds: Set<ChatCitation.SourceKind> = [.note, .highlight, .bookmark]

    /// Combines the scope text and the annotation block into the injected
    /// `bookContext`, clamped to `maxUTF16`, and bundles the citations — keeping
    /// only the citations whose content actually SURVIVED the clamp (Gate-4: the
    /// provenance must match what was injected, not the pre-clamp inputs).
    ///
    /// - Parameters:
    ///   - scopeText: the text the selected scope resolved to (already
    ///     budget-shaped by `AIContextExtractor` / the whole-book digest).
    ///   - annotationBlock: the serialized `[Your notes & marks]` block (may be "").
    ///   - citations: the provenance the caller derived for this assembly.
    static func assemble(
        scopeText: String,
        annotationBlock: String,
        citations: [ChatCitation],
        maxUTF16: Int
    ) -> ChatContextAssembly {
        let trimmedScope = scopeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBlock = annotationBlock.trimmingCharacters(in: .whitespacesAndNewlines)

        // Where the annotation block begins in the combined string (UTF-16 units).
        let blockStartUTF16: Int
        let combined: String
        if trimmedBlock.isEmpty {
            combined = trimmedScope
            blockStartUTF16 = trimmedScope.utf16.count   // no block
        } else if trimmedScope.isEmpty {
            combined = trimmedBlock
            blockStartUTF16 = 0
        } else {
            combined = trimmedScope + "\n\n" + trimmedBlock
            blockStartUTF16 = trimmedScope.utf16.count + 2  // "\n\n"
        }

        let bounded = UTF16Clamp.clamp(combined, maxUTF16: max(0, maxUTF16))

        // Citation retention:
        // - bookContext empty → nothing was injected → no citations.
        // - the annotation block didn't fully survive the clamp → drop the
        //   annotation-derived citations (the scope citation still holds, since
        //   the scope text is preserved first).
        let citations = retainedCitations(
            citations, bounded: bounded, trimmedBlock: trimmedBlock, blockStartUTF16: blockStartUTF16
        )
        return ChatContextAssembly(bookContext: bounded, citations: citations)
    }

    private static func retainedCitations(
        _ citations: [ChatCitation], bounded: String, trimmedBlock: String, blockStartUTF16: Int
    ) -> [ChatCitation] {
        guard !bounded.isEmpty else { return [] }
        let blockFullySurvived = trimmedBlock.isEmpty
            || bounded.utf16.count >= blockStartUTF16 + trimmedBlock.utf16.count
        guard !blockFullySurvived else { return citations }
        return citations.filter { !annotationKinds.contains($0.sourceKind) }
    }
}
