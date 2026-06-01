// Feature #42 Phase 2 WI-2a: the libmobi DECODE path — load + reconstruct a
// Kindle file and extract its parts. Two CI-safe error-path cases pin the
// failure handling (no real book needed); one real-AZW3 case proves the decode
// against an actual Kindle book, skipped automatically when test-books/ is
// absent (CI can't see the gitignored fixtures — that path is exercised
// on-device in WI-5 and in the WI-3 fidelity spike).

import Testing
import Foundation
@testable import vreader

@Suite("libmobi decode (Feature #42 Phase 2 WI-2a)")
struct MobiDocumentTests {

    // MARK: CI-safe error paths (no fixture required)

    @Test("a nonexistent path throws (loadFailed), does not crash")
    func nonexistentPathThrows() {
        #expect(throws: MobiDecodeError.self) {
            try Libmobi.decodeParts(atPath: "/no/such/file-\(UUID().uuidString).azw3")
        }
    }

    @Test("a non-Kindle file throws rather than crashing")
    func nonKindleFileThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-mobi-\(UUID().uuidString).txt")
        try Data("plain text, definitely not a MOBI/PDB container".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(throws: MobiDecodeError.self) {
            try Libmobi.decodeParts(atPath: tmp.path)
        }
    }

    // MARK: Real-book decode (skipped in CI)

    @Test("a real AZW3 decodes into XHTML markup parts")
    func realAzw3DecodesToMarkup() throws {
        guard let path = Self.realAzw3Path else { return }  // CI / no fixture
        let parts = try Libmobi.decodeParts(atPath: path)

        let markup = parts.filter { $0.section == .markup }
        #expect(!markup.isEmpty, "a real AZW3 must reconstruct at least one markup part")

        let firstText = String(decoding: markup[0].data, as: UTF8.self).lowercased()
        #expect(
            firstText.contains("<html") || firstText.contains("<body") || firstText.contains("<p"),
            "the first markup part should contain XHTML"
        )
        // Every markup part should carry the html extension libmobi assigns.
        #expect(markup.allSatisfy { $0.fileExtension == "html" })
    }

    /// First real AZW3 under `<repo>/test-books/books/azw3`, or nil in CI. Repo
    /// root is derived from this source file's path (no hard-coded username).
    static var realAzw3Path: String? {
        let dir = URL(fileURLWithPath: #filePath)   // …/vreaderTests/Services/Libmobi/<this>
            .deletingLastPathComponent()            // Libmobi/
            .deletingLastPathComponent()            // Services/
            .deletingLastPathComponent()            // vreaderTests/
            .deletingLastPathComponent()            // <repo root>
            .appendingPathComponent("test-books/books/azw3")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let azw3 = items.first(where: { $0.lowercased().hasSuffix(".azw3") })
        else { return nil }
        return dir.appendingPathComponent(azw3).path
    }
}
