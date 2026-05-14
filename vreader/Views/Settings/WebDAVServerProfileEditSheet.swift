// Purpose: WebDAV server profile editor sheet (Feature #52 WI-4b).
// Replaces WI-4a's stub with the full add/edit form. Used in both
// ADD-NEW and EDIT-EXISTING modes — receives an optional
// `existing: WebDAVServerProfile?` and adapts title, primary button,
// and pre-fill accordingly.
//
// Fields exposed:
// - Name TextField (free-form; empty falls back to serverURL host)
// - Server URL TextField (URL keyboard, https/http accepted per bug #110)
// - Username TextField
// - Password SecureField + Save / Delete actions (edit-mode only)
// - Test Connection button (edit-mode only; add-mode shows promoted note)
//
// Key decisions:
// - Mirrors `AIProviderEditSheet` shape (Feature #50 WI-6b) — same form/
//   sections split, same .alert binding, same add-mode-hides-keychain-
//   buttons pattern (bug #184).
// - Save is disabled until name is non-empty (after trim) AND server URL
//   is parseable as `URL` with a scheme AND username is non-empty.
//   Password is not gated at the Save level in add-mode because it's
//   gated separately — empty password makes the password section show
//   a "required" hint and disables Save. Edit-mode allows saving with
//   an unchanged password.
// - Test Connection uses live form state, not the stored profile, so
//   unsaved edits are exercised (mirrors AI editor's runTest).
// - Add-mode hides Save Key / Delete Key / Test Connection buttons; shows
//   promoted footnote notes telling the user to Save the profile first
//   (bug #184 pattern, edit-mode shows the real buttons).
// - On Save: add-mode calls VM.addProfile (atomic profile + keychain
//   write); edit-mode calls VM.updateProfile (metadata only — keychain
//   is touched via explicit Save Key button).
// - Re-entrancy guard (`saveInFlight`) prevents double-tap from creating
//   two profiles in add-mode. Matches the AI editor + WI-4a stub pattern.
//
// @coordinates-with: WebDAVServerProfileListView.swift,
//   WebDAVServerProfile.swift, WebDAVServerProfileStore.swift,
//   WebDAVProfileListViewModel.swift, WebDAVProfileListViewModel+Editor.swift

import SwiftUI

/// Editor sheet for a `WebDAVServerProfile`. Presented modally from
/// `WebDAVServerProfileListView` via the "+" toolbar button (add mode)
/// or a leading-edge swipe Edit action on a row (edit mode).
struct WebDAVServerProfileEditSheet: View {

    /// VM that owns the editor operations + error surface. Bindable so
    /// the editor's .alert binding triggers re-render when editorError
    /// flips.
    @Bindable var viewModel: WebDAVProfileListViewModel

    /// Non-nil = edit-mode, pre-fill from this profile. Nil = add-new.
    let existing: WebDAVServerProfile?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State var profileID: UUID
    @State var name: String
    @State var serverURL: String
    @State var username: String

    /// Cleared after a successful Save Key in edit-mode (we don't read
    /// keychain text back into the field — presence is signaled by
    /// `isPasswordSaved`).
    @State var password: String = ""

    @State var isPasswordSaved: Bool
    @State var serverURLError: String?
    @State var testResultText: String?
    @State var testInFlight: Bool = false

    /// Re-entrancy guard so a rapid double-tap on Save in add-mode
    /// can't enqueue two `addProfile` Tasks (each writing a different
    /// keychain entry + producing two list rows). Mirrors WI-4a stub.
    @State var saveInFlight: Bool = false

