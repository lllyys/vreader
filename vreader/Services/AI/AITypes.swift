// Purpose: Data models for AI assistant requests, responses, and streaming chunks.
// Defines the action taxonomy, request/response DTOs, and cache key generation.
//
// Key decisions:
// - All types are Sendable for Swift 6 strict concurrency.
// - AIActionType is Codable for cache serialization.
// - Cache key is a deterministic string from (fingerprint, locatorHash, actionType, promptVersion).
// - AIRequest is not Codable — it carries runtime context that should not be serialized directly.
// - AIResponse is Codable for cache storage.
//
// @coordinates-with: AIService.swift, AIResponseCache.swift

import Foundation

/// Categories of AI actions available to the reader.
enum AIActionType: String, Codable, Sendable, CaseIterable {
    case summarize
    case explain
    case translate
    case vocabulary
    case questionAnswer
}

/// A request to the AI provider with full context.
struct AIRequest: Sendable {
    let actionType: AIActionType
    let bookFingerprint: DocumentFingerprint
    let locator: Locator
    let contextText: String
    let userPrompt: String?
    let targetLanguage: String?
    let promptVersion: String

    /// Deterministic cache key for deduplication.
    /// Format: "{canonicalKey}:{locatorHash}:{actionType}:{promptVersion}"
    var cacheKey: String {
        let fpKey = bookFingerprint.canonicalKey
        let locHash = locator.canonicalHash
        return "\(fpKey):\(locHash):\(actionType.rawValue):\(promptVersion)"
    }
}

/// A completed AI response, suitable for caching.
struct AIResponse: Codable, Sendable, Equatable {
    let content: String
    let actionType: AIActionType
    let promptVersion: String
    let createdAt: Date
}

/// A chunk from a streaming AI response.
struct AIStreamChunk: Sendable, Equatable {
    let text: String
    let isComplete: Bool
}
