// Purpose: Abstraction for key-value preference storage.
// Enables testability by injecting MockPreferenceStore in tests
// and UserDefaultsPreferenceStore in production.
//
// Key decisions:
// - Protocol-based for dependency injection.
// - String-based get/set for simplicity (enum rawValues are strings).
// - MockPreferenceStore is included here for test target access.
//
// @coordinates-with: LibraryViewModel.swift

import Foundation

/// Protocol for key-value preference storage.
protocol PreferenceStoring: Sendable {
    /// Returns the stored string for the given key, or nil if not set.
    func string(forKey key: String) -> String?

    /// Stores a string value for the given key.
    func set(_ value: String, forKey key: String)

    /// Removes the stored value for the given key. No-op if absent.
    func remove(forKey key: String)
}

extension PreferenceStoring {
    /// Convenience: write a value when non-nil, otherwise remove the key.
    func setOrRemove(_ value: String?, forKey key: String) {
        if let value { set(value, forKey: key) } else { remove(forKey: key) }
    }
}

/// Production implementation backed by UserDefaults.
final class UserDefaultsPreferenceStore: PreferenceStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory implementation for testing.
final class MockPreferenceStore: PreferenceStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func string(forKey key: String) -> String? {
        storage[key]
    }

    func set(_ value: String, forKey key: String) {
        storage[key] = value
    }

    func remove(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    /// Stores a raw string directly, useful for simulating corrupted data.
    func setRaw(_ value: String, forKey key: String) {
        storage[key] = value
    }
}