    init(
        viewModel: WebDAVProfileListViewModel,
        existing: WebDAVServerProfile?
    ) {
        self.viewModel = viewModel
        self.existing = existing

        if let existing {
            _profileID = State(initialValue: existing.id)
            _name = State(initialValue: existing.name)
            _serverURL = State(initialValue: existing.serverURL)
            _username = State(initialValue: existing.username)
            // Codex round-1 Low fix [6]: defer the keychain probe to
            // an async .task so it goes through the VM's injected
            // KeychainService (via profileStore.readPassword) instead
            // of constructing a fresh keychain in the view.
            _isPasswordSaved = State(initialValue: false)
        } else {
            _profileID = State(initialValue: UUID())
            _name = State(initialValue: "")
            _serverURL = State(initialValue: "https://")
            _username = State(initialValue: "")
            _isPasswordSaved = State(initialValue: false)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                endpointSection
                passwordSection
                testConnectionSection
            }
            .navigationTitle(existing == nil ? "Add WebDAV Server" : "Edit WebDAV Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("webdavProfileEditCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || saveInFlight)
                    .accessibilityIdentifier("webdavProfileEditSave")
                }
            }
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
            .accessibilityIdentifier("webdavProfileEditSheet")
            .task {
                // Codex round-1 Low fix [6]: probe keychain through the
                // VM (which uses its injected profileStore + KeychainService)
                // rather than constructing a fresh KeychainService in the
                // view. Keeps test injection consistent.
                if let existing {
                    let stored = await viewModel.readStoredPassword(for: existing.id)
                    isPasswordSaved = (stored?.isEmpty == false)
                }
            }
        }
    }

    // MARK: - Save gating

    var canSave: Bool {
        // Server URL must pass the shared validator (Codex round-1 High
        // fix [1]: previously accepted `https://` with no host).
        guard WebDAVProfileListViewModel.validatedServerURL(from: serverURL) != nil else {
            return false
        }
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else { return false }
        // Name CAN be blank — we auto-fill from the URL hostname on save
        // (Codex round-1 Medium fix [5], matches plan edge case (e)).
        // Add-mode requires the user to type a password before Save —
        // otherwise the keychain write below would store an empty string,
        // and Test Connection would fail with "password missing". Edit-
        // mode allows save without password changes (existing keychain
        // entry is reused).
        if existing == nil {
            guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        return true
    }

    // MARK: - Actions

    func save() async {
        guard !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Codex round-1 High fix [1]: shared validator (require scheme +
        // host + http/https). Save MUST agree with canSave gating.
        guard let url = WebDAVProfileListViewModel.validatedServerURL(from: trimmedURL) else {
            serverURLError = "URL must use http:// or https:// and include a host."
            return
        }
        // Codex round-1 Medium fix [5]: when name is blank, auto-fill
        // from the URL hostname before persistence. Matches plan edge
        // case (e). `displayName` already has a hostname fallback for
        // empty-name reads, but persisting the hostname makes the
        // intent explicit + means the list view's row shows the
        // hostname uniformly regardless of which read path renders it.
        let resolvedName: String
        if trimmedName.isEmpty, let host = url.host, !host.isEmpty {
            resolvedName = host
        } else {
            resolvedName = trimmedName
        }
        let profile = WebDAVServerProfile(
            id: profileID,
            name: resolvedName,
            serverURL: trimmedURL,
            username: trimmedUser
        )
        if existing == nil {
            await viewModel.addProfile(profile, password: password)
        } else {
            await viewModel.updateProfile(profile)
        }
        if viewModel.editorError == nil {
            dismiss()
        }
    }

    func saveKey() async {
        await viewModel.savePassword(password, forID: profileID)
        if viewModel.editorError == nil {
            isPasswordSaved = !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            password = ""
        }
    }

    func deleteKey() async {
        await viewModel.deletePassword(forID: profileID)
        if viewModel.editorError == nil {
            isPasswordSaved = false
            password = ""
        }
    }

    func runTest() async {
        testInFlight = true
        defer { testInFlight = false }

        // Test Connection uses the form's current password in edit-mode
        // ONLY if the user has typed a fresh password. Otherwise we read
        // the stored keychain entry through the VM (Codex round-1 Low
        // fix [6]: keep injection consistent — no direct KeychainService
        // in the view).
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidatePassword: String
        if !trimmedPassword.isEmpty {
            candidatePassword = trimmedPassword
        } else if existing != nil, isPasswordSaved {
            candidatePassword = await viewModel.readStoredPassword(for: profileID) ?? ""
        } else {
            candidatePassword = ""
        }

        let result = await viewModel.testConnection(
            serverURL: serverURL,
            username: username,
            password: candidatePassword
        )
        switch result {
        case .success:
            testResultText = "Connected — the WebDAV server responded successfully."
        case .failure(let error):
            testResultText = "Failed: \(error.localizedDescription)"
        }
    }
}
