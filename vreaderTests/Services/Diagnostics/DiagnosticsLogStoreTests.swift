// Purpose: Feature #96 WI-1 — DiagnosticsLogStore load / bound / filter / export
// behavior, with a mock source (no real OSLog dependency).

import Testing
import Foundation
@testable import vreader

/// A canned source — returns fixed entries, or throws, for deterministic tests.
private struct MockDiagnosticsSource: DiagnosticsLogSource {
    var entries: [DiagnosticsLogEntry] = []
    var error: Error?
    func recentEntries(since: Date?, limit: Int) async throws -> [DiagnosticsLogEntry] {
        if let error { throw error }
        return Array(entries.suffix(limit))
    }
}

private func entry(_ level: DiagnosticsLevel, _ category: String, _ message: String,
                   at offset: TimeInterval = 0) -> DiagnosticsLogEntry {
    DiagnosticsLogEntry(date: Date(timeIntervalSince1970: 1_700_000_000 + offset),
                        level: level, category: category, message: message)
}

@MainActor
@Suite("DiagnosticsLogStore")
struct DiagnosticsLogStoreTests {

    @Test func loadPopulatesEntries() async {
        let src = MockDiagnosticsSource(entries: [
            entry(.info, "Library", "loaded"),
            entry(.error, "Persistence", "save failed"),
        ])
        let store = DiagnosticsLogStore(source: src)
        await store.load()
        #expect(store.entries.count == 2)
        #expect(store.hasLoaded)
    }

    @Test func loadBoundsToMaxEntries() async {
        let many = (0..<50).map { entry(.debug, "C", "m\($0)", at: TimeInterval($0)) }
        let src = MockDiagnosticsSource(entries: many)
        let store = DiagnosticsLogStore(source: src, maxEntries: 10)
        await store.load()
        #expect(store.entries.count == 10)
        // keeps the most recent
        #expect(store.entries.last?.message == "m49")
    }

    @Test func throwingSourceYieldsEmptyNoCrash() async {
        struct E: Error {}
        let store = DiagnosticsLogStore(source: MockDiagnosticsSource(error: E()))
        await store.load()
        #expect(store.entries.isEmpty)
        #expect(store.hasLoaded)
    }

    @Test func filterByLevelAndCategory() async {
        let src = MockDiagnosticsSource(entries: [
            entry(.info, "Library", "a"),
            entry(.error, "Library", "b"),
            entry(.error, "Persistence", "c"),
        ])
        let store = DiagnosticsLogStore(source: src)
        await store.load()
        #expect(store.filtered(level: .error).count == 2)
        #expect(store.filtered(category: "Library").count == 2)
        #expect(store.filtered(level: .error, category: "Library").count == 1)
        #expect(store.filtered().count == 3)              // nil = any
        #expect(Set(store.categories) == ["Library", "Persistence"])
    }

    @Test func exportRedactsSecretsInEveryMessage() async {
        let src = MockDiagnosticsSource(entries: [
            entry(.info, "AI", "using apiKey=LEAKEDSECRET123 now"),
            entry(.error, "Backup", "fail https://u:LEAKEDPW@host/x"),
            entry(.debug, "Import", "read /Users/ll/Library/b.epub"),
        ])
        let store = DiagnosticsLogStore(source: src)
        await store.load()
        let text = store.exportText()
        #expect(!text.contains("LEAKEDSECRET123"))
        #expect(!text.contains("LEAKEDPW"))
        #expect(!text.contains("/Users/ll/Library"))
        // structure: header + one line per entry
        #expect(text.contains("current session"))
        #expect(text.contains("[INFO]"))
        #expect(text.contains("(AI)"))
    }

    // Gate-4 Medium: a negative limit must be clamped, not crash via suffix(<0).
    @Test func negativeLimitClampsNoCrash() async {
        let src = MockDiagnosticsSource(entries: [entry(.info, "C", "m")])
        let store = DiagnosticsLogStore(source: src)
        await store.load(limit: -5)
        #expect(store.entries.isEmpty)
        #expect(store.hasLoaded)
    }

    @Test func exportEmptyHasHeaderOnly() async {
        let store = DiagnosticsLogStore(source: MockDiagnosticsSource(entries: []))
        await store.load()
        let text = store.exportText()
        #expect(text.contains("0 entries"))
    }
}
