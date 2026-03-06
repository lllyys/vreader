// Purpose: Tests for SyncConflictResolver — all merge algorithms from plan section 9.4.
// Covers LWW, tombstone-aware merges, field-level merges, monotonic versioning, append-only.

import Testing
import Foundation
@testable import vreader

@Suite("SyncConflictResolver")
struct SyncConflictResolverTests {

    let resolver = SyncConflictResolver()

    // MARK: - ReadingPosition: LWW by updatedAt, deviceId tie-break

    @Test func positionNewerRemoteWins() {
        let local = SyncPositionRecord(
            locatorHash: "loc-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            deviceId: SyncTestHelpers.deviceA
        )
        let remote = SyncPositionRecord(
            locatorHash: "loc-2",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            deviceId: SyncTestHelpers.deviceB
        )
        let result = resolver.resolvePosition(local: local, remote: remote)
        #expect(result == .useRemote)
    }

    @Test func positionNewerLocalWins() {
        let local = SyncPositionRecord(
            locatorHash: "loc-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            deviceId: SyncTestHelpers.deviceA
        )
        let remote = SyncPositionRecord(
            locatorHash: "loc-2",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            deviceId: SyncTestHelpers.deviceB
        )
        let result = resolver.resolvePosition(local: local, remote: remote)
        #expect(result == .useLocal)
    }

    @Test func positionEqualTimestampDeviceIdTieBreak() {
        let sameTime = SyncTestHelpers.refDate
        let local = SyncPositionRecord(
            locatorHash: "loc-1",
            updatedAt: sameTime,
            deviceId: "device-zzz" // lexicographically later
        )
        let remote = SyncPositionRecord(
            locatorHash: "loc-2",
            updatedAt: sameTime,
            deviceId: "device-aaa" // lexicographically earlier
        )
        // Lexicographic tie-breaker: larger deviceId wins
        let result = resolver.resolvePosition(local: local, remote: remote)
        #expect(result == .useLocal)
    }

    @Test func positionEqualTimestampEqualDeviceIdUsesLocal() {
        let sameTime = SyncTestHelpers.refDate
        let local = SyncPositionRecord(locatorHash: "loc-1", updatedAt: sameTime, deviceId: "same-device")
        let remote = SyncPositionRecord(locatorHash: "loc-2", updatedAt: sameTime, deviceId: "same-device")
        let result = resolver.resolvePosition(local: local, remote: remote)
        #expect(result == .useLocal)
    }

    // MARK: - Bookmark: tombstone-aware LWW

