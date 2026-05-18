// Purpose: Unit tests for CoverPickCoordinator — feature #61 WI-2.
// Pins the cover-pick persist contract extracted out of LibraryView /
// LibraryViewSheets: present(for:) targets a book, applyCover(_:) writes
// through CustomCoverStore and bumps coverVersion, and the version
// counter / reset behave as the library + Book Details views expect.

import Testing
import UIKit
@testable import vreader

@MainActor
@Suite("CoverPickCoordinator")
struct CoverPickCoordinatorTests {

    /// A 4x4 opaque test image — small enough to persist instantly.
    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 4, height: 4), format: format
        ).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private func makeBook(key: String = "epub:cover-coord-test:1024") -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: key,
            title: "Cover Test",
            author: nil,
            coverImagePath: nil,
            format: "epub",
            fileByteCount: 1024,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil
        )
    }

    /// A unique temp directory so tests never touch the real App Support
    /// covers directory.
    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("coverpick-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func presentSetsBookForCover() {
        let coordinator = CoverPickCoordinator()
        #expect(coordinator.bookForCover == nil)
        let book = makeBook()
        coordinator.present(for: book)
        #expect(coordinator.bookForCover == book)
    }

    @Test func applyCoverPersistsThroughStoreAndBumpsVersion() {
        let coordinator = CoverPickCoordinator()
        let book = makeBook()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        coordinator.applyCover(makeImage(), for: book, baseDirectory: dir)

        #expect(CustomCoverStore.hasCover(for: book.fingerprintKey, baseDirectory: dir))
        #expect(coordinator.coverVersion == 1)
    }

    @Test func applyCoverTargetsTheGivenBookNotCurrentState() {
        // The picked-item handler snapshots the book before the async
        // image load, so a retarget (a second present) before the save
        // must NOT redirect the cover onto the newer book.
        let coordinator = CoverPickCoordinator()
        let started = makeBook(key: "epub:retarget-started:1")
        let retargeted = makeBook(key: "epub:retarget-newer:2")
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        coordinator.present(for: started)
        coordinator.present(for: retargeted)   // retarget mid-flight
        coordinator.applyCover(makeImage(), for: started, baseDirectory: dir)

        #expect(CustomCoverStore.hasCover(for: started.fingerprintKey, baseDirectory: dir))
        #expect(!CustomCoverStore.hasCover(for: retargeted.fingerprintKey, baseDirectory: dir))
        #expect(coordinator.coverVersion == 1)
    }

    @Test func bumpCoverVersionIncrements() {
        let coordinator = CoverPickCoordinator()
        coordinator.bumpCoverVersion()
        coordinator.bumpCoverVersion()
        #expect(coordinator.coverVersion == 2)
    }

    @Test func resetClearsTransientPickState() {
        let coordinator = CoverPickCoordinator()
        coordinator.present(for: makeBook())
        coordinator.isPickerPresented = true
        coordinator.reset()
        #expect(coordinator.bookForCover == nil)
        #expect(coordinator.isPickerPresented == false)
        #expect(coordinator.pickedItem == nil)
    }

    @Test func applyCoverBumpsOncePerSuccessfulCall() {
        let coordinator = CoverPickCoordinator()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        coordinator.applyCover(
            makeImage(), for: makeBook(key: "epub:cover-a:1"), baseDirectory: dir)
        coordinator.applyCover(
            makeImage(), for: makeBook(key: "epub:cover-b:2"), baseDirectory: dir)
        #expect(coordinator.coverVersion == 2)
    }
}
