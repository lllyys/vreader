// Purpose: Tests for WebDAVBlobStore — the WebDAV adapter for feature #46's
// transport-neutral BackupBlobReading + BackupBlobWriting protocols. Asserts
// the temp + PROPFIND-verify + MOVE atomic-publication pattern, dedupe on
// pre-existing blob, partial-upload detection, and clean error mapping.
//
// @coordinates-with: vreader/Services/Backup/WebDAVBlobStore.swift,
//   vreader/Services/Backup/BackupBlobStore.swift,
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVBlobStore — feature #46 WI-4")
struct WebDAVBlobStoreTests {

    // MARK: - Helpers

    private func makeStore() -> (WebDAVBlobStore, MockWebDAVTransport) {
        let mock = MockWebDAVTransport()
        return (WebDAVBlobStore(transport: mock), mock)
    }

    private let blobPath = "VReader/books/epub/\(String(repeating: "a", count: 64))_1024.epub"
    private let payload = Data(repeating: 0x42, count: 1024)

    // MARK: - Read side

    @Test func existsWithSize_missingPath_returnsNil() async throws {
        let (store, _) = makeStore()
        let size = try await store.existsWithSize(at: blobPath)
        #expect(size == nil)
    }

    @Test func existsWithSize_presentPath_returnsByteCount() async throws {
        let (store, mock) = makeStore()
        mock.files[blobPath] = payload
        let size = try await store.existsWithSize(at: blobPath)
        #expect(size == 1024)
    }

    @Test func download_returnsBytesFromTransport() async throws {
        let (store, mock) = makeStore()
        mock.files[blobPath] = payload
        let data = try await store.download(from: blobPath)
        #expect(data == payload)
    }

