// Purpose: A fully-resolved, immutable provider snapshot for feature #56
// bilingual reading. `AIService.resolveProvider()` snapshots the active
// `ProviderProfile` once *per request*; chapter translation is a *multi-request*
// operation (one request per chunk, many chunks per chapter) that must use ONE
// consistent provider + credential + model for the whole operation — otherwise
// a mid-operation profile swap or Keychain rotation could straddle chunks
// (Gate-2 round-1 H2 + round-2 N1).
//
// Key decisions:
// - Module-internal (NOT file-private to AIService) — `ChapterTranslationService`,
//   `BookTranslationCoordinator`, and `ChapterReTranslateViewModel` all pass it.
// - Carries the credential (`apiKey`) so a Keychain rotation cannot change it
//   across chunks, and `model` so the re-translate flow can override the model
//   for one operation without mutating the saved `ProviderProfile`.
// - Does NOT carry the re-translate `style` — `style` is a pure
//   prompt-construction input consumed only by `TranslationChunkContract`
//   (Gate-2 round-2 N4). This config is the *transport* snapshot.
//
// @coordinates-with: AIService.swift, ProviderKind.swift,
//   ChapterTranslationService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-5)

import Foundation

/// An immutable, fully-resolved AI-provider runtime configuration — the
/// one-snapshot-per-operation seam for multi-request translation work.
struct ResolvedAIProviderConfig: Sendable, Equatable {

    /// Which provider API this config speaks.
    let kind: ProviderKind

    /// The provider's base URL.
    let baseURL: URL

    /// The API credential — pinned so a mid-operation Keychain rotation
    /// cannot change it across requests.
    let apiKey: String

    /// The model identifier — may be a re-translate override of the
    /// profile's saved model.
    let model: String

    /// The `max_tokens` budget (Anthropic requires it on every request;
    /// carried for OpenAI too for a uniform config shape).
    let maxTokens: Int
}
