// Purpose: Form-section view builders for `WebDAVServerProfileEditSheet`.
// Split out of the main sheet file (Feature #52 WI-4b) to keep both under
// the ~300-line guideline. Mirrors `AIProviderEditSheet+Sections.swift`.
//
// @coordinates-with: WebDAVServerProfileEditSheet.swift,
//   WebDAVProfileListViewModel+Editor.swift

import SwiftUI

extension WebDAVServerProfileEditSheet {

    // MARK: - Name

    var nameSection: some View {
        Section("Name") {
            TextField("e.g. \"Home Nextcloud\" or \"Work Synology\"", text: $name)
                .autocorrectionDisabled()
                .accessibilityIdentifier("webdavProfileEditName")
        }
    }

    // MARK: - Endpoint (server URL + username)

    @ViewBuilder
    var endpointSection: some View {
        Section {
            HStack {
                Text("Server URL")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("https://dav.example.com/", text: $serverURL)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("webdavProfileEditServerURL")
                    .onChange(of: serverURL) { _, _ in
                        // Codex round-1 High fix [1]: shared validator
                        // (scheme http/https + non-empty host) — used by
                        // canSave, save, and testConnection too, so all
                        // four paths agree.
                        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed == "https://" || trimmed == "http://" {
                            serverURLError = nil
                        } else if WebDAVProfileListViewModel.validatedServerURL(from: trimmed) == nil {
                            serverURLError = "URL must use http:// or https:// and include a host."
                        } else {
                            serverURLError = nil
                        }
                    }
            }
            if let error = serverURLError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("webdavProfileEditServerURLError")
            }

            HStack {
                Text("Username")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("alice", text: $username)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("webdavProfileEditUsername")
            }
        } header: {
            Text("Endpoint")
        } footer: {
            // Bug #110: WebDAV accepts http (Tailscale `*.ts.net`, NAS
            // local hostnames). NSAllowsArbitraryLoads covers the
            // transport — this footer reassures the user that http is
            // intentional.
            Text("HTTPS is recommended. HTTP is accepted for Tailscale and local-network WebDAV servers.")
                .accessibilityIdentifier("webdavProfileEditEndpointHint")
        }
    }

    // MARK: - Password

    @ViewBuilder
    var passwordSection: some View {
        Section("Password") {
            HStack {
                SecureField(
                    existing == nil ? "Enter Password" : "Enter new password to update",
                    text: $password
                )
                .textContentType(.password)
                .autocorrectionDisabled()
                .accessibilityIdentifier("webdavProfileEditPassword")
                if isPasswordSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Password saved")
                }
            }

            // Bug #184 pattern: add-mode hides the explicit Save Key /
            // Delete Key buttons (the atomic addProfile path is the only
            // keychain-write path in add-mode — see Editor extension).
            // Edit-mode shows the buttons so the user can rotate / drop
            // the password without re-creating the profile.
            if existing != nil {
                HStack {
                    Button("Save Password") {
                        Task { await saveKey() }
                    }
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("webdavProfileEditSavePasswordButton")

                    if isPasswordSaved {
                        Button("Delete Password", role: .destructive) {
                            Task { await deleteKey() }
                        }
                        .accessibilityIdentifier("webdavProfileEditDeletePasswordButton")
                    }
                }
            } else {
                Text("The password is stored only after the profile is saved. Enter the password above, then tap Add at the top of this sheet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("webdavProfileEditSavePasswordNote")
            }
        }
    }

    // MARK: - Test Connection

    @ViewBuilder
    var testConnectionSection: some View {
        Section("Connection") {
            // Bug #184 pattern: add-mode hides the Test Connection button
            // because the keychain entry doesn't exist until the atomic
            // addProfile completes on top-level Save. Edit-mode shows the
            // button.
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
                .disabled(testInFlight || (!isPasswordSaved && password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .accessibilityIdentifier("webdavProfileEditTestConnection")

                if let result = testResultText {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("Connected") ? .green : .red)
                        .accessibilityIdentifier("webdavProfileEditTestResult")
                }
            } else {
                Text("Save the profile first, then return here to test the connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("webdavProfileEditTestConnectionNote")
            }
        }
    }
}
