// Purpose: Tests for ReadingModeMigration — the one-shot launch migration that
// removes the retired `readerReadingMode` UserDefaults key and strips the
// `readingMode` field from per-book override JSON files (feature #54 WI-2).
//
// Covers: UserDefaults key removal; idempotency (second run, clean install);
// per-book file `readingMode` strip with SEMANTIC preservation of all other
// keys/values (decoded-content equality, NOT byte-for-byte — a JSONSerialization
// round trip may re-order keys / re-format whitespace); per-book file WITHOUT a
// `readingMode` key is left untouched (no needless rewrite); missing directory
// tolerated; undecodable / non-JSON file tolerated; old-backup orphan-key
// re-clear; synchronous (compile-time) contract.

import Testing
import Foundation
@testable import vreader

@Suite("ReadingModeMigration")
struct ReadingModeMigrationTests {

    private let readingModeKey = "readerReadingMode"

    /// Fresh ephemeral UserDefaults suite + a fresh temp directory.
    private func makeEnvironment() -> (defaults: UserDefaults, suiteName: String, baseURL: URL) {
        let suiteName = "ReadingModeMigrationTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingModeMigrationTests-\(UUID().uuidString)", isDirectory: true)
        return (defaults, suiteName, baseURL)
    }

    private func cleanUp(_ env: (defaults: UserDefaults, suiteName: String, baseURL: URL)) {
        env.defaults.removePersistentDomain(forName: env.suiteName)
        try? FileManager.default.removeItem(at: env.baseURL)
    }

    // MARK: - UserDefaults key removal

    @Test func run_removesReaderReadingModeKey() {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        env.defaults.set("unified", forKey: readingModeKey)
        #expect(env.defaults.object(forKey: readingModeKey) != nil)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        #expect(env.defaults.object(forKey: readingModeKey) == nil)
    }

    @Test func run_isIdempotent_onSecondRun() {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        env.defaults.set("native", forKey: readingModeKey)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        #expect(env.defaults.object(forKey: readingModeKey) == nil)
    }

    @Test func run_isIdempotent_onCleanInstall_keyNeverExisted() {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        // Key never set — must not crash, must leave it absent.
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        #expect(env.defaults.object(forKey: readingModeKey) == nil)
    }

    @Test func run_clearsExternallyReSetKey_simulatingOldBackupRestore() {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        // First run clears it.
        env.defaults.set("unified", forKey: readingModeKey)
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        // An old-backup restore writes it back mid-session.
        env.defaults.set("unified", forKey: readingModeKey)
        // Next launch's run clears the orphan again.
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        #expect(env.defaults.object(forKey: readingModeKey) == nil)
    }

    // MARK: - Per-book file: readingMode strip with semantic preservation

    @Test func run_stripsReadingModeKey_fromPerBookFile_preservingOtherKeys() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        let fileURL = env.baseURL.appendingPathComponent("book1.json")
        let original: [String: Any] = [
            "fontSize": 18.0,
            "fontName": "Georgia",
            "themeName": "sepia",
            "readingMode": "unified"
        ]
        let originalData = try JSONSerialization.data(withJSONObject: original)
        try originalData.write(to: fileURL)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        let rewritten = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        let rewrittenObj = try #require(rewritten)
        // readingMode stripped.
        #expect(rewrittenObj["readingMode"] == nil)
        // All other keys/values semantically preserved (decoded-content equality).
        #expect(rewrittenObj["fontName"] as? String == "Georgia")
        #expect(rewrittenObj["themeName"] as? String == "sepia")
        #expect((rewrittenObj["fontSize"] as? NSNumber)?.doubleValue == 18.0)
        #expect(rewrittenObj.count == 3)
    }

    @Test func run_preservesPerBookFile_decodableAsTrimmedOverride() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        let fileURL = env.baseURL.appendingPathComponent("book2.json")
        let original: [String: Any] = [
            "fontSize": 20.0,
            "lineSpacing": 1.5,
            "readingMode": "native"
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: fileURL)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        // The rewritten file still decodes into PerBookSettingsOverride with
        // the non-readingMode fields intact.
        let decoded = try JSONDecoder().decode(
            PerBookSettingsOverride.self, from: Data(contentsOf: fileURL)
        )
        #expect(decoded.fontSize == 20.0)
        #expect(decoded.lineSpacing == 1.5)
    }

    @Test func run_leavesPerBookFileUntouched_whenNoReadingModeKey() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        let fileURL = env.baseURL.appendingPathComponent("book3.json")
        let original: [String: Any] = ["fontSize": 16.0, "themeName": "dark"]
        let originalData = try JSONSerialization.data(withJSONObject: original)
        try originalData.write(to: fileURL)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        // No readingMode key → no rewrite. The file's bytes are unchanged.
        let after = try Data(contentsOf: fileURL)
        #expect(after == originalData)
    }

    /// The critical preservation contract: a per-book file carrying keys the
    /// current `PerBookSettingsOverride` struct does NOT know (a future field,
    /// a nested object, an array) must survive the migration with its decoded
    /// content intact. This is the regression guard against someone switching
    /// the migration to a typed `JSONDecoder`/`JSONEncoder` round-trip — that
    /// would silently drop every unknown member and still pass the
    /// already-known-fields tests above.
    @Test func run_preservesUnknownTopLevelKeys_notJustStructFields() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        let fileURL = env.baseURL.appendingPathComponent("future.json")
        let original: [String: Any] = [
            "fontSize": 17.0,
            "readingMode": "unified",
            // Keys NOT on PerBookSettingsOverride — a typed round-trip drops these.
            "futureScalar": "hello",
            "futureFlag": true,
            "futureNumber": 42,
            "futureNested": ["a": 1, "b": ["x", "y"]],
            "futureArray": [1, 2, 3]
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: fileURL)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        // readingMode stripped; every other member — including the unknown
        // ones — preserved with identical decoded content.
        #expect(obj["readingMode"] == nil)
        #expect((obj["fontSize"] as? NSNumber)?.doubleValue == 17.0)
        #expect(obj["futureScalar"] as? String == "hello")
        #expect(obj["futureFlag"] as? Bool == true)
        #expect((obj["futureNumber"] as? NSNumber)?.intValue == 42)
        let nested = try #require(obj["futureNested"] as? [String: Any])
        #expect((nested["a"] as? NSNumber)?.intValue == 1)
        #expect(nested["b"] as? [String] == ["x", "y"])
        #expect((obj["futureArray"] as? [Any])?.count == 3)
        // Original 7 keys minus readingMode == 6.
        #expect(obj.count == 6)
    }

    /// Per-book file cleanup must be idempotent — after the first migration
    /// pass strips `readingMode`, a second run finds no `readingMode` key and
    /// must NOT rewrite the file (no needless write).
    @Test func run_perBookFileCleanup_isIdempotent_noRewriteOnSecondRun() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        let fileURL = env.baseURL.appendingPathComponent("book.json")
        try JSONSerialization.data(withJSONObject: ["fontSize": 15.0, "readingMode": "unified"]).write(to: fileURL)

        // First run strips readingMode.
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        let afterFirst = try Data(contentsOf: fileURL)

        // Second run: no readingMode key remains → file must not be rewritten.
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        let afterSecond = try Data(contentsOf: fileURL)

        #expect(afterSecond == afterFirst)
        // And it is still a valid, readingMode-free per-book file.
        let obj = try JSONSerialization.jsonObject(with: afterSecond) as? [String: Any]
        #expect(obj?["readingMode"] == nil)
        #expect((obj?["fontSize"] as? NSNumber)?.doubleValue == 15.0)
    }

    @Test func run_stripsReadingMode_acrossMultiplePerBookFiles() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        for i in 0..<3 {
            let url = env.baseURL.appendingPathComponent("book\(i).json")
            try JSONSerialization.data(withJSONObject: ["fontSize": 14.0, "readingMode": "unified"]).write(to: url)
        }

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        for i in 0..<3 {
            let url = env.baseURL.appendingPathComponent("book\(i).json")
            let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            #expect(obj?["readingMode"] == nil)
            #expect((obj?["fontSize"] as? NSNumber)?.doubleValue == 14.0)
        }
    }

    // MARK: - Tolerance

    @Test func run_toleratesMissingDirectory() {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        // baseURL never created — must not crash.
        env.defaults.set("unified", forKey: readingModeKey)
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        // The UserDefaults half still ran.
        #expect(env.defaults.object(forKey: readingModeKey) == nil)
    }

    @Test func run_toleratesUndecodableFile() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        // A non-JSON file in the directory.
        let badURL = env.baseURL.appendingPathComponent("garbage.json")
        try Data("not json at all {{{".utf8).write(to: badURL)
        // A valid file alongside it.
        let goodURL = env.baseURL.appendingPathComponent("good.json")
        try JSONSerialization.data(withJSONObject: ["fontSize": 12.0, "readingMode": "unified"]).write(to: goodURL)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        // The garbage file was skipped, not crashed on; the good file was migrated.
        let goodObj = try JSONSerialization.jsonObject(with: Data(contentsOf: goodURL)) as? [String: Any]
        #expect(goodObj?["readingMode"] == nil)
        // The garbage file is left as-is.
        #expect((try? Data(contentsOf: badURL)) != nil)
    }

    @Test func run_ignoresNonJSONExtensionFiles() throws {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        try FileManager.default.createDirectory(at: env.baseURL, withIntermediateDirectories: true)
        let txtURL = env.baseURL.appendingPathComponent("note.txt")
        let txtData = Data("readingMode lives here as plain text".utf8)
        try txtData.write(to: txtURL)

        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)

        // Non-.json files are not enumerated/touched.
        #expect((try? Data(contentsOf: txtURL)) == txtData)
    }

    // MARK: - Synchronous contract

    @Test func run_isSynchronous_callableWithoutAwait() {
        let env = makeEnvironment()
        defer { cleanUp(env) }
        // This test compiling at all proves `run` is synchronous — no `await`.
        ReadingModeMigration.run(defaults: env.defaults, perBookBaseURL: env.baseURL)
        #expect(Bool(true))
    }
}