    @Test func bookmarkNewerActiveRemoteWins() {
        let local = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            createdAt: SyncTestHelpers.date(offsetBy: -100)
        )
        let remote = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            createdAt: SyncTestHelpers.date(offsetBy: -50)
        )
        let result = resolver.resolveBookmark(local: local, remote: remote)
        #expect(result.winner == .useRemote)
        // Keep earliest createdAt
        #expect(result.mergedCreatedAt == SyncTestHelpers.date(offsetBy: -100))
    }

    @Test func bookmarkNewerTombstoneWins() {
        let local = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            createdAt: SyncTestHelpers.refDate
        )
        let remote = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: true,
            createdAt: SyncTestHelpers.refDate
        )
        let result = resolver.resolveBookmark(local: local, remote: remote)
        #expect(result.winner == .useRemote)
    }

    @Test func bookmarkNewerActiveBeatsOlderTombstone() {
        let local = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            createdAt: SyncTestHelpers.refDate
        )
        let remote = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: true,
            createdAt: SyncTestHelpers.refDate
        )
        let result = resolver.resolveBookmark(local: local, remote: remote)
        #expect(result.winner == .useLocal)
    }

    @Test func bookmarkKeepsEarliestCreatedAt() {
        let local = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            createdAt: SyncTestHelpers.date(offsetBy: -200)
        )
        let remote = SyncBookmarkRecord(
            bookmarkId: "bm-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            createdAt: SyncTestHelpers.date(offsetBy: -50)
        )
        let result = resolver.resolveBookmark(local: local, remote: remote)
        #expect(result.mergedCreatedAt == SyncTestHelpers.date(offsetBy: -200))
    }

    @Test func bookmarkEqualTimestampTombstoneWins() {
        let sameTime = SyncTestHelpers.refDate
        let local = SyncBookmarkRecord(
            bookmarkId: "bm-1", updatedAt: sameTime, isDeleted: false, createdAt: sameTime
        )
        let remote = SyncBookmarkRecord(
            bookmarkId: "bm-1", updatedAt: sameTime, isDeleted: true, createdAt: sameTime
        )
        let result = resolver.resolveBookmark(local: local, remote: remote)
        #expect(result.winner == .useRemote)
    }

    // MARK: - Highlight: field-level merge with tombstones

    @Test func highlightNewerTombstoneWins() {
        let local = SyncHighlightRecord(
            highlightId: "hl-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            selectedText: "hello",
            color: "yellow",
            note: nil
        )
        let remote = SyncHighlightRecord(
            highlightId: "hl-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: true,
            selectedText: "hello",
            color: "yellow",
            note: nil
        )
        let result = resolver.resolveHighlight(local: local, remote: remote)
        #expect(result.winner == .useRemote)
    }

    @Test func highlightFieldLevelMergeNewerFieldsWin() {
        let local = SyncHighlightRecord(
            highlightId: "hl-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            selectedText: "hello world",
            color: "blue",
            note: "local note"
        )
        let remote = SyncHighlightRecord(
            highlightId: "hl-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            selectedText: "hello",
            color: "yellow",
            note: "remote note"
        )
        // Newer updatedAt overall wins for field set
        let result = resolver.resolveHighlight(local: local, remote: remote)
        #expect(result.winner == .useLocal)
    }

    @Test func highlightBothActiveNewerRemoteWins() {
        let local = SyncHighlightRecord(
            highlightId: "hl-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            selectedText: "text",
            color: "yellow",
            note: nil
        )
        let remote = SyncHighlightRecord(
            highlightId: "hl-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            selectedText: "text updated",
            color: "blue",
            note: "added note"
        )
        let result = resolver.resolveHighlight(local: local, remote: remote)
        #expect(result.winner == .useRemote)
    }

    // MARK: - Annotation: LWW with tombstone precedence

    @Test func annotationNewerRemoteWins() {
        let local = SyncAnnotationRecord(
            annotationId: "an-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            content: "local content"
        )
        let remote = SyncAnnotationRecord(
            annotationId: "an-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            content: "remote content"
        )
        let result = resolver.resolveAnnotation(local: local, remote: remote)
        #expect(result == .useRemote)
    }

    @Test func annotationNewerTombstoneWins() {
        let local = SyncAnnotationRecord(
            annotationId: "an-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: false,
            content: "content"
        )
        let remote = SyncAnnotationRecord(
            annotationId: "an-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: true,
            content: ""
        )
        let result = resolver.resolveAnnotation(local: local, remote: remote)
        #expect(result == .useRemote)
    }

    @Test func annotationEqualTimestampTombstoneWins() {
        let sameTime = SyncTestHelpers.refDate
        let local = SyncAnnotationRecord(
            annotationId: "an-1", updatedAt: sameTime, isDeleted: false, content: "c"
        )
        let remote = SyncAnnotationRecord(
            annotationId: "an-1", updatedAt: sameTime, isDeleted: true, content: ""
        )
        let result = resolver.resolveAnnotation(local: local, remote: remote)
        #expect(result == .useRemote)
    }

    @Test func annotationNewerLocalActiveBeatsOlderTombstone() {
        let local = SyncAnnotationRecord(
            annotationId: "an-1",
            updatedAt: SyncTestHelpers.date(offsetBy: 10),
            isDeleted: false,
            content: "content"
        )
        let remote = SyncAnnotationRecord(
            annotationId: "an-1",
            updatedAt: SyncTestHelpers.date(offsetBy: -10),
            isDeleted: true,
            content: ""
        )
        let result = resolver.resolveAnnotation(local: local, remote: remote)
        #expect(result == .useLocal)
    }

    // MARK: - LibraryMetadata: user-edited wins over extracted

    @Test func libraryMetadataUserEditWinsOverExtracted() {
        let local = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "User Title",
            author: "User Author",
            isUserEdited: true,
            updatedAt: SyncTestHelpers.date(offsetBy: -10)
        )
        let remote = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "Extracted Title",
            author: "Extracted Author",
            isUserEdited: false,
            updatedAt: SyncTestHelpers.date(offsetBy: 10)
        )
        let result = resolver.resolveLibraryMetadata(local: local, remote: remote)
        #expect(result == .useLocal)
    }

    @Test func libraryMetadataNewerUserEditWins() {
        let local = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "Old User Title",
            author: nil,
            isUserEdited: true,
            updatedAt: SyncTestHelpers.date(offsetBy: -10)
        )
        let remote = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "New User Title",
            author: "New Author",
            isUserEdited: true,
            updatedAt: SyncTestHelpers.date(offsetBy: 10)
        )
        let result = resolver.resolveLibraryMetadata(local: local, remote: remote)
        #expect(result == .useRemote)
    }

    @Test func libraryMetadataExtractedFillsEmptyFields() {
        let local = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "",
            author: nil,
            isUserEdited: false,
            updatedAt: SyncTestHelpers.date(offsetBy: -10)
        )
        let remote = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "Extracted Title",
            author: "Extracted Author",
            isUserEdited: false,
            updatedAt: SyncTestHelpers.date(offsetBy: 10)
        )
        let result = resolver.resolveLibraryMetadata(local: local, remote: remote)
        #expect(result == .useRemote)
    }

    @Test func libraryMetadataBothExtractedNewerWins() {
        let local = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "Old Extracted",
            author: nil,
            isUserEdited: false,
            updatedAt: SyncTestHelpers.date(offsetBy: 10)
        )
        let remote = SyncLibraryMetadataRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            title: "Older Extracted",
            author: nil,
            isUserEdited: false,
            updatedAt: SyncTestHelpers.date(offsetBy: -10)
        )
        let result = resolver.resolveLibraryMetadata(local: local, remote: remote)
        #expect(result == .useLocal)
    }

    // MARK: - FileManifest: monotonic version

    @Test func fileManifestHigherVersionWins() {
        let local = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 1,
            checksum: "abc123"
        )
        let remote = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 2,
            checksum: "def456"
        )
        let result = resolver.resolveFileManifest(local: local, remote: remote)
        #expect(result.winner == .useRemote)
        #expect(result.requiresStale == false)
    }

    @Test func fileManifestSameVersionChecksumMismatchForcesStale() {
        let local = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 3,
            checksum: "abc123"
        )
        let remote = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 3,
            checksum: "xyz789"
        )
        let result = resolver.resolveFileManifest(local: local, remote: remote)
        #expect(result.requiresStale == true)
    }

    @Test func fileManifestSameVersionSameChecksumNoOp() {
        let local = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 3,
            checksum: "same"
        )
        let remote = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 3,
            checksum: "same"
        )
        let result = resolver.resolveFileManifest(local: local, remote: remote)
        #expect(result.winner == .useLocal)
        #expect(result.requiresStale == false)
    }

    @Test func fileManifestLowerRemoteVersionKeepsLocal() {
        let local = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 5,
            checksum: "abc"
        )
        let remote = SyncFileManifestRecord(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey,
            manifestVersion: 3,
            checksum: "def"
        )
        let result = resolver.resolveFileManifest(local: local, remote: remote)
        #expect(result.winner == .useLocal)
    }

    // MARK: - ReadingSession: append-only dedup

    @Test func sessionNewRemoteIsAppended() {
        let localIds: Set<String> = ["s1", "s2"]
        let remoteId = "s3"
        let result = resolver.resolveSession(localSessionIds: localIds, remoteSessionId: remoteId)
        #expect(result == .append)
    }

    @Test func sessionDuplicateIsSkipped() {
        let localIds: Set<String> = ["s1", "s2"]
        let remoteId = "s1"
        let result = resolver.resolveSession(localSessionIds: localIds, remoteSessionId: remoteId)
        #expect(result == .skip)
    }

    @Test func sessionEmptyLocalAlwaysAppends() {
        let localIds: Set<String> = []
        let remoteId = "s1"
        let result = resolver.resolveSession(localSessionIds: localIds, remoteSessionId: remoteId)
        #expect(result == .append)
    }
}
