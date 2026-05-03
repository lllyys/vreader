// Purpose: Adapter that gives WebDAVTransport the BackupBlobReading and
// BackupBlobWriting shape required by feature #46. Keeps the protocol-side
// API focused (BookFileMaterializer doesn't need to know about WebDAV) and
// implements the temp-then-MOVE atomic upload pattern in one place.
//
// @coordinates-with: BackupBlobStore.swift, WebDAVClient.swift,
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Foundation

/// Wraps any `WebDAVTransport` and exposes the read+write blob-store API.
/// Stateless — owns no buffers, just composes the transport's primitives.
struct WebDAVBlobStore: BackupBlobReading, BackupBlobWriting, Sendable {
    let transport: any WebDAVTransport
    /// Directory used for temp uploads under the WebDAV root. `.part` files
    /// here are swept by `tmpSweep()` (future WI; lives on WebDAVProvider).
    let tempPath: String

    init(transport: any WebDAVTransport, tempPath: String = "VReader/uploads/tmp") {
        self.transport = transport
        self.tempPath = tempPath
    }

    // MARK: - BackupBlobReading

    func existsWithSize(at path: String) async throws -> Int64? {
        do {
            return try await transport.existsWithSize(at: path)
        } catch let error as WebDAVError {
            throw BackupBlobStoreError.underlying("\(error)")
        }
    }

    func download(from path: String) async throws -> Data {
        do {
            return try await transport.download(fromPath: path)
        } catch let error as WebDAVError {
            throw BackupBlobStoreError.underlying("\(error)")
        }
    }

    // MARK: - BackupBlobWriting

    func putBlobAtomically(
        _ data: Data,
        to path: String,
        expectedByteCount: Int64
    ) async throws -> BlobPutResult {
        // Step 1: check whether the final blob already exists with matching size.
        // If so, we're done — content-addressed paths guarantee identical bytes
        // have converged.
        if let existing = try await existsWithSize(at: path), existing == expectedByteCount {
            return .alreadyExists
        }

        // Step 2: PUT to a unique temp path. Mid-upload kill leaves only this
        // .part file (which gets swept after 24h); the final path stays clean.
        let tempBlobPath = "\(tempPath)/\(UUID().uuidString).part"
        do {
            try await transport.upload(data: data, toPath: tempBlobPath)
        } catch let error as WebDAVError {
            throw BackupBlobStoreError.underlying("PUT failed: \(error)")
        }

        // Step 3: verify the PUT actually landed the right byte count.
        // A network truncation could leave a short file at the temp path.
        let uploadedSize: Int64?
        do {
            uploadedSize = try await transport.existsWithSize(at: tempBlobPath)
        } catch let error as WebDAVError {
            // Best-effort cleanup; ignore secondary errors.
            try? await transport.delete(path: tempBlobPath)
            throw BackupBlobStoreError.underlying("PROPFIND-verify failed: \(error)")
        }

        if let size = uploadedSize, size != expectedByteCount {
            try? await transport.delete(path: tempBlobPath)
            throw BackupBlobStoreError.sizeAfterPutMismatch(
                expected: expectedByteCount, actual: size
            )
        }

        // Step 4: MOVE temp → final. Default Overwrite: F so a concurrent
        // backup that already published the same blob isn't clobbered.
        // 412 means destination already exists with matching content
        // (content-addressing) — treat as success.
        do {
            try await transport.move(fromPath: tempBlobPath, toPath: path)
        } catch WebDAVError.httpError(412) {
            // Concurrent publish; clean up our temp and report the dedupe.
            try? await transport.delete(path: tempBlobPath)
            return .alreadyExists
        } catch WebDAVError.httpError(let status) where status == 501 {
            // Server doesn't support MOVE. Surface the capability gap so the
            // UI can point users at the README's self-host requirements
            // instead of silently degrading to non-atomic PUT-then-DELETE.
            try? await transport.delete(path: tempBlobPath)
            throw BackupBlobStoreError.serverCapabilityMissing("MOVE")
        } catch let error as WebDAVError {
            try? await transport.delete(path: tempBlobPath)
            throw BackupBlobStoreError.underlying("MOVE failed: \(error)")
        }

        return .uploaded
    }
}
