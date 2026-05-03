// Purpose: Tests for BookFileImportFinalizer — the shared verify +
// import + fingerprint-check pipeline used by both restore-all
// (`BookFileMaterializer`) and lazy-download (#47 WI-4b enqueue path).
// Feature #47 WI-4a.

import Testing
import Foundation
import CryptoKit
@testable import vreader

@Suite("BookFileImportFinalizer — feature #47 WI-4a")
struct BookFileImportFinalizerTests {

    // MARK: - Helpers

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("finalizer_sandbox_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeTempFile(data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finalizer_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    /// Minimal EPUB-ish bytes: ZIP magic (0x50 0x4B 0x03 0x04) + payload.
    /// BookImporter's format detection accepts this and computes a
    /// stable fingerprint — same trick the materializer test suite uses.
    private static func makeEPUBData() -> Data {
        Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x42, count: 1024)
    }

    private static func makeEntry(
        data: Data,
        format: BookFormat = .epub,
        originalExtension: String? = nil
    ) -> BackupLibraryEntry {
        let sha = sha256Hex(data)
        let bytes = Int64(data.count)
        let ext = originalExtension ?? format.fileExtensions.first ?? format.rawValue
        return BackupLibraryEntry(
            fingerprintKey: "\(format.rawValue):\(sha):\(bytes)",
            format: format.rawValue,
            sha256: sha,
            byteCount: bytes,
            originalExtension: ext,
            title: "T",
            author: "A",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: format, sha256: sha, byteCount: bytes)
        )
    }

    private static func makeFinalizer() async throws -> (BookFileImportFinalizer, URL) {
        let sandbox = try makeSandboxDir()
        let mockPersistence = MockPersistenceActor()
        let importer = BookImporter(persistence: mockPersistence, sandboxBooksDirectory: sandbox)
        return (BookFileImportFinalizer(importer: importer), sandbox)
    }

    // MARK: - Happy path

    @Test func finalize_validEPUB_returnsDownloadedWithFingerprint() async throws {
        let data = Self.makeEPUBData()
        let entry = Self.makeEntry(data: data)
        let tempURL = try Self.makeTempFile(data: data, ext: entry.originalExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let (finalizer, _) = try await Self.makeFinalizer()
        let result = await finalizer.finalize(localTempURL: tempURL, entry: entry)

        switch result.outcome {
        case .downloaded(let key):
            #expect(key == entry.fingerprintKey)
        default:
            Issue.record("expected .downloaded outcome, got \(result.outcome)")
        }
    }

    // MARK: - SHA-256 verification

    @Test func finalize_corruptedBytes_returnsSHA256Mismatch() async throws {
        let realData = Self.makeEPUBData()
        let entry = Self.makeEntry(data: realData)
        // Write different bytes than what the entry's SHA expects.
        let corrupted = Data(repeating: 0xFF, count: realData.count)
        let tempURL = try Self.makeTempFile(data: corrupted, ext: entry.originalExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let (finalizer, _) = try await Self.makeFinalizer()
        let result = await finalizer.finalize(localTempURL: tempURL, entry: entry)

        if case .sha256Mismatch(let expected, let actual) = result.outcome {
            #expect(expected == entry.sha256)
            #expect(actual != expected)
        } else {
            Issue.record("expected .sha256Mismatch, got \(result.outcome)")
        }
    }

    // MARK: - Missing file

    @Test func finalize_missingTempFile_returnsImportFailed() async throws {
        let entry = Self.makeEntry(data: Self.makeEPUBData())
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does_not_exist_\(UUID().uuidString).epub")

        let (finalizer, _) = try await Self.makeFinalizer()
        let result = await finalizer.finalize(localTempURL: bogus, entry: entry)

        if case .importFailed(let msg) = result.outcome {
            #expect(msg.contains("sha256-read-failed"))
        } else {
            Issue.record("expected .importFailed (sha256-read-failed), got \(result.outcome)")
        }
    }

    // MARK: - Caller owns lifetime

    @Test func finalize_doesNotDeleteTempFile() async throws {
        let data = Self.makeEPUBData()
        let entry = Self.makeEntry(data: data)
        let tempURL = try Self.makeTempFile(data: data, ext: entry.originalExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let (finalizer, _) = try await Self.makeFinalizer()
        _ = await finalizer.finalize(localTempURL: tempURL, entry: entry)

        // Caller (lazy coordinator / materializer) owns cleanup. Finalizer
        // must not touch the temp file — that would race the materializer's
        // existing `defer { remove tempURL }`.
        #expect(FileManager.default.fileExists(atPath: tempURL.path))
    }

    // MARK: - Static SHA helper

    @Test func localFileSHA256_matchesInMemoryHash() throws {
        let data = Data((0..<10_000).map { UInt8($0 % 256) })
        let url = try Self.makeTempFile(data: data, ext: "bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = Self.sha256Hex(data)
        let actual = try BookFileImportFinalizer.localFileSHA256(at: url)
        #expect(actual == expected)
    }

    @Test func localFileSHA256_emptyFile_matches() throws {
        let url = try Self.makeTempFile(data: Data(), ext: "bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let actual = try BookFileImportFinalizer.localFileSHA256(at: url)
        #expect(actual == Self.sha256Hex(Data()))
    }
}
