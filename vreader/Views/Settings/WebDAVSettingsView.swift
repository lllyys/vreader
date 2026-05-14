// Purpose: WebDAV backup settings screen — entry to the multi-profile
// server list + backup operations (Back Up Now, Restore, Refresh List).
//
// Feature #52 WI-5 (foundational cleanup): the legacy single-server
// credentials section + its flat-keychain reads/writes have been
// removed. Credential entry now lives exclusively in the multi-profile
// list view (WI-4a) + its editor sheet (WI-4b), reached via the
// "Servers" NavigationLink at the top of this screen. Backup operations
// (`Back Up Now`, `Restore`, `Refresh List`) construct their provider
// through `WebDAVProviderFactory.make(persistence:profileStore:)` —
// the async profile-aware variant from WI-3 — which reads the active
// profile from `WebDAVServerProfileStore.shared`.
//
// Key decisions:
// - Single source of truth: the active profile (via the store).
//   `refreshBackupVMIfNeeded` builds the provider from `profileStore`
//   and gates the backup section on whether an active profile exists.
//   No flat-keychain reads remain in this view.
// - Empty state (no active profile yet): the Servers nav-link section
//   stays visible at the top, the backup section is hidden, and the
//   inline footer copy directs the user to add a server.
// - `WebDAVProfileMigrator` (WI-2) handles the one-time migration of
//   legacy flat-keychain credentials into a `"Default"` profile at app
//   launch, so existing users hit this screen with their `Default`
//   profile already active.
//
// @coordinates-with: WebDAVProvider.swift, WebDAVProviderFactory.swift,
//   WebDAVServerProfileStore.swift, WebDAVServerProfileListView.swift,
//   SettingsView.swift, BackupViewModel.swift

import SwiftUI

/// WebDAV backup settings — Servers nav-link, Wi-Fi-only toggle, and
/// backup operations (Back Up Now / Restore / list).
struct WebDAVSettingsView: View {
    @Environment(\.persistenceActor) private var persistenceFromEnv
    @Environment(\.bookImporter) private var bookImporterFromEnv

    @State private var backupVM: BackupViewModel?
    @State private var showRestoreConfirm = false
    @State private var restoreCandidate: BackupMetadata?
    @State private var showDeleteConfirm = false
    @State private var deleteCandidate: BackupMetadata?
    /// Bound to SelectiveRestorePicker — set when the user taps
    /// "Restore selectively…", cleared on dismiss. Feature #47 WI-6.
    @State private var pickerCandidate: BackupMetadata?
    /// Whether the active WebDAV profile has all the fields (server URL,
    /// username, non-empty password) needed to construct a provider.
    /// Drives the backup section's visibility. Refreshed alongside
    /// `backupVM` whenever the store changes (WI-5: replaced
    /// flat-keychain `hasSavedCredentials` with active-profile check).
    @State private var hasActiveCredentials = false

    @Environment(\.persistenceActor) private var persistenceActor
    @Environment(\.webDAVNetworkPolicy) private var webDAVNetworkPolicy

    /// Optional explicit persistence override (preferred for tests / previews).
    /// When nil, we fall back to the SwiftUI environment value.
    private let injectedPersistence: PersistenceActor?

    private var persistence: PersistenceActor? {
        injectedPersistence ?? persistenceFromEnv
    }

    // MARK: - Init

    init(persistence: PersistenceActor? = nil) {
        self.injectedPersistence = persistence
    }

    // MARK: - Body

    var body: some View {
        Form {
            // Multi-profile entry point (WI-4a). After WI-5 this is the
            // ONLY credential-entry path — the legacy single-server
            // form on this screen has been removed.
            Section {
                NavigationLink {
                    WebDAVServerProfileListView(
                        viewModel: WebDAVProfileListViewModel()
                    )
                } label: {
                    HStack {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Servers")
                            Text("Manage saved WebDAV servers and switch the active one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("webdavServersNavLink")
            } header: {
                Text("Servers")
            } footer: {
                if hasActiveCredentials {
                    Text("Backup uses the currently-active server. Switch the active server in the list above.")
                } else {
                    Text("Add a WebDAV server above to enable backup.")
                }
            }

            // Feature #47 WI-6: Wi-Fi-only toggle for lazy book downloads.
            // Single source of truth — Wi-Fi-only also gates the
            // restore-all "Restore" button on cellular (WI-7
            // verification step).
            if let policy = webDAVNetworkPolicy {
                Section {
                    Toggle(isOn: Binding(
                        get: { policy.wifiOnly },
                        set: { policy.wifiOnly = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wi-Fi only for book downloads")
                            Text("When off, lazy book-blob downloads may use cellular data.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("webdavWiFiOnlyToggle")
                } header: {
                    Text("Network policy")
                }
            }

            backupSection
        }
        .navigationTitle("WebDAV Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshBackupVMIfNeeded()
        }
        // WI-5: refresh the backup VM + active-credentials state whenever
        // the profile store mutates (e.g., the user added their first
        // profile via the multi-server list, or switched the active one).
        .onReceive(NotificationCenter.default.publisher(for: .webdavProfilesDidChange)) { _ in
            Task { await refreshBackupVMIfNeeded() }
        }
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
        .sheet(item: $pickerCandidate) { backup in
            // Picker mounts as a fresh sheet per backup so the
            // BackupViewModel.loadManifest call fires from .task and
            // the user sees a spinner instead of stale state.
            NavigationStack {
                if let vm = backupVM, let persistence = persistenceActor {
                    SelectiveRestorePicker(
                        backup: backup,
                        viewModel: vm,
                        persistence: persistence,
                        dismiss: { pickerCandidate = nil }
                    )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading backup details…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Backup Section

    @ViewBuilder
    private var backupSection: some View {
        if hasActiveCredentials, persistence != nil {
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

                Button {
                    pickerCandidate = backup
                } label: {
                    Label("Pick…", systemImage: "checklist")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(backupVM?.isRestoring == true || backupVM?.isBackingUp == true)
                .accessibilityIdentifier("webdavSelectivePickerButton-\(backup.id.uuidString)")

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

    private var byteCountFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }

    /// Constructs (or refreshes) the BackupViewModel from the active
    /// WebDAV profile. WI-5: replaced the legacy
    /// `make(persistence:keychain:bookImporter:)` flat-keychain path
    /// with the async profile-store-backed variant from WI-3.
    ///
    /// Sets `hasActiveCredentials` to true only when the factory
    /// succeeds — the active profile exists, has all required fields,
    /// and its password slot is non-empty. Failures (no active profile,
    /// invalid URL, missing password) hide the backup section.
    private func refreshBackupVMIfNeeded() async {
        guard let persistence else {
            backupVM = nil
            hasActiveCredentials = false
            return
        }
        do {
            let provider = try await WebDAVProviderFactory.make(
                persistence: persistence,
                profileStore: WebDAVServerProfileStore.shared,
                bookImporter: bookImporterFromEnv
            )
            let vm = BackupViewModel(provider: provider)
            backupVM = vm
            hasActiveCredentials = true
            await vm.loadBackups()
        } catch {
            backupVM = nil
            hasActiveCredentials = false
        }
    }
}
