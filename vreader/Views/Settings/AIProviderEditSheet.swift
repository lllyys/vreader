// Purpose: SwiftUI editor sheet for an AI provider profile (feature #50
// WI-6b). Used in both ADD-NEW and EDIT-EXISTING modes — the sheet
// receives an optional `existing: ProviderProfile?` and adapts its
// title, primary button, and pre-fill behavior accordingly.
//
// Fields exposed:
// - kind picker (OpenAI-compatible / Anthropic native)
// - name TextField
// - baseURL TextField (URL keyboard, HTTPS validation)
// - model TextField
// - temperature Slider (0.0..2.0)
// - maxTokens Stepper (1..128_000, step 256)
// - API key SecureField + Save / Delete actions (edit-mode only)
// - Test Connection button (calls VM.testConnection(profile:) with a
//   ProviderProfile built from live form state)
//
// Key decisions:
// - The kind picker auto-resets baseURL + model to the new kind's
//   defaults, but only if the field still holds the OLD kind's default
//   (delegated to KindResetPolicy — round-2 audit fix [1]). This is
//   purely value-based, so no SwiftUI .onChange ordering assumption.
// - Save is disabled until name is non-empty AND baseURL passes
//   validation. The model field can be empty — the provider will return
//   an error from the API and surface it via Test Connection.
// - Test Connection uses live form state, not the stored profile
//   (round-1 audit fix [1]). Feature #80: it is available in BOTH modes,
//   gated on `hasTestableKey` (a typed in-memory key OR a saved key) — the
//   typed key wins over the keychain (empty/nil falls back), so an unsaved
//   add-mode key can be tested without a Save-and-reopen round-trip. A
//   `testGeneration` guard drops an in-flight result whose form state
//   changed mid-request; `resetTestResult()` clears stale results on every
//   request-shaping input + on save/delete-key.
// - Add-mode "Save Key" is disabled to prevent keychain orphans on
//   Cancel (round-1 audit fix [4]). The atomic addProfile path is the
//   only key-write path in add-mode.
// - Editor errors surface via an .alert bound to viewModel.editorError
//   (round-1 audit fix [5]).
// - On Save, the sheet validates one last time, calls VM.addProfile or
//   VM.updateProfile, and dismisses on success.
//
// @coordinates-with: AISettingsViewModel.swift,
//   AISettingsViewModel+Editor.swift, AIProviderListView.swift,
//   KindResetPolicy.swift, ProviderKind.swift, ProviderProfile.swift

import SwiftUI

/// Editor sheet for an AI provider profile. Presented modally from
/// `AIProviderListView` via the "+" toolbar button (add mode) or a
/// leading-edge swipe Edit action on a row (edit mode).
struct AIProviderEditSheet: View {
    @Bindable var viewModel: AISettingsViewModel
    /// Non-nil = edit-mode, pre-fill from this profile. Nil = add-mode.
    let existing: ProviderProfile?

