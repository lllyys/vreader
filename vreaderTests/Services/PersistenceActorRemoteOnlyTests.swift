// Purpose: Tests for PersistenceActor+RemoteOnly extension — fileState
// queries, fileState/blobPath mutations, and bulk insertion of remoteOnly
// rows used by the selective-restore flow. Feature #47 WI-3b foundation.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("PersistenceActor+RemoteOnly — feature #47 WI-3b")
struct PersistenceActorRemoteOnlyTests {

    private func makeRecord(
        sha: String,
        title: String = "Remote Book",
        fileState: BookFileState = .remoteOnly,
        blobPath: String? = "VReader/books/epub/\(String(repeating: "a", count: 64))_1024.epub"
    ) -> BookRecord {
        let fp = DocumentFingerprint(
            contentSHA256: sha,
            fileByteCount: 1024,
            format: .epub
        )
        return BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: title,
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: ImportProvenance(
                source: .filesApp,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: nil
            ),
            detectedEncoding: nil,
            addedAt: Date(),
            originalExtension: "epub",
            fileState: fileState,
            blobPath: blobPath
        )
    }

    // MARK: - fingerprintKeys(withFileState:)

    @Test func fingerprintKeysWithFileState_emptyDB_returnsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let keys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(keys.isEmpty)
    }

    @Test func fingerprintKeysWithFileState_filtersOnlyMatching() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let local = makeRecord(sha: String(repeating: "a", count: 64), fileState: .local, blobPath: nil)
        let remote1 = makeRecord(sha: String(repeating: "b", count: 64), fileState: .remoteOnly)
        let remote2 = makeRecord(sha: String(repeating: "c", count: 64), fileState: .remoteOnly)
        let downloading = makeRecord(sha: String(repeating: "d", count: 64), fileState: .downloading)
        _ = try await persistence.insertBook(local)
        _ = try await persistence.insertBook(remote1)
        _ = try await persistence.insertBook(remote2)
        _ = try await persistence.insertBook(downloading)

        let remoteKeys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(Set(remoteKeys) == Set([remote1.fingerprintKey, remote2.fingerprintKey]))

        let downloadingKeys = try await persistence.fingerprintKeys(withFileState: .downloading)
        #expect(downloadingKeys == [downloading.fingerprintKey])

        let failedKeys = try await persistence.fingerprintKeys(withFileState: .failed)
        #expect(failedKeys.isEmpty)
    }

    // MARK: - setBookFileState(fingerprintKey:newState:)

    @Test func setBookFileState_changesPersistedState() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let record = makeRecord(sha: String(repeating: "a", count: 64), fileState: .remoteOnly)
        _ = try await persistence.insertBook(record)

        try await persistence.setBookFileState(fingerprintKey: record.fingerprintKey, newState: .downloading)

        let downloading = try await persistence.fingerprintKeys(withFileState: .downloading)
        #expect(downloading == [record.fingerprintKey])
        let remoteOnly = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(remoteOnly.isEmpty)
    }

    @Test func setBookFileState_unknownKey_throwsRecordNotFound() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        do {
            try await persistence.setBookFileState(fingerprintKey: "nope:nope:0", newState: .failed)
            Issue.record("expected throw")
        } catch let PersistenceError.recordNotFound(key) {
            #expect(key == "nope:nope:0")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - setBlobPath(fingerprintKey:blobPath:)

    @Test func setBlobPath_persistsValue() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let record = makeRecord(sha: String(repeating: "a", count: 64), fileState: .local, blobPath: nil)
        _ = try await persistence.insertBook(record)

        let path = "VReader/books/epub/foo_2048.epub"
        try await persistence.setBlobPath(fingerprintKey: record.fingerprintKey, blobPath: path)

        let fetched = try await persistence.findBook(byFingerprintKey: record.fingerprintKey)
        #expect(fetched?.blobPath == path)
    }

    @Test func setBlobPath_nilClearsPath() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let record = makeRecord(sha: String(repeating: "a", count: 64), fileState: .remoteOnly, blobPath: "p")
        _ = try await persistence.insertBook(record)

        try await persistence.setBlobPath(fingerprintKey: record.fingerprintKey, blobPath: nil)

        let fetched = try await persistence.findBook(byFingerprintKey: record.fingerprintKey)
        #expect(fetched?.blobPath == nil)
    }

    @Test func setBlobPath_unknownKey_throwsRecordNotFound() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        do {
            try await persistence.setBlobPath(fingerprintKey: "nope:nope:0", blobPath: "p")
            Issue.record("expected throw")
        } catch let PersistenceError.recordNotFound(key) {
            #expect(key == "nope:nope:0")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - insertRemoteOnlyBookRecords

    @Test func insertRemoteOnly_insertsAllAsRemoteOnly() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let r1 = makeRecord(sha: String(repeating: "a", count: 64), title: "A")
        let r2 = makeRecord(sha: String(repeating: "b", count: 64), title: "B")
        let r3 = makeRecord(sha: String(repeating: "c", count: 64), title: "C")

        try await persistence.insertRemoteOnlyBookRecords([r1, r2, r3])

        let keys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(Set(keys) == Set([r1.fingerprintKey, r2.fingerprintKey, r3.fingerprintKey]))
    }

    @Test func insertRemoteOnly_isIdempotentWithExistingLocalBooks() async throws {
        // If a remoteOnly insert collides with an existing local book,
        // the local row wins — never downgrade .local to .remoteOnly.
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = String(repeating: "a", count: 64)
        let local = makeRecord(sha: sha, title: "Local", fileState: .local, blobPath: nil)
        _ = try await persistence.insertBook(local)

        let remote = makeRecord(sha: sha, title: "Remote", fileState: .remoteOnly)
        try await persistence.insertRemoteOnlyBookRecords([remote])

        let fetched = try await persistence.findBook(byFingerprintKey: local.fingerprintKey)
        #expect(fetched?.fileState == .local)
        #expect(fetched?.title == "Local")
    }

    @Test func insertRemoteOnly_emptyArray_noOps() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        try await persistence.insertRemoteOnlyBookRecords([])
        let allRemote = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(allRemote.isEmpty)
    }

    @Test func insertRemoteOnly_coercesCallerFileStateToRemoteOnly() async throws {
        // Pin the coercion invariant: even if the caller passed `.local`,
        // `.downloading`, or `.failed`, the row lands as `.remoteOnly`.
        // The catalog is the only entry point for this method, and it must
        // not be possible to bypass the coercion.
        let persistence = try CollectionTestHelper.makePersistence()
        let local = makeRecord(sha: String(repeating: "a", count: 64), fileState: .local, blobPath: "p1")
        let downloading = makeRecord(sha: String(repeating: "b", count: 64), fileState: .downloading, blobPath: "p2")
        let failed = makeRecord(sha: String(repeating: "c", count: 64), fileState: .failed, blobPath: "p3")

        try await persistence.insertRemoteOnlyBookRecords([local, downloading, failed])

        let remoteKeys = try await persistence.fingerprintKeys(withFileState: .remoteOnly)
        #expect(Set(remoteKeys) == Set([local.fingerprintKey, downloading.fingerprintKey, failed.fingerprintKey]))

        // Coerced rows kept their blob paths.
        let fetched = try await persistence.findBook(byFingerprintKey: local.fingerprintKey)
        #expect(fetched?.blobPath == "p1")
    }

    // MARK: - Bug #118: atomic promote (.local + blobPath=nil in one save)

    @Test func promoteToLocalClearBlob_setsLocalAndClearsBlobInOneSave() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let sha = String(repeating: "a", count: 64)
        let record = makeRecord(sha: sha, fileState: .downloading, blobPath: "VReader/books/epub/old.epub")
        _ = try await persistence.insertBook(record)

        try await persistence.promoteToLocalClearBlob(fingerprintKey: record.fingerprintKey)

        let fetched = try await persistence.findBook(byFingerprintKey: record.fingerprintKey)
        #expect(fetched?.fileState == .local)
        #expect(fetched?.blobPath == nil)
    }

    @Test func promoteToLocalClearBlob_unknownKey_throwsRecordNotFound() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        do {
            try await persistence.promoteToLocalClearBlob(fingerprintKey: "nope:nope:0")
            Issue.record("expected throw")
        } catch let PersistenceError.recordNotFound(key) {
            #expect(key == "nope:nope:0")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
