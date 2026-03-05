// Purpose: Streaming SHA-256 hash computation for imported files.
// Uses CryptoKit for secure hashing, reads in chunks to keep memory bounded.
//
// Key decisions:
// - Uses structured concurrency (not Task.detached) so cancellation propagates.
// - CancellationError is caught and rethrown as ImportError.cancelled.
//
// @coordinates-with: BookImporter.swift, ImportError.swift

import Foundation
import CryptoKit

/// Result of hashing a file's contents.
struct HashResult: Sendable, Equatable {
    /// Lowercase hex-encoded SHA-256 digest (64 characters).
    let sha256Hex: String

    /// Total file size in bytes.
    let byteCount: Int64
}

/// Computes SHA-256 hash by streaming file contents in chunks.
enum ContentHasher {

    /// Chunk size for streaming reads (64KB).
    private static let chunkSize = 64 * 1024

    /// Computes the SHA-256 hash and byte count of the file at the given URL.
    ///
    /// Performs synchronous file I/O. Callers on `@MainActor` must dispatch
    /// to a background context before calling this method.
    ///
    /// - Parameter fileURL: The file URL to hash.
    /// - Returns: A `HashResult` with the hex digest and byte count.
    /// - Throws: `ImportError.hashComputationFailed` if the file cannot be read,
    ///           `ImportError.cancelled` if the task is cancelled.
    static func hash(fileAt fileURL: URL) async throws -> HashResult {
        do {
            return try computeHash(fileAt: fileURL)
        } catch is CancellationError {
            throw ImportError.cancelled
        }
    }

    /// Synchronous hash computation on the calling thread.
    private static func computeHash(fileAt fileURL: URL) throws -> HashResult {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw ImportError.hashComputationFailed("File not readable")
        }

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ImportError.hashComputationFailed("Cannot open file")
        }
        defer {
            do {
                try fileHandle.close()
            } catch {
                assertionFailure("FileHandle close failed: \(error)")
            }
        }

        var hasher = SHA256()
        var totalBytes: Int64 = 0

        while true {
            try Task.checkCancellation()

            let chunk: Data?
            do {
                chunk = try fileHandle.read(upToCount: chunkSize)
            } catch {
                throw ImportError.hashComputationFailed("Read error during hashing")
            }

            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
            totalBytes += Int64(data.count)
        }

        let digest = hasher.finalize()
        let hexString = digest.map { String(format: "%02x", $0) }.joined()

        return HashResult(sha256Hex: hexString, byteCount: totalBytes)
    }
}
