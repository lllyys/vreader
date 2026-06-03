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

        // Citation retention: keep only citations whose content actually survived
        // the clamp — PER source SECTION (Gate-4 WI-6), not all-or-nothing, so a
        // partial clamp that keeps Notes but drops Bookmarks under-reports neither.
        let citations = retainedCitations(
            citations, block: trimmedBlock, blockStartUTF16: blockStartUTF16, bounded: bounded
        )
        return ChatContextAssembly(bookContext: bounded, citations: citations)
    }

    /// The section header each annotation-kind citation maps to.
    private static func sectionHeader(for kind: ChatCitation.SourceKind) -> String? {
        switch kind {
        case .note:      return ChatAnnotationContext.notesHeader
        case .highlight: return ChatAnnotationContext.highlightsHeader
        case .bookmark:  return ChatAnnotationContext.bookmarksHeader
        case .scope, .wholeBookSpan: return nil   // not annotation-block-derived
        }
    }

    /// The UTF-16 offset (in the COMBINED string) where a section's first bullet
    /// content begins. Searches ONLY the annotation `block` (never the scope text),
    /// via the line-anchored marker `"\n<header>\n- "`, so scope/annotation prose
    /// that happens to match the line shape can't false-retain a citation. Returns
    /// nil if the section isn't in the block.
    private static func firstBulletUTF16Offset(
        forHeader header: String, block: String, blockStartUTF16: Int
    ) -> Int? {
        let marker = "\n" + header + "\n- "
        guard let range = block.range(of: marker) else { return nil }
        return blockStartUTF16 + block[block.startIndex..<range.upperBound].utf16.count
    }

    private static func retainedCitations(
        _ citations: [ChatCitation], block: String, blockStartUTF16: Int, bounded: String
    ) -> [ChatCitation] {
        guard !bounded.isEmpty else { return [] }   // nothing injected → no provenance
        let boundedLen = bounded.utf16.count
        return citations.filter { citation in
            guard let header = sectionHeader(for: citation.sourceKind) else {
                return true   // scope / whole-book citations ride with the scope text (kept)
            }
            guard let firstBullet = firstBulletUTF16Offset(
                forHeader: header, block: block, blockStartUTF16: blockStartUTF16
            ) else {
                return false   // the section isn't in the annotation block at all
            }
            // The section's first ITEM survived iff the clamp kept past its bullet
            // marker. (A clamp that preserves only the bullet's `[label]` prefix but
            // cuts the item text can still retain — an accepted narrow over-report
            // in the rare >budget-clamp case; provenance is advisory.)
            return boundedLen > firstBullet
        }
    }
}
