// Purpose: WebDAV server profile editor sheet — Feature #52 WI-4a STUB.
// WI-4a ships the list UI + a placeholder editor body so the Add /
// Edit flow is reachable end-to-end. WI-4b replaces this stub with the
// full form (Name / Server URL / Username / Password + Save / Test
// Connection, mirroring `AIProviderEditSheet`).
//
// Per WI-4a plan: "New profile add path lands in a stub editor that
// just writes a name placeholder." The add-mode Save button creates a
// `WebDAVServerProfile` with placeholder name and empty URL/username
// so the list-view slice can show a new row + exercise the swipe-
// delete path WITHOUT the full form. The empty URL/username naturally
// fails validation if the user tries to back up — that's the WI-4a
// tradeoff; WI-4b's full editor unblocks usable saves.
//
// Edit-mode is cancel-only in WI-4a (the full form lands in WI-4b).
//
// @coordinates-with: WebDAVServerProfileListView.swift,
//   WebDAVServerProfile.swift, WebDAVServerProfileStore.swift

import SwiftUI

/// Stub editor for a `WebDAVServerProfile`. WI-4b replaces this body
/// with the full add/edit form.
struct WebDAVServerProfileEditSheet: View {
    /// Non-nil = edit-mode (existing profile passed in). Nil = add-new.
    let existing: WebDAVServerProfile?

    /// Store the add-mode Save button writes the placeholder profile to.
    /// Defaults to the production singleton; tests override.
    let profileStore: WebDAVServerProfileStore

    @Environment(\.dismiss) private var dismiss

    /// Re-entrancy guard for the add-mode Add button. Codex round-2
    /// Medium: a rapid double-tap before dismissal could enqueue two
    /// `Task`s, each with a fresh `UUID()`, producing duplicate
    /// placeholder rows. Disabling the button after first tap is the
    /// minimal idiomatic fix (the equivalent of an `isInFlight` flag).
    @State private var isAdding = false

    /// Placeholder name suggested in add-mode. Stored as the name on
    /// the persisted profile so the list shows something recognisable
    /// until WI-4b's full editor lets the user rename.
    static let addPlaceholderName = "New WebDAV Server"

    init(
        existing: WebDAVServerProfile?,
        profileStore: WebDAVServerProfileStore = .shared
    ) {
        self.existing = existing
        self.profileStore = profileStore
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "wrench.adjustable")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text(headlineCopy)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(bodyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("webdavProfileEditCancel")
                }
                // Add-mode only: write a placeholder profile so the list
                // gains a row and downstream WIs (4b editor, swipe delete,
                // active selection) are reachable from a fresh-install state.
                if existing == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            guard !isAdding else { return }
                            isAdding = true
                            let placeholder = WebDAVServerProfile(
                                id: UUID(),
                                name: Self.addPlaceholderName,
                                serverURL: "",
                                username: ""
                            )
                            Task {
                                await profileStore.upsert(placeholder)
                                dismiss()
                            }
                        }
                        .disabled(isAdding)
                        .accessibilityIdentifier("webdavProfileEditAdd")
                    }
                }
            }
            .accessibilityIdentifier("webdavProfileEditSheet")
        }
    }

    // MARK: - Copy

    private var navigationTitle: String {
        existing == nil ? "Add WebDAV Server" : "Edit WebDAV Server"
    }

    private var headlineCopy: String {
        existing == nil
            ? "New server (placeholder)"
            : "Edit \(existing?.displayName ?? "server") (placeholder)"
    }

    private var bodyCopy: String {
        if existing == nil {
            return "Tap Add to create a placeholder row in the list. WI-4b ships the full editor (Name, Server URL, Username, Password, Test Connection) so you can configure the server. Until then, this row is non-functional for backup; the single-server form on the WebDAV Backup screen remains the working credentials path."
        } else {
            return "The full editor (Name, Server URL, Username, Password, Test Connection) lands in WI-4b. WI-4a ships the list + navigation; this stub keeps the Edit flow reachable from the list."
        }
    }
}
