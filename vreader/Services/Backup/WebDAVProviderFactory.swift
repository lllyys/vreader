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
