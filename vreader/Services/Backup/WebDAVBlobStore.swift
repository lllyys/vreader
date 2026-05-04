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
final class WebDAVBlobStore: BackupBlobReading, BackupBlobWriting, @unchecked Sendable {
    let transport: any WebDAVTransport
    /// Directory used for temp uploads under the WebDAV root. `.part` files
    /// here are swept by `tmpSweep()` (future WI; lives on WebDAVProvider).
    let tempPath: String
    /// Once we've successfully MKCOL'd the temp ancestors, skip subsequent
    /// MKCOLs in this process to keep happy-path PUTs cheap. Bug #112: a
    /// fresh rclone target rejects the first PUT with 409 because
    /// `VReader/uploads/tmp/` doesn't exist; after the first ensure we
    /// memoize so repeated uploads pay the cost once.
    ///
    /// Race semantics: two concurrent uploaders may both observe
    /// `ensuredTempDir == false` and call MKCOL twice. That's harmless —
    /// MKCOL on an existing directory is treated as success (the
    /// transport's adapter swallows the "already exists" status). The
    /// only cost is an extra round-trip on first concurrent use.
    private nonisolated(unsafe) var ensuredTempDir: Bool = false

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

        // Step 2: ensure the temp directory tree exists before PUT.
        // Bug #112: rclone (and other strict WebDAV servers) reject PUT
        // with 409 if the parent path doesn't exist. WebDAVProvider's
        // backup path MKCOLs `VReader/backups/...` ancestors but never
        // `VReader/uploads/tmp/`, which is owned by this adapter. We
        // create them here once per process.
        try await ensureTempDirectoryExists()

        // Step 3: PUT to a unique temp path. Mid-upload kill leaves only this
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

    /// MKCOL the temp directory tree (deepest-last) so a fresh server
    /// accepts the upcoming PUT. Memoized via `ensuredTempDir` — only
    /// runs once per instance after the first successful pass. MKCOL on
    /// an existing path returns an error on most servers; we swallow
    /// those with `try?` because the goal is "directory exists after
    /// this returns," not "we successfully created it." Concurrent first
    /// callers may both run the loop; that's harmless — MKCOL is
    /// idempotent on success.
    private func ensureTempDirectoryExists() async throws {
        if ensuredTempDir { return }
        for ancestor in Self.nestedAncestors(of: tempPath) {
            try? await transport.createDirectory(path: ancestor)
        }
        ensuredTempDir = true
    }

    /// Returns each ancestor directory deepest-last.
    /// `"VReader/uploads/tmp"` → `["VReader", "VReader/uploads", "VReader/uploads/tmp"]`.
    static func nestedAncestors(of path: String) -> [String] {
        var components: [String] = []
        var accumulator: [String] = []
        for piece in path.split(separator: "/") where !piece.isEmpty {
            accumulator.append(String(piece))
            components.append(accumulator.joined(separator: "/"))
        }
        return components
    }
}
