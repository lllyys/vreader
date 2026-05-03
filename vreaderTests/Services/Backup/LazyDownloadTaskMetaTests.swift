// Purpose: Tests for LazyDownloadTaskMeta encode/decode and the
// taskDescription schema/format gate that protects downstream filesystem
// path construction. Feature #47 WI-3a.

import Testing
import Foundation
@testable import vreader

@Suite("LazyDownloadTaskMeta — feature #47 WI-3a")
struct LazyDownloadTaskMetaTests {

    private func validSHA() -> String { String(repeating: "a", count: 64) }

    @Test func encode_decode_roundTrips() throws {
        let original = LazyDownloadTaskMeta(
            fingerprintKey: "epub:abc:1024",
            blobPath: "VReader/books/epub/foo_1024.epub",
            expectedSHA256: validSHA(),
            expectedByteCount: 1024,
            originalExtension: "epub"
        )
        let encoded = try #require(original.encodeAsTaskDescription())
        let decoded = try #require(LazyDownloadTaskMeta.decode(fromTaskDescription: encoded))
        #expect(decoded == original)
    }

    @Test func decode_nilDescription_returnsNil() {
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: nil) == nil)
    }

    @Test func decode_garbageDescription_returnsNil() {
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: "not json") == nil)
    }

    @Test func decode_unknownSchemaVersion_returnsNil() throws {
        // A future v2 task description must be rejected by a v1 client so
        // the orphan handler kicks in (cancel + flip row to .failed).
        let futureMeta = """
        {"schemaVersion":99,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":1,"originalExtension":"epub"}
        """
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: futureMeta) == nil)
    }

    @Test func decode_zeroOrNegativeSchemaVersion_returnsNil() throws {
        let zeroVersion = """
        {"schemaVersion":0,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":1,"originalExtension":"epub"}
        """
        let negativeVersion = """
        {"schemaVersion":-1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":1,"originalExtension":"epub"}
        """
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: zeroVersion) == nil)
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: negativeVersion) == nil)
    }

    @Test func decode_invalidSHA_returnsNil() throws {
        // Wrong length, non-hex chars, or path-traversal text in SHA must
        // be rejected — the SHA is interpolated into a filesystem path
        // downstream, so a corrupt taskDescription cannot be allowed to
        // produce a path-bearing staged URL.
        let shortSHA = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"abc","expectedByteCount":1,"originalExtension":"epub"}
        """
        let nonHex = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(String(repeating: "z", count: 64))","expectedByteCount":1,"originalExtension":"epub"}
        """
        let pathTraversal = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"../etc/passwd\(String(repeating: "a", count: 50))","expectedByteCount":1,"originalExtension":"epub"}
        """
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: shortSHA) == nil)
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: nonHex) == nil)
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: pathTraversal) == nil)
    }

    @Test func decode_invalidExtension_returnsNil() throws {
        // Empty, overlong, or non-alnum extensions are rejected — the
        // extension is interpolated into a path so dots/slashes/spaces
        // in it would produce a path-traversing staged URL.
        let empty = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":1,"originalExtension":""}
        """
        let pathInExt = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":1,"originalExtension":"e/p"}
        """
        let overlong = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":1,"originalExtension":"superlongext"}
        """
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: empty) == nil)
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: pathInExt) == nil)
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: overlong) == nil)
    }

    @Test func decode_negativeByteCount_returnsNil() throws {
        let negative = """
        {"schemaVersion":1,"fingerprintKey":"k","blobPath":"p","expectedSHA256":"\(validSHA())","expectedByteCount":-1,"originalExtension":"epub"}
        """
        #expect(LazyDownloadTaskMeta.decode(fromTaskDescription: negative) == nil)
    }

    @Test func currentSchemaVersionIsOne() {
        #expect(LazyDownloadTaskMeta.currentSchemaVersion == 1)
    }
}
