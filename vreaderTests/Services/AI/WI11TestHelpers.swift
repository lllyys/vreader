// Purpose: Shared test helpers for WI-11 AI feature tests.
// Contains StubAIProvider and common factory methods.

import Foundation
@testable import vreader

// MARK: - Stub Provider

/// A stub AIProvider for testing that records calls and returns canned responses.
final class StubAIProvider: AIProvider, @unchecked Sendable {
    let providerName = "Stub"

    var stubbedResponse: AIResponse?
    var stubbedError: Error?
    private(set) var sendRequestCallCount = 0
    private(set) var lastRequest: AIRequest?

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        sendRequestCallCount += 1
        lastRequest = request
        if let error = stubbedError {
            throw error
        }
        guard let response = stubbedResponse else {
            throw AIError.invalidResponse
        }
        return response
    }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(AIStreamChunk(text: "streamed", isComplete: true))
            continuation.finish()
        }
    }
}

// MARK: - Shared Helpers

enum WI11TestHelpers {
    static let testFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    static func makeLocator(
        format: BookFormat = .txt,
        charOffset: Int? = 0
    ) -> Locator {
        Locator(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: testFP.contentSHA256,
                fileByteCount: testFP.fileByteCount,
                format: format
            ),
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: charOffset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    static func makeConsentManager(hasConsent: Bool) -> AIConsentManager {
        let suiteName = "com.vreader.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AIConsentManager(defaults: defaults)
        if hasConsent {
            manager.grantConsent()
        }
        return manager
    }

    static func makeKeychainService() -> KeychainService {
        KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
    }

    static func makeResponse(
        content: String = "AI response",
        actionType: AIActionType = .summarize,
        promptVersion: String = "v1"
    ) -> AIResponse {
        AIResponse(
            content: content,
            actionType: actionType,
            promptVersion: promptVersion,
            createdAt: Date()
        )
    }

    static func makeRequest(
        actionType: AIActionType = .summarize,
        promptVersion: String = "v1"
    ) -> AIRequest {
        AIRequest(
            actionType: actionType,
            bookFingerprint: testFP,
            locator: makeLocator(),
            contextText: "Some context text",
            userPrompt: nil,
            targetLanguage: nil,
            promptVersion: promptVersion
        )
    }
}