    /// Feature #81: reader-flow hook fired AFTER a successful add/update,
    /// just before `dismiss()`. `wasAdd` is true for add-mode. Default nil
    /// → the Library presentation path is unchanged. `AIProviderListView`
    /// (not the reader) supplies this to buffer the saved id and re-emit it
    /// from its own `.sheet(onDismiss:)` once the editor fully dismisses
    /// (avoids popping the reader nav stack underneath a still-present
    /// editor sheet).
    let onSaveSuccess: ((UUID, _ wasAdd: Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State
    //
    // `internal` (default) access so the sections extension in
    // `AIProviderEditSheet+Sections.swift` can read & bind these
    // properties. Cross-file extensions cannot see `private` members.

    @State var profileID: UUID
    @State var name: String
    @State var kind: ProviderKind
    @State var baseURLText: String
    @State var model: String
    @State var temperature: Double
    @State var maxTokens: Int

    @State var apiKey: String = ""
    @State var isAPIKeySaved: Bool

    @State var baseURLError: String?
    @State var testResultText: String?
    @State var testInFlight: Bool = false
    /// Feature #80 (Gate-4 High): monotonic run id. `runTest()` captures it; any
    /// `resetTestResult()` (every request-shaping input change + save/delete-key)
    /// bumps it, so an IN-FLIGHT test whose form state changed mid-request does
    /// NOT repaint the stale result over the new state when it completes.
    @State var testGeneration: Int = 0

    // Round-2 audit fix: the previous design tracked `userEditedBaseURL`
    // / `userEditedModel` via field .onChange handlers + a transient
    // `isApplyingKindDefaults` flag. That depended on SwiftUI dispatching
    // the field .onChange callbacks synchronously inside the kind
    // .onChange closure, which is not guaranteed; if the runtime ever
    // delivered them later, the flag would already be false and the
    // fields would be wrongly marked as user-edited.
    //
    // The replacement is purely value-based: KindResetPolicy compares the
    // current field text against the OLD kind's default. If it still
    // matches, the user never touched it, so we replace it with the NEW
    // kind's default. If it doesn't match, the user typed something
    // custom and we leave it alone. No timing assumptions, no flags.

    init(
        viewModel: AISettingsViewModel,
        existing: ProviderProfile?,
        onSaveSuccess: ((UUID, _ wasAdd: Bool) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.existing = existing
        self.onSaveSuccess = onSaveSuccess

        if let existing {
            _profileID = State(initialValue: existing.id)
            _name = State(initialValue: existing.name)
            _kind = State(initialValue: existing.kind)
            _baseURLText = State(initialValue: existing.baseURL.absoluteString)
            _model = State(initialValue: existing.model)
            _temperature = State(initialValue: existing.temperature)
            _maxTokens = State(initialValue: existing.maxTokens)
            // Probe keychain for an existing key by id; presence vs absence
            // is the only signal we care about (we don't read the key text
            // back into the SecureField — that would defeat the purpose).
            let stored = (try? viewModel.keychainService.readAPIKey(forProfile: existing.id)) ?? nil
            _isAPIKeySaved = State(initialValue: stored != nil && !(stored?.isEmpty ?? true))
        } else {
            let newID = UUID()
            let defaultKind: ProviderKind = .openAICompatible
            _profileID = State(initialValue: newID)
            _name = State(initialValue: "")
            _kind = State(initialValue: defaultKind)
            // Feature #79 (Variant A): bind Base URL + Model EMPTY in add-mode.
            // The kind default is shown as a muted placeholder + "Default" tag;
            // a blank field resolves to the kind default at Save (the `effective`
            // helpers). Nothing to backspace.
            _baseURLText = State(initialValue: "")
            _model = State(initialValue: "")
            _temperature = State(initialValue: 0.7)
            _maxTokens = State(initialValue: 2048)
            _isAPIKeySaved = State(initialValue: false)
        }
    }

    /// Add-mode (vs edit an existing profile) — the discriminator for all the
    /// Feature #79 placeholder / effective-value behavior. Internal so the
    /// `+Sections` extension (separate file) can read it.
    var isAddMode: Bool { existing == nil }

    /// Feature #80: whether Test Connection can run — a key is typed in-memory
    /// (add-mode or a live edit) OR a key is already saved (edit-mode). Drives
    /// the Test button's enabled state + the "enter a key" hint in both modes.
    /// Pure static (testable without the view); whitespace-only typed key counts
    /// as no key.
    static func hasTestableKey(typedKey: String, isSaved: Bool) -> Bool {
        !typedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaved
    }
    var hasTestableKey: Bool { Self.hasTestableKey(typedKey: apiKey, isSaved: isAPIKeySaved) }

    // MARK: - Feature #79: effective values + placeholders (add-mode-only)

    /// The Base URL to validate / persist / test. In ADD-MODE a blank (or
    /// whitespace-only) field resolves to the kind default; otherwise the typed
    /// value. In EDIT-MODE it is always the raw typed value (so clearing a field
    /// still fails validation, never silently defaults — Gate-2 round-1 High).
    static func effectiveBaseURLText(isAddMode: Bool, typed: String, kind: ProviderKind) -> String {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return (isAddMode && t.isEmpty) ? kind.defaultBaseURL.absoluteString : t
    }

    /// The Model to persist / test, same add-mode-only fallback. Blank model is
    /// NOT provider-tolerated (serialized verbatim), so add-mode blank →
    /// kind.defaultModel is a required local fix (Gate-2 round-1 Medium).
    static func effectiveModel(isAddMode: Bool, typed: String, kind: ProviderKind) -> String {
        // Edit-mode: return the RAW typed value — pre-#79 `save()` persisted
        // `model` untrimmed, so trimming here would silently normalize an
        // existing whitespace-padded model on an unrelated save (Gate-4 Medium).
        guard isAddMode else { return typed }
        // Add-mode: blank (incl. whitespace-only) → kind default; else verbatim.
        return typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.defaultModel : typed
    }

    /// The Base URL placeholder text: the kind default in ADD-MODE, empty in
    /// EDIT-MODE (an existing profile with `model==""` must NOT show a misleading
    /// default hint — Gate-2 round-2 Medium).
    static func placeholderBaseURL(isAddMode: Bool, kind: ProviderKind) -> String {
        isAddMode ? kind.defaultBaseURL.absoluteString : ""
    }

    static func placeholderModel(isAddMode: Bool, kind: ProviderKind) -> String {
        isAddMode ? kind.defaultModel : ""
    }

    /// Instance conveniences over the pure statics with the current form state.
    var effectiveBaseURLText: String {
        Self.effectiveBaseURLText(isAddMode: isAddMode, typed: baseURLText, kind: kind)
    }
    var effectiveModel: String {
        Self.effectiveModel(isAddMode: isAddMode, typed: model, kind: kind)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                nameSection
                providerSection
                apiKeySection
                testConnectionSection
            }
            .navigationTitle(existing == nil ? "Add Provider" : "Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("editProviderCancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("editProviderSave")
                }
            }
            // Round-1 audit finding [5]: editor errors were set on the VM
            // but never surfaced. Bind an alert here so add/update/save-
            // key failures are visible to the user instead of silently
            // failing the dismiss-on-success path.
            .alert(
                "Profile Error",
                isPresented: Binding(
                    get: { viewModel.editorError != nil },
                    set: { if !$0 { viewModel.editorError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.editorError ?? "")
            }
        }
    }

    // Form sections live in AIProviderEditSheet+Sections.swift —
    // round-2 audit fix [2] split them out to keep this file under
    // the ~300-line guideline.

    // MARK: - Actions

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Feature #79: validate the EFFECTIVE URL (add-mode blank → kind
            // default, valid; edit-mode raw, so clearing still fails).
            && AISettingsViewModel.validateBaseURL(effectiveBaseURLText) == nil
    }

    func save() async {
        // Feature #79: validate + persist the EFFECTIVE Base URL / Model.
        baseURLError = AISettingsViewModel.validateBaseURL(effectiveBaseURLText)
        guard baseURLError == nil else { return }
        guard let url = URL(string: effectiveBaseURLText) else { return }

        let profile = ProviderProfile(
            id: profileID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            baseURL: url,
            model: effectiveModel,
            temperature: temperature,
            maxTokens: maxTokens
        )

        if existing == nil {
            await viewModel.addProfile(profile, apiKey: apiKey)
        } else {
            await viewModel.updateProfile(profile)
            // The editor sheet allows changing the API key in edit-mode
            // via the Save Key button; updateProfile doesn't touch the
            // keychain. So no additional work needed here.
        }

        if viewModel.editorError == nil {
            // Feature #81: report the saved id BEFORE dismissing so the
            // reader flow (via AIProviderListView's onDismiss re-emission)
            // can activate it as the bilingual engine + pop. `existing ==
            // nil` distinguishes add from edit. Library path: nil → no-op.
            onSaveSuccess?(profileID, existing == nil)
            dismiss()
        }
    }

    /// Feature #80: a stored test result describes the LAST tested form state, so
    /// any change that alters what the next test would do must clear it (back to
    /// idle) — otherwise a stale "Connected" lingers over edited inputs.
    func resetTestResult() {
        testResultText = nil
        testGeneration &+= 1  // invalidate any in-flight test run (Gate-4 High)
    }

    /// Whether a just-finished test run's result should be applied: only if its
    /// captured generation still matches (the form didn't change mid-request).
    static func shouldApplyTestResult(runGeneration: Int, currentGeneration: Int) -> Bool {
        runGeneration == currentGeneration
    }

    func saveKey() async {
        await viewModel.saveAPIKey(apiKey, forID: profileID)
        if viewModel.editorError == nil {
            isAPIKeySaved = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Clear the in-memory text since we don't display the saved
            // key back; the green checkmark is the only indicator.
            apiKey = ""
            // Feature #80: saved-key presence changed → invalidate any prior test.
            resetTestResult()
        }
    }

    func deleteKey() async {
        await viewModel.deleteAPIKey(forID: profileID)
        if viewModel.editorError == nil {
            isAPIKeySaved = false
            apiKey = ""
            resetTestResult()  // Feature #80: saved-key removed → stale result invalid.
        }
    }

    func runTest() async {
        testInFlight = true
        defer { testInFlight = false }
        // Feature #80 (Gate-4 High): stamp this run; if the form changes
        // mid-request (any reset bumps the generation), drop the stale result.
        testGeneration &+= 1
        let runGeneration = testGeneration

        // Audit round-1 finding [1]: build a candidate ProviderProfile
        // from the sheet's current form state so unsaved edits are
        // exercised. The id is still profileID — that's the keychain
        // account key. The provider config (baseURL, model, kind,
        // maxTokens) is whatever the user has on screen right now.
        // Feature #79: test the EFFECTIVE URL/model (add-mode blank → kind
        // default; edit-mode raw — unchanged).
        guard let url = URL(string: effectiveBaseURLText) else {
            testResultText = "Failed: invalid base URL."
            return
        }
        let candidate = ProviderProfile(
            id: profileID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            baseURL: url,
            model: effectiveModel,
            temperature: temperature,
            maxTokens: maxTokens
        )

        // Feature #80: pass the TYPED in-memory key so an unsaved (add-mode) key
        // is tested without a Save-and-reopen round-trip. Empty → nil → the VM
        // falls back to the keychain (edit-mode saved-key path, unchanged).
        let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await viewModel.testConnection(
            profile: candidate, apiKeyOverride: typedKey.isEmpty ? nil : typedKey)
        // Gate-4 High: the form may have changed while the request was in flight;
        // only apply this result if its run is still current.
        guard Self.shouldApplyTestResult(runGeneration: runGeneration, currentGeneration: testGeneration) else { return }
        switch result {
        case .success:
            testResultText = "Connected — the provider responded successfully."
        case .failure(let error):
            testResultText = "Failed: \(error.localizedDescription)"
        }
    }
}
