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

    @Test("Locator.canonicalJSON matches the golden vectors (cross-platform resume contract)")
    func locatorVectors() throws {
        let json = try Self.loadJSON("locator.json")
        let vectors = try #require(json["vectors"] as? [[String: Any]])
        #expect(!vectors.isEmpty)
        var emitted = ""
        for v in vectors {
            let format = try #require(BookFormat(rawValue: v["format"] as! String))
            let fp = DocumentFingerprint(
                contentSHA256: v["contentSHA256"] as! String,
                fileByteCount: Int64(v["fileByteCount"] as! Int),
                format: format
            )
            let loc = Locator(
                bookFingerprint: fp,
                href: v["href"] as? String,
                progression: v["progression"] as? Double,
                totalProgression: v["totalProgression"] as? Double,
                cfi: v["cfi"] as? String,
                page: v["page"] as? Int,
                charOffsetUTF16: v["charOffsetUTF16"] as? Int,
                charRangeStartUTF16: v["charRangeStartUTF16"] as? Int,
                charRangeEndUTF16: v["charRangeEndUTF16"] as? Int,
                textQuote: v["textQuote"] as? String,
                textContextBefore: v["textContextBefore"] as? String,
                textContextAfter: v["textContextAfter"] as? String
            )
            #expect(loc.canonicalJSON() == v["expectedCanonicalJSON"] as! String)
            emitted += loc.canonicalJSON() + "\n"
        }
        // Emit this platform's ACTUAL canonical output so run.sh can byte-diff it
        // against the Kotlin output (bug #355). Written to the repo via #filePath.
        // FAIL LOUD on a write error (bug #355 Gate-4) — a swallowed write could
        // leave a stale file that false-passes the cross-diff.
        let outDir = Self.vectorsDir().deletingLastPathComponent()
            .appendingPathComponent("conformance/.out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try emitted.write(to: outDir.appendingPathComponent("swift-locator.txt"),
                          atomically: true, encoding: .utf8)
    }

    @Test("Locator.validate() REJECTS non-finite progression (the canonical guard — bug #356)")
    func locatorRejectsNonFinite() {
        // Bug #356: a non-finite locator must NOT silently canonicalize to the same
        // form as a valid missing-progression one. The Swift guard is validate()
        // (the canonical hash is a non-throwing computed property used at 18
        // persisted-key sites, so a precondition crash there is riskier than
        // relying on validate() — the Kotlin reference additionally rejects at
        // canonicalJson). Assert validate() catches non-finite at the boundary.
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64), fileByteCount: 1, format: .epub
        )
        for p in [Double.nan, Double.infinity, -Double.infinity] {
            let progLoc = Locator(
                bookFingerprint: fp, href: nil, progression: p, totalProgression: nil,
                cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil, textContextAfter: nil
            )
            #expect(progLoc.validate() == .nonFiniteProgression)
            let totalLoc = Locator(
                bookFingerprint: fp, href: nil, progression: nil, totalProgression: p,
                cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
                charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil, textContextAfter: nil
            )
            #expect(totalLoc.validate() == .nonFiniteProgression)
        }
    }

    @Test("ChapterTranslationRecord.lookupKey matches the golden vectors")
    func cacheKeyVectors() throws {
        let json = try Self.loadJSON("cache-key.json")
        let vectors = try #require(json["vectors"] as? [[String: Any]])
        #expect(!vectors.isEmpty)
        var emitted = ""
        for v in vectors {
            let key = ChapterTranslationRecord.lookupKey(
                bookFingerprintKey: v["bookFingerprintKey"] as! String,
                unitStorageKey: v["unitStorageKey"] as! String,
                targetLanguage: v["targetLanguage"] as! String,
                promptVersion: v["promptVersion"] as! String
            )
            #expect(key == v["expectedLookupKey"] as! String)
            emitted += key + "\n"
        }
        // Emit for the run.sh cross-diff (bug #355) — fail loud on write error.
        let outDir = Self.vectorsDir().deletingLastPathComponent()
            .appendingPathComponent("conformance/.out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try emitted.write(to: outDir.appendingPathComponent("swift-cachekey.txt"),
                          atomically: true, encoding: .utf8)
    }
}
#endif
