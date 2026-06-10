// Purpose: Feature #56 WI-15 boundary protocols for
// `ChapterReTranslateViewModel`. Two seams:
//
//   1. `RetranslateProviderResolving` — produces a `ResolvedAIProviderConfig`
//      from a picker-chosen `(profileID, modelOverride)`. `AIService`
//      conforms in production; tests inject a deterministic mock that
//      records the resolved (profile, model) without touching the Keychain.
//
//   2. `ChapterReTranslating` — runs the translation for ONE unit.
//      `ChapterTranslationService` conforms via an extension that delegates
//      to its existing `translate(...)` entry point. Tests inject a mock
//      that records the config + style without reaching an AI provider.
//
// Both protocols are `Sendable` so the VM can store them as `any …`
// existentials without sacrificing Swift 6 strict concurrency.
//
// Extracted from `ChapterReTranslateViewModel.swift` so the VM file stays
// under the ~300-LoC budget (rule 50 §9).
//
// @coordinates-with: ChapterReTranslateViewModel.swift, AIService.swift,
//   ChapterTranslationService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import Foundation

// MARK: - Provider resolution

/// The provider-resolution boundary the re-translate VM depends on. `AIService`
/// conforms in production; tests inject a deterministic mock that records what
/// the picker resolved without reaching the Keychain.
protocol RetranslateProviderResolving: Sendable {
    /// Resolves a *named* profile into a full runtime config, applying an
    /// optional model override. Mirrors `AIService.resolveProviderConfig(...)`.
    func resolveProviderConfig(
        profileID: UUID, modelOverride: String?
    ) async throws -> ResolvedAIProviderConfig
}

extension AIService: RetranslateProviderResolving {}

// MARK: - Translation execution

/// The translation-execution boundary. `ChapterTranslationService` conforms via
/// the extension below. Tests inject a deterministic runner that records the
/// resolved config + style without calling any AI provider.
protocol ChapterReTranslating: Sendable {
    /// `onChunkProgress` (Bug #311): fired with `(completedChunks, totalChunks)`
    /// after each chunk lands, so the VM can drive an honest N-of-M progress bar
    /// rather than a faked 0.5 pin during the opaque translate. `@Sendable` —
    /// it crosses from the service actor back to the `@MainActor` VM.
    func translateForRetranslate(
        bookFingerprintKey: String,
        unit: TranslationUnitID,
        sourceText: String,
        targetLanguage: String,
        providerProfileID: UUID,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle,
        granularity: TranslationGranularity,
        onChunkProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> ChapterTranslationResult
}

extension ChapterTranslationService: ChapterReTranslating {
    func translateForRetranslate(
        bookFingerprintKey: String,
        unit: TranslationUnitID,
        sourceText: String,
        targetLanguage: String,
        providerProfileID: UUID,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle,
        granularity: TranslationGranularity,
        onChunkProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> ChapterTranslationResult {
        try await translate(
            bookFingerprintKey: bookFingerprintKey,
            unit: unit,
            sourceText: sourceText,
            targetLanguage: targetLanguage,
            providerProfileID: providerProfileID,
            config: config,
            style: style,
            granularity: granularity,
            // Bug #341: an explicit re-translate must not be short-circuited
            // by a fresh cache hit; the post-translate upsert replaces the row
            // in place (atomic swap — failure leaves the old row untouched).
            bypassCacheRead: true,
            onChunkProgress: onChunkProgress)
    }
}
