// Purpose: Tests for ProviderKind enum (feature #50 WI-1).
// Verifies Codable round-trip, default values, CaseIterable order, displayName.

import Testing
import Foundation
@testable import vreader

@Suite("ProviderKind")
struct ProviderKindTests {

    @Test func rawValuesStable() {
        #expect(ProviderKind.openAICompatible.rawValue == "openAICompatible")
        #expect(ProviderKind.anthropicNative.rawValue == "anthropicNative")
    }

    @Test func codableRoundTripOpenAI() throws {
        let original = ProviderKind.openAICompatible
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderKind.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundTripAnthropic() throws {
        let original = ProviderKind.anthropicNative
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderKind.self, from: data)
        #expect(decoded == original)
    }

    @Test func defaultBaseURLOpenAI() {
        let url = ProviderKind.openAICompatible.defaultBaseURL
        #expect(url.absoluteString == "https://api.openai.com/v1")
    }

    @Test func defaultBaseURLAnthropic() {
        let url = ProviderKind.anthropicNative.defaultBaseURL
        #expect(url.absoluteString == "https://api.anthropic.com")
    }

    @Test func defaultModelOpenAIIsLocked() {
        // The plan locks specific defaults so the prefilled UI in WI-6
        // behaves predictably. A silent change here would change what
        // users see on "Add provider" without surfacing in code review.
        #expect(ProviderKind.openAICompatible.defaultModel == "gpt-4o-mini")
    }

    @Test func defaultModelAnthropicIsLocked() {
        #expect(ProviderKind.anthropicNative.defaultModel == "claude-sonnet-4-6")
    }

    @Test func displayNameNonEmpty() {
        for kind in ProviderKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test func caseIterableOrderStable() {
        // Order is part of the contract: UI lists kinds in this order.
        // Changing the order requires updating consumers.
        let cases = ProviderKind.allCases
        #expect(cases.count == 2)
        #expect(cases[0] == .openAICompatible)
        #expect(cases[1] == .anthropicNative)
    }

    @Test func displayNamesAreDistinct() {
        let names = ProviderKind.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }
}
