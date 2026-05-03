// Purpose: Tests for the file-state helpers added to LibraryBookItem
// in feature #47 WI-5: `isReadable`, `needsDownload`, `canShare`. These
// drive row UI decisions (cloud icon vs spinner vs retry CTA), the
// Share-menu visibility, and the reader-open gate.

import Testing
import Foundation
@testable import vreader

@Suite("LibraryBookItem.fileState helpers — feature #47 WI-5")
struct LibraryBookItemFileStateTests {

    private func makeItem(fileState: BookFileState, blobPath: String? = nil) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: "epub:abc:1024",
            title: "T",
            author: "A",
            coverImagePath: nil,
            format: "epub",
            fileByteCount: 1024,
            addedAt: Date(),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            lastReadAt: nil,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            fileState: fileState,
            blobPath: blobPath
        )
    }

    // MARK: - isReadable

    @Test func isReadable_trueOnlyForLocal() {
        #expect(makeItem(fileState: .local).isReadable)
        #expect(makeItem(fileState: .remoteOnly).isReadable == false)
        #expect(makeItem(fileState: .downloading).isReadable == false)
        #expect(makeItem(fileState: .failed).isReadable == false)
        #expect(makeItem(fileState: .missingRemote).isReadable == false)
    }

    // MARK: - needsDownload

    @Test func needsDownload_trueForRemoteOnlyAndFailed() {
        #expect(makeItem(fileState: .remoteOnly).needsDownload)
        #expect(makeItem(fileState: .failed).needsDownload)
    }

    @Test func needsDownload_falseForLocalDownloadingAndMissingRemote() {
        #expect(makeItem(fileState: .local).needsDownload == false)
        #expect(makeItem(fileState: .downloading).needsDownload == false)
        #expect(makeItem(fileState: .missingRemote).needsDownload == false)
    }

    // MARK: - canShare

    @Test func canShare_mirrorsIsReadable() {
        // Sharing requires bytes — only `.local` rows can be shared.
        // Pinned as a separate property because the Share menu code
        // reads `canShare` semantically; if a future state allows
        // streaming-share we'd diverge from `isReadable`.
        for state in BookFileState.allCases {
            let item = makeItem(fileState: state)
            #expect(item.canShare == item.isReadable)
        }
    }

    // MARK: - Default init still produces .local

    @Test func defaultInit_assumesLocalNoBlobPath() {
        // Backward-compat for call sites that pre-date #47.
        let item = LibraryBookItem(
            fingerprintKey: "k",
            title: "T",
            author: nil,
            coverImagePath: nil,
            format: "epub",
            fileByteCount: 1,
            addedAt: Date(),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil
        )
        #expect(item.fileState == .local)
        #expect(item.blobPath == nil)
        #expect(item.isReadable)
    }

    // MARK: - blobPath round-trips

    @Test func blobPath_storedAndExposed() {
        let item = makeItem(fileState: .remoteOnly, blobPath: "VReader/books/epub/foo_1024.epub")
        #expect(item.blobPath == "VReader/books/epub/foo_1024.epub")
    }
}

@Suite("PersistenceActor+Library — fileState projection (#47 WI-5)")
struct PersistenceActorLibraryFileStateTests {

    @Test func fetchAllLibraryBooks_carriesFileStateAndBlobPath() async throws {
        let persistence = try CollectionTestHelper.makePersistence()

        let local = makeRecord(sha: String(repeating: "a", count: 64), fileState: .local, blobPath: nil)
        let remote = makeRecord(sha: String(repeating: "b", count: 64), fileState: .remoteOnly, blobPath: "p1")
        let failed = makeRecord(sha: String(repeating: "c", count: 64), fileState: .failed, blobPath: "p2")
        _ = try await persistence.insertBook(local)
        _ = try await persistence.insertBook(remote)
        _ = try await persistence.insertBook(failed)

        let items = try await persistence.fetchAllLibraryBooks()
        let byKey = Dictionary(uniqueKeysWithValues: items.map { ($0.fingerprintKey, $0) })

        #expect(byKey[local.fingerprintKey]?.fileState == .local)
        #expect(byKey[local.fingerprintKey]?.blobPath == nil)
        #expect(byKey[remote.fingerprintKey]?.fileState == .remoteOnly)
        #expect(byKey[remote.fingerprintKey]?.blobPath == "p1")
        #expect(byKey[failed.fingerprintKey]?.fileState == .failed)
        #expect(byKey[failed.fingerprintKey]?.blobPath == "p2")
    }

    private func makeRecord(sha: String, fileState: BookFileState, blobPath: String?) -> BookRecord {
        let fp = DocumentFingerprint(
            contentSHA256: sha,
            fileByteCount: 1024,
            format: .epub
        )
        return BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "T",
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
}
