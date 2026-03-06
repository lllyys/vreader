// Purpose: Consent prompt shown before first AI feature use.
// Explains what data will be sent and requires explicit opt-in.
//
// Key decisions:
// - Informational text explains data sharing clearly.
// - Single "I Agree" button to grant consent.
// - No dismiss without action — user must explicitly consent or navigate away.
// - Uses AIConsentManager directly for simplicity in V1.
//
// @coordinates-with: AIConsentManager.swift, AIAssistantView.swift

import SwiftUI

/// Consent prompt for AI features.
struct AIConsentView: View {
    let onConsent: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("AI Assistant")
                .font(.headline)

            Text("To use AI features, text from your current reading position will be sent to an external AI provider. No data is sent without your explicit consent.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("I Agree — Enable AI") {
                onConsent()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("aiConsentButton")

            Text("You can revoke consent at any time in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .accessibilityIdentifier("aiConsentView")
    }
}
