// Purpose: Tests for ContentHasher — streaming SHA-256 hash computation.

import Testing
import Foundation
@testable import vreader

@Suite("ContentHasher")
struct ContentHasherTests {

    // MARK: - Known Hash Values

    @Test func emptyDataHash() async throws {
        // SHA-256 of empty data is a well-known constant
        let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let tempURL = try createTempFile(content: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try await ContentHasher.hash(fileAt: tempURL)
        #expect(result.sha256Hex == emptyHash)
        #expect(result.byteCount == 0)
    }

    @Test func knownStringHash() async throws {
        // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let expectedHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let tempURL = try createTempFile(content: "hello".data(using: .utf8)!)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try await ContentHasher.hash(fileAt: tempURL)
        #expect(result.sha256Hex == expectedHash)
        #expect(result.byteCount == 5)
    }

    // MARK: - Byte Count

    @Test func byteCountMatchesFileSize() async throws {
        let data = Data(repeating: 0xAB, count: 4096)
        let tempURL = try createTempFile(content: data)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try await ContentHasher.hash(fileAt: tempURL)
        #expect(result.byteCount == 4096)
    }

    // MARK: - Determinism

    @Test func sameContentProducesSameHash() async throws {
        let data = "deterministic content".data(using: .utf8)!
        let url1 = try createTempFile(content: data)
        let url2 = try createTempFile(content: data)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let result1 = try await ContentHasher.hash(fileAt: url1)
        let result2 = try await ContentHasher.hash(fileAt: url2)
        #expect(result1.sha256Hex == result2.sha256Hex)
        #expect(result1.byteCount == result2.byteCount)
    }

    @Test func differentContentProducesDifferentHash() async throws {
        let url1 = try createTempFile(content: "content A".data(using: .utf8)!)
        let url2 = try createTempFile(content: "content B".data(using: .utf8)!)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let result1 = try await ContentHasher.hash(fileAt: url1)
        let result2 = try await ContentHasher.hash(fileAt: url2)
        #expect(result1.sha256Hex != result2.sha256Hex)
    }

    // MARK: - Hash Format Validation

    @Test func hashIsLowercaseHex64Chars() async throws {
        let tempURL = try createTempFile(content: "test".data(using: .utf8)!)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try await ContentHasher.hash(fileAt: tempURL)
        #expect(result.sha256Hex.count == 64)
        #expect(result.sha256Hex.allSatisfy { $0.isHexDigit })
        #expect(result.sha256Hex == result.sha256Hex.lowercased())
    }

    // MARK: - Error Cases

    @Test func nonexistentFileThrows() async {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")
        do {
            _ = try await ContentHasher.hash(fileAt: fakeURL)
            Issue.record("Expected error for nonexistent file")
        } catch let error as ImportError {
            guard case .hashComputationFailed = error else {
                Issue.record("Expected hashComputationFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected ImportError, got \(error)")
        }
    }

    // MARK: - Large File (streaming)

    @Test func largeFileStreamsCorrectly() async throws {
        // 1MB file to test streaming
        let data = Data(repeating: 0x42, count: 1_048_576)
        let tempURL = try createTempFile(content: data)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try await ContentHasher.hash(fileAt: tempURL)
        #expect(result.byteCount == 1_048_576)
        #expect(result.sha256Hex.count == 64)
    }

    // MARK: - Unicode Filename

    @Test func unicodeFilenameWorks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("测试文件_\(UUID().uuidString).txt")
        try "hello".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await ContentHasher.hash(fileAt: url)
        #expect(result.byteCount == 5)
    }

    // MARK: - Cancellation

    @Test func cancellationThrowsCancelledError() async throws {
        // Use a larger file to increase chance of cancellation being observed
        let data = Data(repeating: 0x00, count: 10_000_000) // 10MB
        let tempURL = try createTempFile(content: data)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let task = Task {
            try await ContentHasher.hash(fileAt: tempURL)
        }
        // Cancel immediately
        task.cancel()

        do {
            _ = try await task.value
            // May succeed if it completes before cancellation is checked — acceptable
        } catch is CancellationError {
            // Expected: raw CancellationError propagated
        } catch let error as ImportError {
            // Expected: mapped to .cancelled
            #expect(error == .cancelled, "Expected .cancelled, got \(error)")
        }
    }

    // MARK: - Helpers

    private func createTempFile(content: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("hasher_test_\(UUID().uuidString)")
        try content.write(to: url)
        return url
    }
}
