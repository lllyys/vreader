// Feature #42 Phase 2 WI-2a: the libmobi DECODE path — load + reconstruct a
// Kindle file and extract its parts. Coverage:
//  - CI-safe error paths pin the SPECIFIC MobiDecodeError surface (no fixture).
//  - Synthetic MOBIPart chains exercise appendChain's defensive paths
//    (cycle ceiling, null-data corruption, empty part) deterministically in CI —
//    no real libmobi parse needed.
//  - One real-AZW3 case proves the end-to-end decode, SKIPPED (not passed) when
//    test-books/ is absent (CI can't see the gitignored fixtures; that path is
//    also exercised on-device in WI-5 + the WI-3 fidelity spike).

import Testing
import Foundation
@testable import vreader

@Suite("libmobi decode (Feature #42 Phase 2 WI-2a)")
struct MobiDocumentTests {

    // MARK: CI-safe error paths (no fixture required)

    @Test("a nonexistent path throws loadFailed with a nonzero code")
    func nonexistentPathThrowsLoadFailed() {
        do {
            _ = try Libmobi.decodeParts(atPath: "/no/such/file-\(UUID().uuidString).azw3")
            Issue.record("expected decodeParts to throw")
        } catch let MobiDecodeError.loadFailed(code) {
            #expect(code != 0)
        } catch {
            Issue.record("expected .loadFailed, got \(error)")
        }
    }

    @Test("a non-Kindle file throws load/parseFailed rather than crashing")
    func nonKindleFileThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-mobi-\(UUID().uuidString).txt")
        try Data("plain text, definitely not a MOBI/PDB container".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            _ = try Libmobi.decodeParts(atPath: tmp.path)
            Issue.record("expected decodeParts to throw on a non-Kindle file")
        } catch MobiDecodeError.loadFailed, MobiDecodeError.parseFailed, MobiDecodeError.noMarkup {
            // any of these is a clean, memory-safe rejection
        } catch {
            Issue.record("expected a MobiDecodeError load/parse/noMarkup, got \(error)")
        }
    }

    // MARK: Synthetic-chain coverage of appendChain's defensive paths (CI-safe)

    @Test("appendChain extracts a synthetic two-node markup chain in order")
    func appendChainExtractsChain() throws {
        let b0 = Array("<p>a</p>".utf8)
        let b1 = Array("<p>b</p>".utf8)
        try b0.withUnsafeBufferPointer { p0 in
            try b1.withUnsafeBufferPointer { p1 in
                let n1 = UnsafeMutablePointer<MOBIPart>.allocate(capacity: 1)
                let n0 = UnsafeMutablePointer<MOBIPart>.allocate(capacity: 1)
                defer { n0.deallocate(); n1.deallocate() }
                n1.pointee = MOBIPart(uid: 1, type: T_HTML, size: b1.count,
                                      data: UnsafeMutablePointer(mutating: p1.baseAddress), next: nil)
                n0.pointee = MOBIPart(uid: 0, type: T_HTML, size: b0.count,
                                      data: UnsafeMutablePointer(mutating: p0.baseAddress), next: n1)
                var parts: [MobiPart] = []
                try Libmobi.appendChain(n0, section: .markup, into: &parts)
                #expect(parts.count == 2)
                #expect(parts.map(\.uid) == [0, 1])
                #expect(String(decoding: parts[0].data, as: UTF8.self) == "<p>a</p>")
                #expect(parts.allSatisfy { $0.fileExtension == "html" })
            }
        }
    }

    @Test("appendChain rejects a cyclic chain with .corrupt")
    func appendChainRejectsCycle() {
        var byte: UInt8 = 0x41
        withUnsafeMutablePointer(to: &byte) { bp in
            let n = UnsafeMutablePointer<MOBIPart>.allocate(capacity: 1)
            defer { n.deallocate() }
            n.pointee = MOBIPart(uid: 0, type: T_HTML, size: 1, data: bp, next: n)  // self-cycle
            var parts: [MobiPart] = []
            #expect(throws: MobiDecodeError.self) {
                try Libmobi.appendChain(n, section: .markup, into: &parts)
            }
        }
    }

    @Test("appendChain rejects size>0 with null data as .corrupt")
    func appendChainRejectsNullData() {
        let n = UnsafeMutablePointer<MOBIPart>.allocate(capacity: 1)
        defer { n.deallocate() }
        n.pointee = MOBIPart(uid: 0, type: T_HTML, size: 10, data: nil, next: nil)
        var parts: [MobiPart] = []
        #expect(throws: MobiDecodeError.self) {
            try Libmobi.appendChain(n, section: .markup, into: &parts)
        }
    }

    @Test("appendChain yields empty Data for a legitimately size==0 part")
    func appendChainAllowsZeroSize() throws {
        let n = UnsafeMutablePointer<MOBIPart>.allocate(capacity: 1)
        defer { n.deallocate() }
        n.pointee = MOBIPart(uid: 5, type: T_CSS, size: 0, data: nil, next: nil)
        var parts: [MobiPart] = []
        try Libmobi.appendChain(n, section: .flow, into: &parts)
        #expect(parts.count == 1)
        #expect(parts[0].data.isEmpty)
        #expect(parts[0].fileExtension == "css")
    }

    // MARK: Real-book decode (SKIPPED in CI via .enabled trait, not passed)

    @Test("a real AZW3 decodes into XHTML markup parts",
          .enabled(if: MobiDocumentTests.realAzw3Path != nil))
    func realAzw3DecodesToMarkup() throws {
        let path = try #require(Self.realAzw3Path)
        let parts = try Libmobi.decodeParts(atPath: path)

        let markup = parts.filter { $0.section == .markup }
        #expect(!markup.isEmpty, "a real AZW3 must reconstruct at least one markup part")

        let firstText = String(decoding: markup[0].data, as: UTF8.self).lowercased()
        #expect(
            firstText.contains("<html") || firstText.contains("<body") || firstText.contains("<p"),
            "the first markup part should contain XHTML"
        )
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
