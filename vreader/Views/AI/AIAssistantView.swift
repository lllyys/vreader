// Purpose: Main AI assistant panel UI.
// Shows action buttons, response text, and state-dependent content.
//
// Key decisions:
// - Minimal V1 UI — action buttons and text display.
// - Shows consent view when consent is required.
// - Shows disabled message when feature flag is off.
// - Loading state shows progress indicator.
// - Response text is scrollable.
//
// @coordinates-with: AIAssistantViewModel.swift, AIConsentView.swift

import SwiftUI

/// Main AI assistant panel view.
struct AIAssistantView: View {
    let viewModel: AIAssistantViewModel

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .idle:
                Text("Select an action to get AI assistance.")
                    .foregroundStyle(.secondary)

            case .loading:
                ProgressView("Processing...")

            case .streaming:
                ScrollView {
                    Text(viewModel.responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            case .complete:
                ScrollView {
                    Text(viewModel.responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

            case .error(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

            case .consentRequired:
                AIConsentView {
                    viewModel.grantConsent()
                }

            case .featureDisabled:
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars.inverse")
                        .foregroundStyle(.secondary)
                    Text("AI features are currently disabled.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
