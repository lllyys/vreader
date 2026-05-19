// Purpose: One-shot launch migration that retires the Native/Unified reading
// mode (feature #54). Removes the `readerReadingMode` UserDefaults key and
// strips the `readingMode` field from per-book override JSON files.
//
// Why this exists:
//   Before feature #54, the reader exposed a Native/Unified picker persisted
//   to the `readerReadingMode` UserDefaults key and, per-book, to a
//   `readingMode` field inside each PerBookSettings JSON file. Feature #54
//   removes the picker and routes rendering by `ReaderEngine` instead. This
//   migration cleans the now-orphaned persisted state at launch.
//
// Why it is SYNCHRONOUS and runs before any store/UI construction:
//   Per-book overrides are plain JSON files written by `PerBookSettingsStore`
//   with no actor and no lock. A detached fire-and-forget migration (the
//   `WebDAVProfileMigrator` pattern) could clobber a concurrent panel
//   save/delete or a backup restore, or let a `ReaderSettingsStore`
//   initialize while `readerReadingMode` is still set. `WebDAVProfileMigrator`
//   can be detached only because `WebDAVServerProfileStore` is an `actor`;
//   `PerBookSettingsStore` is not. So `run` is synchronous and is called
//   inside `VReaderApp.init()` BEFORE the debug bridge / settings store / UI
//   are constructed — at launch no reader is open, no panel mounted, no
//   backup running, so the migration owns the per-book directory and
//   UserDefaults. It is a one-shot launch gate, not best-effort detached work.
//
// Why per-book files are edited as raw JSON objects (not the typed struct):
//   Decoding a per-book file as `PerBookSettingsOverride` then re-encoding
//   would silently drop any field the current struct does not know — and #54
//   itself trims a field, so a naive typed round-trip is lossy. Instead the
//   file is decoded as a generic `JSONSerialization` object, only the
//   `readingMode` key is removed, and the object is re-written. This
//   SEMANTICALLY preserves every other key/value (the decoded content of
//   each untouched member is identical) — it is NOT byte-for-byte: a
//   JSONSerialization decode → re-encode may re-order keys or re-format
//   whitespace. That is harmless because per-book files are only ever
//   consumed via `JSONDecoder`, never compared byte-wise.
//
// Idempotent: a second run finds the key already absent and the files already
// stripped, and is a no-op. A file with no `readingMode` key is left untouched
// (no needless rewrite).
//
// @coordinates-with: PerBookSettings.swift (per-book JSON layout),
//   ReaderSettingsStore.swift (the `readerReadingMode` key), VReaderApp.swift
//   (the synchronous launch call site — wired in WI-5)

import Foundation
import os

/// One-shot launch migration retiring the Native/Unified reading mode.
/// Synchronous and idempotent — see the file header for the concurrency
/// rationale.
enum ReadingModeMigration {

    /// The retired UserDefaults key that stored the global reading mode.
    static let readingModeKey = "readerReadingMode"

    /// The retired per-book JSON field name.
    private static let perBookReadingModeKey = "readingMode"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "ReadingModeMigration"
    )

    /// Removes the retired reading-mode state. Synchronous; safe to call any
    /// number of times.
    ///
    /// - Parameters:
    ///   - defaults: UserDefaults holding the `readerReadingMode` key.
    ///   - perBookBaseURL: directory containing per-book override JSON files
    ///     (the same directory `PerBookSettingsStore` reads/writes).
    static func run(defaults: UserDefaults, perBookBaseURL: URL) {
        removeUserDefaultsKey(defaults: defaults)
        stripPerBookFiles(perBookBaseURL: perBookBaseURL)
    }

    // MARK: - UserDefaults

    private static func removeUserDefaultsKey(defaults: UserDefaults) {
        guard defaults.object(forKey: readingModeKey) != nil else { return }
        defaults.removeObject(forKey: readingModeKey)
        logger.info("Removed retired UserDefaults key '\(readingModeKey, privacy: .public)'.")
    }

    // MARK: - Per-book files

    private static func stripPerBookFiles(perBookBaseURL: URL) {
        let fileManager = FileManager.default
        // A missing directory is normal (fresh install) — nothing to strip.
        guard let entries = try? fileManager.contentsOfDirectory(
            at: perBookBaseURL,
            includingPropertiesForKeys: nil
        ) else { return }

        var rewrittenCount = 0
        for fileURL in entries where fileURL.pathExtension.lowercased() == "json" {
            if stripReadingModeKey(from: fileURL) {
                rewrittenCount += 1
            }
        }
        if rewrittenCount > 0 {
            logger.info("Stripped '\(perBookReadingModeKey, privacy: .public)' from \(rewrittenCount, privacy: .public) per-book file(s).")
        }
    }

    /// Strips the `readingMode` key from one per-book JSON file.
    ///
    /// Re-writes the file ONLY when a `readingMode` key was actually present
    /// and removed — a file with no such key is left byte-for-byte untouched.
    /// Undecodable / non-object JSON is skipped silently.
    ///
    /// - Returns: `true` if the file was rewritten, `false` otherwise.
    private static func stripReadingModeKey(from fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              var dictionary = object as? [String: Any] else {
            return false
        }
        guard dictionary[perBookReadingModeKey] != nil else {
            // No readingMode key → no rewrite needed.
            return false
        }
        dictionary.removeValue(forKey: perBookReadingModeKey)
        guard let newData = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return false
        }
        guard (try? newData.write(to: fileURL, options: .atomic)) != nil else {
            return false
        }
        return true
    }
}
