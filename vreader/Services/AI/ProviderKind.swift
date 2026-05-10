// Purpose: Discriminator for AI provider protocols (feature #50 WI-1).
// Each kind names a distinct on-the-wire API:
// - openAICompatible: POST /v1/chat/completions, Authorization: Bearer
// - anthropicNative:  POST /v1/messages, x-api-key, anthropic-version: 2023-06-01
//
// Each case carries its own default base URL and default model so the
// "Add provider" UI can pre-fill a sensible starting point without coupling
// the form to a specific provider concrete.
//
// @coordinates-with: ProviderProfile.swift, AIService.swift,
//   AnthropicProvider.swift, OpenAICompatibleProvider (in AIProvider.swift)

import Foundation

/// Identifies which on-the-wire API a provider speaks.
enum ProviderKind: String, Codable, Sendable, CaseIterable {
    /// OpenAI-compatible chat completions API. Works with OpenAI, Azure
    /// OpenAI, Ollama, LM Studio, and any other server that implements
    /// `POST /v1/chat/completions` with `Authorization: Bearer`.
    case openAICompatible

    /// Anthropic Messages API. `POST /v1/messages` with `x-api-key`
    /// header and required `anthropic-version` header.
    case anthropicNative

    /// Default base URL for new profiles of this kind.
    var defaultBaseURL: URL {
        switch self {
        case .openAICompatible:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.openai.com/v1")!
        case .anthropicNative:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.anthropic.com")!
        }
    }

    /// Default model identifier for new profiles of this kind.
    /// Users can override per-profile in Settings.
    var defaultModel: String {
        switch self {
        case .openAICompatible:
            return "gpt-4o-mini"
        case .anthropicNative:
            return "claude-sonnet-4-6"
        }
    }

    /// Human-readable name for the kind, used in pickers and labels.
    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicNative:
            return "Anthropic"
        }
    }
}
