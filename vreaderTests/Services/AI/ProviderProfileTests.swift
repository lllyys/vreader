// Purpose: Tests for ProviderProfile struct (feature #50 WI-1).
// Verifies Codable round-trip, UUID identity, structural equality.

import Testing
import Foundation
@testable import vreader

@Suite("ProviderProfile")
struct ProviderProfileTests {

    private static func makeProfile(
        id: UUID = UUID(),
        name: String = "Test Provider",
        kind: ProviderKind = .openAICompatible,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4o-mini",
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) -> ProviderProfile {
        ProviderProfile(
            id: id,
            name: name,
            kind: kind,
            baseURL: baseURL,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    @Test func codableRoundTrip() throws {
        let original = Self.makeProfile()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderProfile.self, from: data)
        #expect(decoded == original)
    }

    @Test func anthropicProfileRoundTrip() throws {
        let original = Self.makeProfile(
            name: "Claude",
            kind: .anthropicNative,
            baseURL: URL(string: "https://api.anthropic.com")!,
            model: "claude-sonnet-4-6",
            maxTokens: 4096
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderProfile.self, from: data)
        #expect(decoded == original)
        #expect(decoded.kind == .anthropicNative)
    }

    @Test func uuidIdentity() {
        let id = UUID()
        let a = Self.makeProfile(id: id, name: "First name")
        let b = Self.makeProfile(id: id, name: "Renamed")
        // Same id, different name → not equal under structural equality,
        // but id field stays stable for downstream identity tracking.
        #expect(a.id == b.id)
        #expect(a != b)
    }

    @Test func structuralEqualityCoversAllFields() {
        let base = Self.makeProfile()

        // Differing id alone must produce inequality. Without this case a
        // future custom `==` that accidentally ignored identity would still
        // pass — and downstream active-profile logic depends on `id` being
        // part of equality.
        #expect(base != ProviderProfile(
            id: UUID(), name: base.name, kind: base.kind,
            baseURL: base.baseURL, model: base.model,
            temperature: base.temperature, maxTokens: base.maxTokens
        ))
        #expect(base != ProviderProfile(
            id: base.id, name: "different", kind: base.kind,
            baseURL: base.baseURL, model: base.model,
            temperature: base.temperature, maxTokens: base.maxTokens
        ))
        #expect(base != ProviderProfile(
            id: base.id, name: base.name, kind: .anthropicNative,
            baseURL: base.baseURL, model: base.model,
            temperature: base.temperature, maxTokens: base.maxTokens
        ))
        #expect(base != ProviderProfile(
            id: base.id, name: base.name, kind: base.kind,
            baseURL: URL(string: "https://other.example.com/v1")!,
            model: base.model, temperature: base.temperature, maxTokens: base.maxTokens
        ))
        #expect(base != ProviderProfile(
            id: base.id, name: base.name, kind: base.kind,
            baseURL: base.baseURL, model: "different-model",
            temperature: base.temperature, maxTokens: base.maxTokens
        ))
        #expect(base != ProviderProfile(
            id: base.id, name: base.name, kind: base.kind,
            baseURL: base.baseURL, model: base.model,
            temperature: base.temperature + 0.1, maxTokens: base.maxTokens
        ))
        #expect(base != ProviderProfile(
            id: base.id, name: base.name, kind: base.kind,
            baseURL: base.baseURL, model: base.model,
            temperature: base.temperature, maxTokens: base.maxTokens + 1
        ))
    }

    @Test func identifiableConformance() {
        // ProviderProfile must be Identifiable for SwiftUI List rendering.
        let id = UUID()
        let profile = Self.makeProfile(id: id)
        // Trivial assertion that the Identifiable id matches.
        let asIdentifiable: any Identifiable = profile
        _ = asIdentifiable
        #expect(profile.id == id)
    }

    @Test func canonicalJSONShapeStable() throws {
        // Canary fixture: encoded JSON must include each field by exact name
        // so older builds (or the migration layer) can decode forward-compat.
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let profile = Self.makeProfile(
            id: id,
            name: "Canary",
            kind: .anthropicNative,
            baseURL: URL(string: "https://api.anthropic.com")!,
            model: "claude-sonnet-4-6",
            temperature: 0.5,
            maxTokens: 1024
        )
        let data = try JSONEncoder().encode(profile)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"id\""))
        #expect(json.contains("\"name\""))
        #expect(json.contains("\"kind\""))
        #expect(json.contains("\"baseURL\""))
        #expect(json.contains("\"model\""))
        #expect(json.contains("\"temperature\""))
        #expect(json.contains("\"maxTokens\""))
        #expect(json.contains("\"anthropicNative\""))
    }
}
