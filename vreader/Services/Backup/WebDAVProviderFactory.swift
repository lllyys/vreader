// Purpose: Builds a fully-wired WebDAVProvider from the active WebDAV
// server profile. Used by WebDAVSettingsView + LibraryView to construct
// the provider on demand without leaking storage details into the view.
//
// Feature #52 WI-5: the legacy flat-keychain variants
// (`make(keychain:)` and `makeRequestBuilder(keychain:)`) have been
// removed. The two production call sites that used them
// (`WebDAVSettingsView.refreshBackupVMIfNeeded` and `LibraryView`'s
// row-tap observer) now read credentials from the active profile via
// `WebDAVServerProfileStore`. The migrator (`WebDAVProfileMigrator`)
// ensures existing users land in the multi-profile world with a
// "Default" profile mirroring their pre-#52 flat-keychain credentials.
//
// @coordinates-with: WebDAVProvider.swift, BackupDataCollector.swift,
//   BackupDataRestorer.swift, WebDAVServerProfileStore.swift,
//   WebDAVProfileMigrator.swift, WebDAVSettingsView.swift, LibraryView.swift

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

    // MARK: - Profile-store variants (Feature #52 WI-3, sole path after WI-5)
    //
    // The variants below read credentials from `WebDAVServerProfileStore`
    // — the multi-profile source of truth. They are async because store
    // reads cross an actor boundary.

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

    /// Builds the lazy-download request builder from the active
    /// WebDAV profile. Used by the row-tap → enqueue path
    /// (feature #47 WI-6) so taps on remote-only library rows don't
    /// have to round-trip a full `WebDAVProvider`.
    ///
    /// Throws `missingCredentials` when no active profile is set OR
    /// the active profile has empty fields OR its password slot is
    /// empty; throws `invalidServerURL` when the active profile's
    /// `serverURL` doesn't parse to a `URL` with a scheme.
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
