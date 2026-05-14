// Purpose: Builds a fully-wired WebDAVProvider from Keychain credentials and
// the live PersistenceActor. Used by WebDAVSettingsView to construct the
// provider on demand without leaking storage details into the view.
//
// @coordinates-with: WebDAVProvider.swift, BackupDataCollector.swift,
//   BackupDataRestorer.swift, KeychainService.swift, WebDAVSettingsView.swift

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Errors thrown when constructing a WebDAVProvider from saved credentials.
enum WebDAVProviderFactoryError: Error, Sendable, Equatable {
    case missingCredentials
    case invalidServerURL(String)
}

enum WebDAVProviderFactory {

    static let serverURLAccount = "com.vreader.webdav.serverURL"
    static let usernameAccount = "com.vreader.webdav.username"
    static let passwordAccount = "com.vreader.webdav.password"

    /// Constructs a fully-wired WebDAVProvider for the given persistence actor.
    /// Reads credentials from Keychain. Throws if credentials are missing or invalid.
    ///
    /// `bookImporter` enables feature #46's materializing restore. When omitted
    /// (legacy callers / tests), restore falls back to v1-format behavior:
    /// metadata-only, books silently skipped if missing locally. Production
    /// callers (from `VReaderApp` via `WebDAVSettingsView`) pass the live
    /// `BookImporter` so backup blobs land on a fresh device.
    @MainActor
    static func make(
        persistence: PersistenceActor,
        keychain: KeychainService = KeychainService(),
        defaults: UserDefaults = .standard,
        perBookSettingsBaseURL: URL = standardPerBookSettingsBaseURL,
        appVersion: String = currentAppVersion(),
        deviceName: String = currentDeviceName(),
        bookImporter: (any BookImporting)? = nil
    ) throws -> WebDAVProvider {
        guard
            let serverURL = try? keychain.readString(forAccount: serverURLAccount),
            !serverURL.isEmpty,
            let username = try? keychain.readString(forAccount: usernameAccount),
            !username.isEmpty,
            let password = try? keychain.readString(forAccount: passwordAccount),
            !password.isEmpty
        else {
            throw WebDAVProviderFactoryError.missingCredentials
        }

        guard let url = URL(string: serverURL), url.scheme != nil else {
            throw WebDAVProviderFactoryError.invalidServerURL(serverURL)
        }

        let client = WebDAVClient(serverURL: url, username: username, password: password)
        let collector = BackupDataCollector(
            persistence: persistence,
            defaults: defaults,
            perBookSettingsBaseURL: perBookSettingsBaseURL
        )
        let restorer = BackupDataRestorer(
            persistence: persistence,
            defaults: defaults,
            perBookSettingsBaseURL: perBookSettingsBaseURL
        )
        return WebDAVProvider(
            transport: client,
            dataCollector: collector,
            dataRestorer: restorer,
            deviceName: deviceName,
            appVersion: appVersion,
            bookImporter: bookImporter
        )
    }

    /// Builds just the lazy-download request builder from saved
    /// credentials. Used by the row-tap → enqueue path (#47 WI-6) so
    /// taps on remote-only rows don't have to round-trip a full
    /// `WebDAVProvider`. Throws `missingCredentials` /
    /// `invalidServerURL` for the same reasons `make(...)` does.
    @MainActor
    static func makeRequestBuilder(
        keychain: KeychainService = KeychainService()
    ) throws -> WebDAVDownloadRequestBuilder {
        guard
            let serverURL = try? keychain.readString(forAccount: serverURLAccount),
            !serverURL.isEmpty,
            let username = try? keychain.readString(forAccount: usernameAccount),
            !username.isEmpty,
            let password = try? keychain.readString(forAccount: passwordAccount),
            !password.isEmpty
        else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        guard let url = URL(string: serverURL), url.scheme != nil else {
            throw WebDAVProviderFactoryError.invalidServerURL(serverURL)
        }
        let client = WebDAVClient(serverURL: url, username: username, password: password)
        return WebDAVDownloadRequestBuilder(client: client)
    }

