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

    /// Feature #79: the muted "Default" chip shown beside an empty add-mode
    /// field (committed design `vreader-ai-provider-fields.jsx`). Signals the
    /// kind default will be used if left blank — no text to delete.
    var defaultTag: some View {
        Text("Default")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    @ViewBuilder
    var providerSection: some View {
        Section {
            HStack {
                Text("Base URL")
                    .foregroundStyle(.secondary)
                Spacer()
                // Feature #79: "Default" tag shown only in add-mode while the
                // field is empty (the kind default applies at Save).
                if isAddMode && baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    defaultTag.accessibilityIdentifier("editProviderBaseURLDefaultTag")
                }
                // Add-mode → kind default as the placeholder; edit-mode → none.
                TextField(
                    AIProviderEditSheet.placeholderBaseURL(isAddMode: isAddMode, kind: kind),
                    text: $baseURLText
                )
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("editProviderBaseURL")
                    .onChange(of: baseURLText) { _, _ in
                        // Validate the EFFECTIVE URL (add-mode blank → kind
                        // default → no spurious "empty" error; edit-mode raw).
                        baseURLError = AISettingsViewModel.validateBaseURL(
                            AIProviderEditSheet.effectiveBaseURLText(
                                isAddMode: isAddMode, typed: baseURLText, kind: kind))
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
                if isAddMode && model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    defaultTag.accessibilityIdentifier("editProviderModelDefaultTag")
                }
                TextField(
                    AIProviderEditSheet.placeholderModel(isAddMode: isAddMode, kind: kind),
                    text: $model
                )
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editProviderModel")
            }
        } header: {
            Text("Endpoint")
        } footer: {
            // Bug #185: per-kind hint explaining what path the app appends.
            // Without this, users entering full endpoint URLs get silent
            // doubled paths (e.g. `…/v1/chat/completions/chat/completions`).
            Text(kind.endpointPathHint)
                .accessibilityIdentifier("editProviderBaseURLHint")
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

            // Bug #184: in add-mode the Save Key button was always disabled
            // (keychain-orphan prevention — see audit round-1 finding [4]).
            // The disabled button confused users who didn't notice the
            // caption2/tertiary hint. Hide the buttons row in add-mode and
            // show only a promoted (footnote/secondary) inline note so the
            // next action is unambiguous: "tap Save at the top".
            if let _ = existing {
                HStack {
                    Button("Save Key") {
                        Task { await saveKey() }
                    }
                    .disabled(apiKey.isEmpty)
                    .accessibilityIdentifier("editProviderSaveKeyButton")

                    if isAPIKeySaved {
                        Button("Delete Key", role: .destructive) {
                            Task { await deleteKey() }
                        }
                        .accessibilityIdentifier("editProviderDeleteKeyButton")
                    }
                }
            } else {
                Text("The key is stored only after the profile is saved. Enter the key above, then tap Save at the top of this sheet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editProviderSaveKeyNote")
            }
        }
    }

    // MARK: - Test Connection

    @ViewBuilder
    var testConnectionSection: some View {
        Section("Connection") {
            // Bug #184: in add-mode the Test Connection button was always
            // disabled because the keychain account is keyed by profileID,
            // and in add-mode that key is only written by addProfile on
            // top-level Save (audit round-1 finding [1]). Hide the button
            // in add-mode and promote the explanation from caption2/tertiary
            // to footnote/secondary so it reads as the next instruction.
            if existing != nil {
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
                .disabled(testInFlight || !isAPIKeySaved)
                .accessibilityIdentifier("editProviderTestConnection")

                if let result = testResultText {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("Connected") ? .green : .red)
                        .accessibilityIdentifier("editProviderTestResult")
                }
            } else {
                Text("Save the profile first, then return here to test the connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editProviderTestConnectionNote")
            }
        }
    }
}
