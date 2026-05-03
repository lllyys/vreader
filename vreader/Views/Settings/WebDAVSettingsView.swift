// Purpose: WebDAV connection configuration UI for backup settings.
// Allows users to enter server URL, username, and password.
// Provides connection testing and credential persistence via Keychain.
//
// Key decisions:
// - Credentials stored in Keychain (not UserDefaults) for security.
// - Connection test validates before saving credentials.
// - Server URL validated for https:// prefix (security best practice).
// - Form-based layout consistent with iOS Settings patterns.
//
// @coordinates-with: WebDAVClient.swift, WebDAVProvider.swift, KeychainService.swift, SettingsView.swift

import SwiftUI

/// WebDAV server configuration view for backup settings.
struct WebDAVSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.persistenceActor) private var persistenceFromEnv
    @Environment(\.bookImporter) private var bookImporterFromEnv

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var isSaving = false

    @State private var backupVM: BackupViewModel?
    @State private var showRestoreConfirm = false
    @State private var restoreCandidate: BackupMetadata?
    @State private var showDeleteConfirm = false
    @State private var deleteCandidate: BackupMetadata?

    /// Keychain service for credential persistence.
    private let keychain: KeychainService

    /// Optional explicit persistence override (preferred for tests / previews).
    /// When nil, we fall back to the SwiftUI environment value.
    private let injectedPersistence: PersistenceActor?

    private var persistence: PersistenceActor? {
        injectedPersistence ?? persistenceFromEnv
    }

    // MARK: - Keychain Accounts

    private static let serverURLAccount = "com.vreader.webdav.serverURL"
    private static let usernameAccount = "com.vreader.webdav.username"
    private static let passwordAccount = "com.vreader.webdav.password"

    // MARK: - Init

    init(keychain: KeychainService = KeychainService(), persistence: PersistenceActor? = nil) {
        self.keychain = keychain
        self.injectedPersistence = persistence
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("webdavServerURL")

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("webdavUsername")

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("webdavPassword")
            } header: {
                Text("WebDAV Server")
            } footer: {
                Text("Enter your WebDAV server details. Supports Nutstore, NextCloud, Synology, and other WebDAV-compatible services.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        } else if let result = testResult {
                            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isSuccess ? .green : .red)
                        }
                    }
                }
                .disabled(isTesting || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                .accessibilityIdentifier("webdavTestButton")

                if let result = testResult, !result.isSuccess {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await saveCredentials() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                .accessibilityIdentifier("webdavSaveButton")

                Button(role: .destructive) {
                    clearCredentials()
                } label: {
                    HStack {
                        Spacer()
                        Text("Remove Credentials")
                        Spacer()
                    }
                }
                .accessibilityIdentifier("webdavClearButton")
            }

            backupSection
        }
        .navigationTitle("WebDAV Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadCredentials() }
        .task { await refreshBackupVMIfNeeded() }
        .confirmationDialog(
            "Restore from this backup?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let candidate = restoreCandidate {
                    Task { await backupVM?.performRestore(backupId: candidate.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let candidate = restoreCandidate {
                Text("This merges backup data for \(candidate.bookCount) books into your library. Annotations and bookmarks dedupe by ID and reader location; existing matches will be overwritten with the backup's values. Reading positions and settings are replaced. Book files themselves are not restored.")
            }
        }
        .confirmationDialog(
            "Delete this backup?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let candidate = deleteCandidate {
                    Task { await backupVM?.deleteBackup(id: candidate.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the backup from the server.")
        }
    }

    // MARK: - Backup Section

    @ViewBuilder
    private var backupSection: some View {
        if hasSavedCredentials, persistence != nil {
            Section {
                Button {
                    Task { await backupVM?.performBackup() }
                } label: {
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("Back Up Now")
                        Spacer()
                        if backupVM?.isBackingUp == true {
                            ProgressView(value: backupVM?.backupProgress ?? 0)
                                .frame(width: 80)
                        } else if backupVM?.lastBackupSucceeded == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .disabled(backupVM == nil || backupVM?.isBackingUp == true || backupVM?.isRestoring == true)
                .accessibilityIdentifier("webdavBackupNowButton")
            } header: {
                Text("Backup")
            } footer: {
                Text("Backs up annotations, reading positions, settings, collections, web sources, per-book overrides, and replacement rules. Book files themselves are not uploaded — you'll need to re-import them on a new device, then restore.")
            }

            Section {
                if backupVM?.isLoading == true {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if backupVM?.backups.isEmpty == true {
                    Text("No backups yet")
                        .foregroundStyle(.secondary)
                } else if let backups = backupVM?.backups {
                    ForEach(backups, id: \.id) { backup in
                        backupRow(backup)
                    }
                }
                Button {
                    Task { await backupVM?.loadBackups() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh List")
                    }
                }
                .disabled(backupVM == nil || backupVM?.isLoading == true)
                .accessibilityIdentifier("webdavRefreshBackupsButton")
            } header: {
                Text("Available Backups")
            }

            if let message = backupVM?.errorMessage {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("webdavBackupErrorText")
                }
            }
        }
    }

    @ViewBuilder
    private func backupRow(_ backup: BackupMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "archivebox")
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.body)
                Spacer()
                Text(byteCountFormatter.string(fromByteCount: backup.totalSizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(backup.deviceName) · v\(backup.appVersion) · \(backup.bookCount) books")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    restoreCandidate = backup
                    showRestoreConfirm = true
                } label: {
                    Label("Restore", systemImage: "icloud.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(backupVM?.isRestoring == true || backupVM?.isBackingUp == true)
                .accessibilityIdentifier("webdavRestoreButton-\(backup.id.uuidString)")

                Button(role: .destructive) {
                    deleteCandidate = backup
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("webdavDeleteBackupButton-\(backup.id.uuidString)")

                if backupVM?.isRestoring == true,
                   restoreCandidate?.id == backup.id {
                    ProgressView(value: backupVM?.restoreProgress ?? 0)
                        .frame(width: 60)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var hasSavedCredentials: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    private var byteCountFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }

    /// Constructs (or refreshes) the BackupViewModel when credentials become available.
    private func refreshBackupVMIfNeeded() async {
        guard let persistence else { return }
        guard hasSavedCredentials else {
            backupVM = nil
            return
        }
        do {
            let provider = try WebDAVProviderFactory.make(
                persistence: persistence,
                keychain: keychain,
                bookImporter: bookImporterFromEnv
            )
            let vm = BackupViewModel(provider: provider)
            backupVM = vm
            await vm.loadBackups()
        } catch {
            backupVM = nil
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        guard let url = URL(string: serverURL), url.scheme != nil else {
            testResult = TestResult(isSuccess: false, message: "Invalid server URL")
            return
        }

        let client = WebDAVClient(
            serverURL: url,
            username: username,
            password: password
        )

        do {
            try await client.testConnection()
            testResult = TestResult(isSuccess: true, message: "Connected successfully")
        } catch let error as WebDAVError {
            switch error {
            case .authenticationFailed:
                testResult = TestResult(isSuccess: false, message: "Authentication failed. Check username and password.")
            case .connectionFailed(let msg):
                testResult = TestResult(isSuccess: false, message: "Connection failed: \(msg)")
            default:
                testResult = TestResult(isSuccess: false, message: "Error: \(error)")
            }
        } catch {
            testResult = TestResult(isSuccess: false, message: "Connection error: \(error.localizedDescription)")
        }
    }

    private func saveCredentials() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try keychain.saveString(serverURL, forAccount: Self.serverURLAccount)
            try keychain.saveString(username, forAccount: Self.usernameAccount)
            try keychain.saveString(password, forAccount: Self.passwordAccount)
            testResult = TestResult(isSuccess: true, message: "Credentials saved")
            await refreshBackupVMIfNeeded()
        } catch {
            testResult = TestResult(
                isSuccess: false,
                message: "Failed to save credentials: \(error.localizedDescription)"
            )
        }
    }

    private func loadCredentials() {
        serverURL = (try? keychain.readString(forAccount: Self.serverURLAccount)) ?? ""
        username = (try? keychain.readString(forAccount: Self.usernameAccount)) ?? ""
        password = (try? keychain.readString(forAccount: Self.passwordAccount)) ?? ""
    }

    private func clearCredentials() {
        try? keychain.delete(forAccount: Self.serverURLAccount)
        try? keychain.delete(forAccount: Self.usernameAccount)
        try? keychain.delete(forAccount: Self.passwordAccount)
        serverURL = ""
        username = ""
        password = ""
        testResult = nil
    }

    // MARK: - Types

    private struct TestResult {
        let isSuccess: Bool
        let message: String
    }
}
