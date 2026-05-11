// Purpose: Form-section view builders for AIProviderEditSheet. Split
// out of the main sheet file (feature #50 WI-6b round-2 audit fix [2])
// to keep the parent under the ~300-line guideline. The sections need
// access to the sheet's @State properties, so they live in an extension
// on the same struct rather than as standalone Views — keeps the
// binding semantics ($kind, $baseURLText, etc.) identical to inline
// definitions.
//
// @coordinates-with: AIProviderEditSheet.swift, KindResetPolicy.swift

import SwiftUI

extension AIProviderEditSheet {

    // MARK: - Provider kind picker

    var kindSection: some View {
        Section("Provider Type") {
            Picker("Kind", selection: $kind) {
                ForEach(ProviderKind.allCases, id: \.self) { k in
                    Text(k.displayName).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editProviderKindPicker")
            .onChange(of: kind) { oldKind, newKind in
                // Pure value-based reset — no .onChange ordering
                // assumptions. KindResetPolicy compares the current
                // field text against the OLD kind's default in add-mode;
                // in edit-mode it always returns false because the
                // user's saved values are sticky (round-3 audit fix).
                // See KindResetPolicy.swift for the audit history.
                let inEditMode = existing != nil
                if KindResetPolicy.shouldReplaceBaseURL(
                    current: baseURLText, oldKind: oldKind, inEditMode: inEditMode
                ) {
                    baseURLText = newKind.defaultBaseURL.absoluteString
                    baseURLError = AISettingsViewModel.validateBaseURL(baseURLText)
                }
                if KindResetPolicy.shouldReplaceModel(
                    current: model, oldKind: oldKind, inEditMode: inEditMode
                ) {
                    model = newKind.defaultModel
                }
            }
        }
    }

    // MARK: - Name

    var nameSection: some View {
        Section("Name") {
            TextField("e.g. \"ChatGPT\" or \"Local Llama\"", text: $name)
                .autocorrectionDisabled()
                .accessibilityIdentifier("editProviderName")
        }
    }

    // MARK: - Endpoint + Sampling

    @ViewBuilder
    var providerSection: some View {
        Section("Endpoint") {
            HStack {
                Text("Base URL")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("https://api.example.com/v1", text: $baseURLText)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("editProviderBaseURL")
                    .onChange(of: baseURLText) { _, _ in
                        baseURLError = AISettingsViewModel.validateBaseURL(baseURLText)
                    }
            }
            if let error = baseURLError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("editProviderBaseURLError")
            }

            HStack {
                Text("Model")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("e.g. gpt-4o-mini", text: $model)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editProviderModel")
            }
        }

        Section("Sampling") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Temperature")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .monospacedDigit()
                }
                Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                    .accessibilityIdentifier("editProviderTemperature")
            }
            Stepper(
                "Max Tokens: \(maxTokens)",
                value: $maxTokens,
                in: 1...128_000,
                step: 256
            )
            .accessibilityIdentifier("editProviderMaxTokens")
        }
    }

    // MARK: - API key

    @ViewBuilder
    var apiKeySection: some View {
        Section("API Key") {
            HStack {
                SecureField("Enter API Key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editProviderAPIKey")
                if isAPIKeySaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("API key saved")
                }
            }
            HStack {
                Button("Save Key") {
                    Task { await saveKey() }
                }
                // Audit round-1 finding [4]: in add-mode the sheet
                // generates a UUID up front but the profile isn't in the
                // store yet. Writing a keychain entry here would leak an
                // orphaned secret if the user then taps Cancel. Force
                // add-mode users to enter the key in the SecureField and
                // commit via the top-level "Save" button — addProfile
                // persists key + profile atomically.
                .disabled(apiKey.isEmpty || existing == nil)
                .accessibilityIdentifier("editProviderSaveKeyButton")

                if isAPIKeySaved && existing != nil {
                    Button("Delete Key", role: .destructive) {
                        Task { await deleteKey() }
                    }
                    .accessibilityIdentifier("editProviderDeleteKeyButton")
                }
            }

            if existing == nil {
                Text("Enter your API key above, then tap Save to create the profile. The key is stored only after the profile is saved.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Test Connection

    @ViewBuilder
    var testConnectionSection: some View {
        Section("Connection") {
            Button {
                Task { await runTest() }
            } label: {
                HStack {
                    if testInFlight {
                        ProgressView().padding(.trailing, 8)
                    }
                    Text("Test Connection")
                }
            }
            // Test Connection now operates on live form state (round-1
            // audit finding [1]), but still requires a saved keychain
            // entry — the keychain account is keyed by profileID, and
            // in add-mode that key is only written by addProfile on
            // top-level Save. So the button is enabled in edit-mode
            // when a key is saved, and disabled in add-mode.
            .disabled(testInFlight || !isAPIKeySaved || existing == nil)
            .accessibilityIdentifier("editProviderTestConnection")

            if let result = testResultText {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("Connected") ? .green : .red)
                    .accessibilityIdentifier("editProviderTestResult")
            }

            if existing == nil {
                Text("Save the profile first to test the connection.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