    @Test func download_missingPath_throwsUnderlying() async throws {
        let (store, _) = makeStore()
        await #expect(throws: BackupBlobStoreError.self) {
            _ = try await store.download(from: blobPath)
        }
    }

    // MARK: - Write side — happy path

    @Test func putBlobAtomically_freshBlob_uploadsViaTempThenMove() async throws {
        let (store, mock) = makeStore()
        let result = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        #expect(result == .uploaded)
        // Final blob is at the canonical path.
        #expect(mock.files[blobPath] == payload)
        // No leftover .part files in the tmp dir — MOVE consumed the temp.
        let tmpResidue = mock.files.keys.filter { $0.hasPrefix("VReader/uploads/tmp/") }
        #expect(tmpResidue.isEmpty)
        // Trace: PROPFIND-exists (final) → PUT (tmp) → PROPFIND-exists (tmp size verify) → MOVE
        let methods = mock.methodCalls.map(\.method)
        #expect(methods.contains("PUT"))
        #expect(methods.contains("MOVE"))
    }

    // MARK: - Write side — dedupe

    @Test func putBlobAtomically_alreadyExistsWithMatchingSize_skipsUpload() async throws {
        let (store, mock) = makeStore()
        mock.files[blobPath] = payload
        let result = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        #expect(result == .alreadyExists)
        // No PUT, no MOVE — dedupe path.
        let methods = mock.methodCalls.map(\.method)
        #expect(!methods.contains("PUT"))
        #expect(!methods.contains("MOVE"))
    }

    @Test func putBlobAtomically_alreadyExistsWithDifferentSize_attemptsUploadButHits412() async throws {
        // Documents a known limitation: when the final path has bytes with the
        // wrong size (server-state corruption — should not happen with
        // content-addressed paths), we attempt the upload, then MOVE fails with
        // 412 (destination exists), which we treat as .alreadyExists. The
        // wrong-size bytes stay in place. This is acceptable because:
        //   1. Content-addressed paths shouldn't accumulate wrong-size content
        //      in the first place — the path encodes the SHA-256 + byte count.
        //   2. Detecting and overwriting bad bytes here would defeat the
        //      content-addressing convergence guarantee.
        // If a user's server actually has corrupt blobs, manual cleanup or a
        // server-side `verify` script is the right fix, not adapter logic.
        let (store, mock) = makeStore()
        mock.files[blobPath] = Data(repeating: 0xFF, count: 999) // wrong size at final
        let result = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        #expect(result == .alreadyExists)
        // Confirm we attempted the upload — temp was used (dedupe-by-size
        // guard correctly didn't short-circuit on the wrong-size existing).
        let methods = mock.methodCalls.map(\.method)
        #expect(methods.contains("PUT"))
        // Tmp was cleaned up after the 412.
        let tmpResidue = mock.files.keys.filter { $0.hasPrefix("VReader/uploads/tmp/") }
        #expect(tmpResidue.isEmpty)
    }

    // MARK: - Write side — concurrent publish (412)

    @Test func putBlobAtomically_destinationAlreadyMatched_treats412AsAlreadyExists() async throws {
        // Simulate a race: another device published the blob between our
        // existsWithSize check (saw nothing) and our MOVE (sees existing).
        // The 412 from MOVE+Overwrite:F maps to .alreadyExists in our adapter.
        let (store, mock) = makeStore()
        // Pre-populate the destination with payload bytes mapped under a
        // different size (so the dedupe check at step 1 doesn't short-circuit
        // — we want MOVE to be the one rejecting).
        mock.existsWithSizeOverride = { path in
            // existsWithSize for the FINAL blob path returns 999 first call
            // (treated as wrong-size, falls through to PUT+MOVE), then nil
            // for the tmp path (so verify-size falls back to actual file).
            if path == self.blobPath { return 999 }
            return nil
        }
        // Pre-place an existing blob so MOVE will hit Overwrite: F → 412.
        mock.files[self.blobPath] = Data(repeating: 0x99, count: 999)

        // After PUT, mock.existsWithSize will return the actual byte count
        // since the override returns nil for tmp paths. Need to clear the
        // override after PUT — easier: drop it now, but keep the existing file.
        mock.existsWithSizeOverride = nil

        let result = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        #expect(result == .alreadyExists)
        // Tmp file was cleaned up after the 412.
        let tmpResidue = mock.files.keys.filter { $0.hasPrefix("VReader/uploads/tmp/") }
        #expect(tmpResidue.isEmpty)
    }

    // MARK: - Write side — partial upload detection

    @Test func putBlobAtomically_uploadTruncated_throwsSizeMismatch() async throws {
        let (store, mock) = makeStore()
        // PUT will succeed but PROPFIND-verify on the temp path returns the
        // wrong size — simulates network truncation mid-upload.
        mock.existsWithSizeOverride = { path in
            if path.contains("uploads/tmp/") { return 512 }  // truncated
            return nil
        }
        await #expect(throws: BackupBlobStoreError.self) {
            _ = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        }
        // Tmp file was removed after the size mismatch.
        let tmpResidue = mock.files.keys.filter { $0.hasPrefix("VReader/uploads/tmp/") }
        #expect(tmpResidue.isEmpty)
        // Final blob never landed.
        #expect(mock.files[blobPath] == nil)
    }

    // MARK: - Write side — server capability missing

    // MARK: - Write side — bug #112: fresh rclone server (no temp dir yet)

    @Test func putBlobAtomically_freshServer_createsTempDirectoryBeforePut() async throws {
        // Bug #112: rclone's WebDAV returns 409 when PUT'ing into a path
        // whose parent directory doesn't exist. The fix MKCOLs the temp
        // path before the first PUT.
        let (store, mock) = makeStore()
        mock.simulateRcloneStrictParentRequirement = true
        // Pre-MKCOL the books destination so the MOVE target's parent
        // exists — this test focuses on the temp parent.
        try await mock.createDirectory(path: "VReader/books/epub")

        let result = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        #expect(result == .uploaded)
        #expect(mock.files[blobPath] == payload)

        // Verify the order: MKCOL VReader/uploads/tmp comes BEFORE PUT.
        let methods = mock.methodCalls
        let mkcolTempIdx = methods.firstIndex { $0.method == "MKCOL" && $0.path == "VReader/uploads/tmp" }
        let putIdx = methods.firstIndex { $0.method == "PUT" }
        #expect(mkcolTempIdx != nil, "expected MKCOL on VReader/uploads/tmp before PUT")
        #expect(putIdx != nil, "expected at least one PUT")
        if let mi = mkcolTempIdx, let pi = putIdx {
            #expect(mi < pi, "MKCOL must precede PUT")
        }
    }

    @Test func putBlobAtomically_freshServer_alsoMkcolsAncestors() async throws {
        // Bug #112 edge case: rclone may also reject MKCOL on a deep path
        // whose intermediate ancestors don't exist. The fix walks
        // ancestors deepest-last so VReader → VReader/uploads →
        // VReader/uploads/tmp all get created.
        let (store, mock) = makeStore()
        mock.simulateRcloneStrictParentRequirement = true
        try await mock.createDirectory(path: "VReader/books/epub")

        _ = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)

        let mkcolPaths = mock.methodCalls.filter { $0.method == "MKCOL" }.map(\.path)
        // Either all three ancestors are MKCOL'd, or the implementation
        // is idempotent enough that a single MKCOL on the deepest path
        // succeeds (rclone accepts that, but stricter servers don't).
        // We assert the leaf is present at minimum.
        #expect(mkcolPaths.contains("VReader/uploads/tmp"))
    }

    // MARK: - Bug #117: failed MKCOL must not poison memoization

    @Test func ensureTempDir_failureDoesNotPoisonMemoization() async throws {
        // Bug #117: ensureTempDirectoryExists() previously swallowed every
        // MKCOL error with try? then unconditionally set ensuredTempDir.
        // A transient auth/network failure on first MKCOL would memoize
        // "directory ready" while the directory didn't actually exist —
        // every later upload in the same process would skip the ensure
        // step and keep failing 409.
        let (store, mock) = makeStore()
        mock.simulateRcloneStrictParentRequirement = true
        try await mock.createDirectory(path: "VReader/books/epub")

        // First call: MKCOL on the LEAF temp path throws auth.
        var firstAttempt = true
        mock.mkcolInterceptor = { path in
            if firstAttempt && path == "VReader/uploads/tmp" {
                return .authenticationFailed
            }
            return nil
        }

        do {
            _ = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
            Issue.record("expected first putBlobAtomically to throw — auth failed mid-ensure")
        } catch {
            // Expected — auth error propagates out of ensureTempDirectoryExists.
        }
        // Clear interceptor so the retry path can succeed.
        firstAttempt = false
        mock.mkcolInterceptor = nil

        // Second call MUST re-run the MKCOL chain (the failed memoization
        // would skip it and 409 would surface again).
        let result = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
        #expect(result == .uploaded)

        // Two MKCOLs on the leaf path = ensure ran twice.
        let leafMkcols = mock.methodCalls.filter { $0.method == "MKCOL" && $0.path == "VReader/uploads/tmp" }
        #expect(leafMkcols.count == 2, "expected MKCOL on leaf path on both first (failed) and second (success) attempts; got \(leafMkcols.count)")
    }

    @Test func putBlobAtomically_freshServer_alsoMkcolsAncestors_orderedFullChain() async throws {
        // Bug #117 sub-finding: the original test only asserted the leaf
        // MKCOL existed. Strengthen to verify the full ancestor chain
        // (deepest-last) is created — a regression that stopped
        // creating `VReader` would still 409 on stricter servers.
        let (store, mock) = makeStore()
        mock.simulateRcloneStrictParentRequirement = true
        try await mock.createDirectory(path: "VReader/books/epub")

        _ = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)

        let mkcolsInOrder = mock.methodCalls.filter { $0.method == "MKCOL" }.map(\.path)
        // Drop the test-setup MKCOL that pre-created VReader/books/epub.
        let storeMkcols = mkcolsInOrder.filter { $0.hasPrefix("VReader/uploads") || $0 == "VReader" }
        #expect(storeMkcols == ["VReader", "VReader/uploads", "VReader/uploads/tmp"])
    }

    @Test func putBlobAtomically_moveNotImplemented_throwsServerCapability() async throws {
        let (store, mock) = makeStore()
        mock.simulateMoveNotImplemented = true
        do {
            _ = try await store.putBlobAtomically(payload, to: blobPath, expectedByteCount: 1024)
            Issue.record("expected throw")
        } catch BackupBlobStoreError.serverCapabilityMissing(let cap) {
            #expect(cap == "MOVE")
        } catch {
            Issue.record("wrong error: \(error)")
        }
        // No final blob (no atomic publication possible).
        #expect(mock.files[blobPath] == nil)
        // Tmp cleaned.
        let tmpResidue = mock.files.keys.filter { $0.hasPrefix("VReader/uploads/tmp/") }
        #expect(tmpResidue.isEmpty)
    }
}
