// Feature #104 Spike A WI-2 — Swift side of the dual-platform identity
// conformance lane. Asserts the Swift reference implementations
// (DocumentFingerprint, ChapterTranslationRecord) produce the SAME outputs
// as the SHARED golden vectors in `contracts/vectors/` — the identical
// vectors the Kotlin conformance suite (contracts/conformance/kotlin)
// asserts against. Both suites green against one vector set ⇒ the
// cross-platform identity contract holds (ADR-0001 Risk 1, the interop gate).
//
// The vectors are located relative to THIS source file via `#filePath`
// (iOS simulator tests run as host processes and can read the repo on the
// Mac), so `contracts/vectors/` stays the single source of truth — no
// bundled copy to drift.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #104 — cross-platform identity conformance (Swift side)")
struct IdentityConformanceTests {

    private static func vectorsDir(file: String = #filePath) -> URL {
        // …/vreaderTests/Contracts/IdentityConformanceTests.swift → repo root
        URL(fileURLWithPath: file)
            .deletingLastPathComponent()   // Contracts/
            .deletingLastPathComponent()   // vreaderTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("contracts/vectors")
    }

    private static func loadJSON(_ name: String) throws -> [String: Any] {
        let url = vectorsDir().appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("DocumentFingerprint.canonicalKey matches the golden vectors")
    func fingerprintVectors() throws {
        let json = try Self.loadJSON("fingerprint.json")
        let vectors = try #require(json["vectors"] as? [[String: Any]])
        #expect(!vectors.isEmpty)
        for v in vectors {
            let format = try #require(BookFormat(rawValue: v["format"] as! String))
            let fp = DocumentFingerprint(
                contentSHA256: v["contentSHA256"] as! String,
                fileByteCount: Int64(v["fileByteCount"] as! Int),
                format: format
            )
            #expect(fp.canonicalKey == v["expectedCanonicalKey"] as! String)
            // Round-trip: parse the key back to the same triple.
            let parsed = DocumentFingerprint(canonicalKey: fp.canonicalKey)
            #expect(parsed == fp)
        }
        // Invalid vectors must be rejected by `validated`.
        let invalid = try #require(json["invalid"] as? [[String: Any]])
        for v in invalid {
            let format = try #require(BookFormat(rawValue: v["format"] as! String))
            let result = DocumentFingerprint.validated(
                contentSHA256: v["contentSHA256"] as! String,
                fileByteCount: Int64(v["fileByteCount"] as! Int),
                format: format
            )
            #expect(result == nil, "invalid vector should be rejected: \(v["_why"] ?? "")")
        }
    }

    @Test("ChapterTranslationRecord.lookupKey matches the golden vectors")
    func cacheKeyVectors() throws {
        let json = try Self.loadJSON("cache-key.json")
        let vectors = try #require(json["vectors"] as? [[String: Any]])
        #expect(!vectors.isEmpty)
        for v in vectors {
            let key = ChapterTranslationRecord.lookupKey(
                bookFingerprintKey: v["bookFingerprintKey"] as! String,
                unitStorageKey: v["unitStorageKey"] as! String,
                targetLanguage: v["targetLanguage"] as! String,
                promptVersion: v["promptVersion"] as! String
            )
            #expect(key == v["expectedLookupKey"] as! String)
        }
    }
}
#endif
