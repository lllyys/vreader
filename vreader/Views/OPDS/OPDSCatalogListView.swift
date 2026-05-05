// Purpose: View for managing saved OPDS catalog URLs.
// Users can add, edit, and delete catalog entries, then browse them.
//
// Key decisions:
// - Catalogs stored in UserDefaults (lightweight, no SwiftData needed).
// - Each catalog has a name, URL, and optional credentials.
// - Tapping a catalog navigates to OPDSBrowserView.
// - Add/edit uses an alert with text fields.
//
// @coordinates-with: OPDSModels.swift, OPDSBrowserView.swift, LibraryView.swift

import SwiftUI

/// Manages the user's list of saved OPDS catalogs.
struct OPDSCatalogListView: View {
    @State private var catalogs: [OPDSSavedCatalog] = []
    @State private var isShowingAddSheet = false
    @State private var editingCatalog: OPDSSavedCatalog?

    // Add/edit form fields
    @State private var formName = ""
    @State private var formURL = ""
    @State private var formUsername = ""
    @State private var formPassword = ""

    private static let storageKey = "opds.savedCatalogs"
    /// Bug #133: passwords are stored in Keychain, keyed by catalog UUID.
    /// UserDefaults persists everything except the password.
    private let keychain = KeychainService(serviceIdentifier: "com.vreader.opds")

    var body: some View {
        Group {
            if catalogs.isEmpty {
                emptyCatalogState
            } else {
                catalogList
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    resetForm()
                    editingCatalog = nil
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add catalog")
                .accessibilityIdentifier("opdsAddCatalog")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            addEditSheet
        }
        .onAppear {
            loadCatalogs()
        }
    }

    // MARK: - Subviews

    private var emptyCatalogState: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No OPDS Catalogs")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add an OPDS catalog server to browse and download books.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                resetForm()
                editingCatalog = nil
                isShowingAddSheet = true
            } label: {
                Label("Add Catalog", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("opdsAddCatalogEmpty")
        }
        .accessibilityIdentifier("opdsEmptyState")
    }

    private var catalogList: some View {
        List {
            ForEach(catalogs) { catalog in
                NavigationLink {
                    if let url = URL(string: catalog.url) {
                        let creds: OPDSCredentials? = {
                            guard let user = catalog.username,
                                  let pass = catalog.password,
                                  !user.isEmpty else { return nil }
                            return OPDSCredentials(username: user, password: pass)
                        }()
                        OPDSBrowserView(
                            catalogURL: url,
                            catalogName: catalog.name,
                            credentials: creds
                        )
                    } else {
                        Text("Invalid catalog URL")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(catalog.name)
                            .font(.body)
                        Text(catalog.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
                .contextMenu {
                    Button {
                        formName = catalog.name
                        formURL = catalog.url
                        formUsername = catalog.username ?? ""
                        formPassword = catalog.password ?? ""
                        editingCatalog = catalog
                        isShowingAddSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        deleteCatalog(catalog)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .accessibilityIdentifier("opdsCatalog_\(catalog.id)")
            }
            .onDelete { indexSet in
                for index in indexSet {
                    deleteCatalog(catalogs[index])
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("opdsCatalogList")
    }

    private var addEditSheet: some View {
        NavigationStack {
            Form {
                Section("Catalog Info") {
                    TextField("Name", text: $formName)
                        .accessibilityIdentifier("opdsCatalogNameField")
                    TextField("URL", text: $formURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("opdsCatalogURLField")
                }

                Section("Authentication (Optional)") {
                    TextField("Username", text: $formUsername)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("opdsCatalogUsernameField")
                    SecureField("Password", text: $formPassword)
                        .accessibilityIdentifier("opdsCatalogPasswordField")
                }
            }
            .navigationTitle(editingCatalog == nil ? "Add Catalog" : "Edit Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingAddSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCatalog()
                        isShowingAddSheet = false
                    }
                    .disabled(formName.isEmpty || formURL.isEmpty)
                    .accessibilityIdentifier("opdsCatalogSaveButton")
                }
            }
        }
    }

    // MARK: - Persistence (Bug #133: passwords in Keychain, rest in UserDefaults)

    private func loadCatalogs() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([OPDSSavedCatalog].self, from: data) else {
            catalogs = []
            return
        }

        // Migrate any legacy plaintext entries: move password to Keychain,
        // rewrite UserDefaults with password cleared. One-time per catalog.
        var didMigrate = false
        var migrated: [OPDSSavedCatalog] = []
        for var c in decoded {
            if let plaintext = c.password, !plaintext.isEmpty {
                try? keychain.saveString(plaintext, forAccount: c.id.uuidString)
                c.password = nil
                didMigrate = true
            }
            // Hydrate password from Keychain (legacy or already-migrated).
            if let stored = try? keychain.readString(forAccount: c.id.uuidString),
               !stored.isEmpty {
                c.password = stored
            }
            migrated.append(c)
        }
        catalogs = migrated
        if didMigrate {
            saveCatalogs()  // Rewrite UserDefaults with passwords stripped.
        }
    }

    private func saveCatalogs() {
        // Write to Keychain first; only UserDefaults sees a password-free copy.
        for c in catalogs {
            if let pw = c.password, !pw.isEmpty {
                try? keychain.saveString(pw, forAccount: c.id.uuidString)
            } else {
                try? keychain.delete(forAccount: c.id.uuidString)
            }
        }
        let stripped = catalogs.map { c -> OPDSSavedCatalog in
            var copy = c
            copy.password = nil
            return copy
        }
        if let data = try? JSONEncoder().encode(stripped) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func saveCatalog() {
        let trimmedURL = formURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = formName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing = editingCatalog,
           let index = catalogs.firstIndex(where: { $0.id == editing.id }) {
            catalogs[index] = OPDSSavedCatalog(
                id: editing.id,
                name: trimmedName,
                url: trimmedURL,
                username: formUsername.isEmpty ? nil : formUsername,
                password: formPassword.isEmpty ? nil : formPassword
            )
        } else {
            let newCatalog = OPDSSavedCatalog(
                name: trimmedName,
                url: trimmedURL,
                username: formUsername.isEmpty ? nil : formUsername,
                password: formPassword.isEmpty ? nil : formPassword
            )
            catalogs.append(newCatalog)
        }

        saveCatalogs()
    }

    private func deleteCatalog(_ catalog: OPDSSavedCatalog) {
        // Bug #133: clear the Keychain entry too — saveCatalogs only writes
        // for remaining catalogs, so the deleted catalog's password would
        // leak otherwise.
        try? keychain.delete(forAccount: catalog.id.uuidString)
        catalogs.removeAll { $0.id == catalog.id }
        saveCatalogs()
    }

    private func resetForm() {
        formName = ""
        formURL = ""
        formUsername = ""
        formPassword = ""
    }
}
