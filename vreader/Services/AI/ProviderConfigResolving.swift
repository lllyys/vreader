// Purpose: Feature #98 WI-2 — narrow resolver seam so the
// `BookTranslationCoordinator` can rebuild a `ResolvedAIProviderConfig` from
// a PERSISTED profile id when resuming an interrupted whole-book job
// (Gate-2 round 2: the coordinator's live contract had no resolver access;
// `start(...)` requires a caller-supplied pre-resolved config).
//
// @coordinates-with: AIService.swift, BookTranslationCoordinator.swift,
//   dev-docs/plans/20260611-feature-98-background-resilient-translation.md

import Foundation

/// Resolves a named provider profile into a config snapshot. Production is
/// `AIService` (the method already exists with this exact signature); tests
/// inject a recorder stub.
protocol ProviderConfigResolving: Sendable {
    func resolveProviderConfig(
        profileID: UUID,
        modelOverride: String?
    ) async throws -> ResolvedAIProviderConfig
}

extension AIService: ProviderConfigResolving {}
