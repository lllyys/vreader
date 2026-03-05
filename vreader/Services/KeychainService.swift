// Purpose: Keychain CRUD for secrets and deviceId management.
// Uses kSecClassGenericPassword with a service identifier for namespacing.
// Provides string and data-level read/write/delete operations.
//
// Key decisions:
// - Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for credentials:
//   items are only accessible when the device is unlocked, and are excluded
//   from backups/device transfer (ThisDeviceOnly).
// - Save uses add-or-update pattern: tries SecItemAdd first, falls back to SecItemUpdate.
//   Update path includes kSecAttrAccessible to enforce accessibility on existing items.
// - Delete is idempotent: deleting a nonexistent item is a no-op.
// - deviceId uses atomic add-or-read to avoid race conditions on first access.
// - Struct-based for Sendable compliance. All methods are synchronous
//   (Keychain API is synchronous and thread-safe).
//
// @coordinates-with: AppConfiguration.swift

import Foundation
import Security

/// Errors from Keychain operations.
enum KeychainError: Error, LocalizedError, Sendable {
    /// String could not be encoded to/from UTF-8 data.
    case dataEncodingFailed

    /// An unexpected Security framework status code.
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .dataEncodingFailed:
            return "Failed to encode or decode Keychain data as UTF-8."
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            return "Keychain error (\(status)): \(message)"
        }
    }
}

/// Keychain-backed storage for secrets and device identity.
struct KeychainService: Sendable {

    /// The Keychain service identifier used to namespace items.
    let serviceIdentifier: String

    /// The account name used for the deviceId item.
    private static let deviceIdAccount = "com.vreader.deviceId"

    // MARK: - Initialization

    /// Creates a KeychainService with the given service identifier.
    ///
    /// - Parameter serviceIdentifier: A reverse-DNS string to namespace Keychain items.
    ///   Defaults to the app's production service identifier.
    init(serviceIdentifier: String = "com.vreader.keychain") {
        self.serviceIdentifier = serviceIdentifier
    }

    // MARK: - String Operations

    /// Saves a string value to the Keychain for the given account.
    /// If an item already exists for this account, it is overwritten.
    ///
    /// - Parameters:
    ///   - value: The string to store.
    ///   - account: The account key for this item.
    /// - Throws: `KeychainError` on failure.
    func saveString(_ value: String, forAccount account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }
        try saveData(data, forAccount: account)
    }

    /// Reads a string value from the Keychain for the given account.
    ///
    /// - Parameter account: The account key to look up.
    /// - Returns: The stored string, or nil if no item exists.
    /// - Throws: `KeychainError` on failure (other than item-not-found).
    func readString(forAccount account: String) throws -> String? {
        guard let data = try readData(forAccount: account) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }
        return string
    }

    // MARK: - Data Operations

    /// Saves raw data to the Keychain for the given account.
    /// If an item already exists for this account, it is overwritten.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - account: The account key for this item.
    /// - Throws: `KeychainError` on failure.
    func saveData(_ data: Data, forAccount account: String) throws {
        let query = baseQuery(forAccount: account)

        // Try to add first
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Item exists, update it (include accessibility to enforce on existing items)
            let updateAttributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Reads raw data from the Keychain for the given account.
    ///
    /// - Parameter account: The account key to look up.
    /// - Returns: The stored data, or nil if no item exists.
    /// - Throws: `KeychainError` on failure (other than item-not-found).
    func readData(forAccount account: String) throws -> Data? {
        var query = baseQuery(forAccount: account)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.dataEncodingFailed
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    /// Deletes the Keychain item for the given account.
    /// If no item exists, this is a no-op (does not throw).
    ///
    /// - Parameter account: The account key to delete.
    /// - Throws: `KeychainError` on failure (other than item-not-found).
    func delete(forAccount account: String) throws {
        let query = baseQuery(forAccount: account)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Device ID

    /// Returns the persistent device identifier, generating one if needed.
    ///
    /// Uses atomic add-or-read pattern: attempts to add a new UUID first.
    /// If another caller raced and already inserted, reads the winner's value.
    /// This avoids the check-then-act race of read-then-write.
    ///
    /// - Returns: The device identifier string (UUID format).
    /// - Throws: `KeychainError` on Keychain failure.
    func deviceId() throws -> String {
        let newId = UUID().uuidString
        guard let data = newId.data(using: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }

        // Atomic add attempt — if another caller already inserted, this returns errSecDuplicateItem
        var addQuery = baseQuery(forAccount: Self.deviceIdAccount)
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            // We won the race (or it was first access)
            return newId
        case errSecDuplicateItem:
            // Another caller already inserted — read the winner's value
            guard let existing = try readString(forAccount: Self.deviceIdAccount) else {
                // Shouldn't happen: item exists but can't be read
                throw KeychainError.unexpectedStatus(errSecItemNotFound)
            }
            return existing
        default:
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Deletes the stored device identifier. The next call to `deviceId()` will
    /// generate a fresh UUID, effectively rotating the identity.
    ///
    /// This is the "Reset Sync Identity" action exposed in Settings.
    ///
    /// - Throws: `KeychainError` on Keychain failure.
    func resetDeviceId() throws {
        try delete(forAccount: Self.deviceIdAccount)
    }

    // MARK: - Private

    /// Builds the base query dictionary for a Keychain item.
    private func baseQuery(forAccount account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: account,
        ]
    }
}
