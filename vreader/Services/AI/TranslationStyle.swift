// Purpose: The re-translation style enum for feature #56 bilingual reading
// (from `vreader-retranslate.jsx`). A pure prompt-construction input — it is
// folded into the translation chunk prompt by `TranslationChunkContract`, and
// is NEVER a wire field on `AIRequest` / `ResolvedAIProviderConfig`
// (Gate-2 round-2 N4 — `style` lives only in the prompt).
//
// @coordinates-with: TranslationChunkContract.swift,
//   ChapterTranslationService.swift, ChapterReTranslateViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Foundation

/// How the translation should read — the re-translate picker's style choice.
enum TranslationStyle: String, Sendable, CaseIterable, Codable {
    /// Word-for-word faithful to the source structure.
    case literal
    /// Natural target-language phrasing (the bilingual-mode default).
    case natural
    /// Polished, literary target-language prose.
    case literary
}