    // MARK: - Feature #52 WI-3 — profile-store variants
    //
    // The variants below read credentials from `WebDAVServerProfileStore`
    // (the new multi-profile source of truth) instead of the flat-keychain
    // triplet. They are async because store reads cross an actor boundary.
    //
    // Migration plan: WI-3 introduces these variants alongside the legacy
    // sync variants. WI-4a/4b ship the UI that lets users add/edit profiles.
    // WI-5 migrates the legacy call sites (`WebDAVSettingsView`,
    // `LibraryView`) to these async variants and drops the legacy sync
    // versions. Until then, both paths coexist; the migrator
    // (`WebDAVProfileMigrator`) ensures the store contains a "Default"
    // profile mirroring the legacy flat-keychain credentials, so reads
    // from either source see the same data.

    /// Constructs a fully-wired `WebDAVProvider` from the active profile in
    /// `WebDAVServerProfileStore`. Throws `missingCredentials` when there
    /// is no active profile or the resolved profile has empty fields /
    /// missing password. Throws `invalidServerURL` when the profile's
    /// `serverURL` doesn't parse to a `URL` with a scheme.
    @MainActor
    static func make(
        persistence: PersistenceActor,
        profileStore: WebDAVServerProfileStore,
        defaults: UserDefaults = .standard,
        perBookSettingsBaseURL: URL = standardPerBookSettingsBaseURL,
        appVersion: String = currentAppVersion(),
        deviceName: String = currentDeviceName(),
        bookImporter: (any BookImporting)? = nil
    ) async throws -> WebDAVProvider {
        guard let profile = await profileStore.activeProfile() else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        guard !profile.serverURL.isEmpty,
              !profile.username.isEmpty else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        let password = (try await profileStore.readPassword(for: profile.id)) ?? ""
        guard !password.isEmpty else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        guard let url = URL(string: profile.serverURL), url.scheme != nil else {
            throw WebDAVProviderFactoryError.invalidServerURL(profile.serverURL)
        }
        let client = WebDAVClient(serverURL: url, username: profile.username, password: password)
        let collector = BackupDataCollector(
            persistence: persistence,
            defaults: defaults,
            perBookSettingsBaseURL: perBookSettingsBaseURL
        )
        let restorer = BackupDataRestorer(
            persistence: persistence,
            defaults: defaults,
            perBookSettingsBaseURL: perBookSettingsBaseURL
        )
        return WebDAVProvider(
            transport: client,
            dataCollector: collector,
            dataRestorer: restorer,
            deviceName: deviceName,
            appVersion: appVersion,
            bookImporter: bookImporter
        )
    }

    /// Profile-store-backed variant of `makeRequestBuilder(keychain:)`.
    /// Same error contract as the legacy variant: throws
    /// `missingCredentials` when there is no active profile or its
    /// password slot is empty; throws `invalidServerURL` when the
    /// profile's `serverURL` doesn't parse.
    @MainActor
    static func makeRequestBuilder(
        profileStore: WebDAVServerProfileStore
    ) async throws -> WebDAVDownloadRequestBuilder {
        guard let profile = await profileStore.activeProfile() else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        guard !profile.serverURL.isEmpty,
              !profile.username.isEmpty else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        let password = (try await profileStore.readPassword(for: profile.id)) ?? ""
        guard !password.isEmpty else {
            throw WebDAVProviderFactoryError.missingCredentials
        }
        guard let url = URL(string: profile.serverURL), url.scheme != nil else {
            throw WebDAVProviderFactoryError.invalidServerURL(profile.serverURL)
        }
        let client = WebDAVClient(serverURL: url, username: profile.username, password: password)
        return WebDAVDownloadRequestBuilder(client: client)
    }

    /// Default per-book-settings storage location (mirrors ReaderContainerView).
    static let standardPerBookSettingsBaseURL: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerBookSettings", isDirectory: true)
    }()

    static func currentAppVersion() -> String {
        let dict = Bundle.main.infoDictionary
        let v = dict?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let b = dict?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    @MainActor
    static func currentDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Device"
        #endif
    }
}
