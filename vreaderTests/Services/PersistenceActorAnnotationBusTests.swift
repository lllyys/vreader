// Feature #86 WI-2: the `.readerAnnotationsDidChange` mutation-complete bus.
// Every PersistenceActor annotation mutation chokepoint posts the bus AFTER a
// successful save; an idempotent no-op (delete of a missing record) does NOT.
// XCTest because it needs XCTestExpectation for the NotificationCenter timing.

import XCTest
import SwiftData
@testable import vreader

final class PersistenceActorAnnotationBusTests: XCTestCase {

    private var container: ModelContainer!
    private var persistence: PersistenceActor!
    private var fp: DocumentFingerprint!

    override func setUp() async throws {
        let schema = Schema(SchemaV8.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        persistence = PersistenceActor(modelContainer: container)
        fp = DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 4096, format: .txt
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey, title: "Bus Book", author: nil,
            coverImagePath: nil, fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil, addedAt: Date()
        )
        _ = try await persistence.insertBook(record)
    }

    override func tearDown() {
        container = nil
        persistence = nil
        fp = nil
    }

    private func locator(_ offset: Int) -> Locator {
        LocatorFactory.txtPosition(fingerprint: fp, charOffsetUTF16: offset)!
    }

    /// Counts `.readerAnnotationsDidChange` deliveries DETERMINISTICALLY: the
    /// observer is registered with `queue: nil`, so `NotificationCenter.post`
    /// delivers SYNCHRONOUSLY on the posting thread (inside the actor mutation,
    /// before it returns). After `await body()` completes, the `await` is a
    /// happens-before barrier, so every post is already counted — no queue-flush
    /// ordering ambiguity (`OperationQueue.main` ≠ the `MainActor` executor).
    private func countBusPosts(during body: () async throws -> Void) async throws -> Int {
        nonisolated(unsafe) var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: .readerAnnotationsDidChange, object: nil, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        try await body()
        return count
    }

    /// Asserts the bus fires EXACTLY once.
    private func expectBusPosts(
        _ description: String, _ body: () async throws -> Void
    ) async throws {
        let n = try await countBusPosts(during: body)
        XCTAssertEqual(n, 1, "\(description): expected exactly one post, got \(n)")
    }

    /// Asserts the bus fires at least `count` times (import posts once per item).
    private func expectBusPosts(
        atLeast count: Int, _ description: String, _ body: () async throws -> Void
    ) async throws {
        let n = try await countBusPosts(during: body)
        XCTAssertGreaterThanOrEqual(n, count, "\(description): expected ≥\(count) posts, got \(n)")
    }

    /// Runs `body` and asserts the bus does NOT fire (deterministic synchronous count).
    private func expectBusSilent(
        _ description: String, _ body: () async throws -> Void
    ) async throws {
        let n = try await countBusPosts(during: body)
        XCTAssertEqual(n, 0, "\(description): expected no post, got \(n)")
    }

    func test_addHighlight_postsBus() async throws {
        try await expectBusPosts("addHighlight posts") {
            _ = try await self.persistence.addHighlight(
                locator: self.locator(10), selectedText: "phrase",
                color: "yellow", note: nil, toBookWithKey: self.fp.canonicalKey
            )
        }
    }

    func test_removeHighlight_postsBus() async throws {
        let h = try await persistence.addHighlight(
            locator: locator(20), selectedText: "x", color: "green", note: nil,
            toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("removeHighlight posts") {
            try await self.persistence.removeHighlight(highlightId: h.highlightId)
        }
    }

    func test_updateHighlightNote_postsBus() async throws {
        let h = try await persistence.addHighlight(
            locator: locator(30), selectedText: "y", color: "blue", note: nil,
            toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("updateHighlightNote posts") {
            try await self.persistence.updateHighlightNote(
                highlightId: h.highlightId, note: "added"
            )
        }
    }

    func test_addBookmark_postsBus() async throws {
        try await expectBusPosts("addBookmark posts") {
            _ = try await self.persistence.addBookmark(
                locator: self.locator(40), title: "bm", toBookWithKey: self.fp.canonicalKey
            )
        }
    }

    func test_addAnnotation_postsBus() async throws {
        try await expectBusPosts("addAnnotation posts") {
            _ = try await self.persistence.addAnnotation(
                locator: self.locator(50), content: "a standalone note",
                toBookWithKey: self.fp.canonicalKey
            )
        }
    }

    func test_removeAnnotation_postsBus() async throws {
        let a = try await persistence.addAnnotation(
            locator: locator(60), content: "note", toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("removeAnnotation posts") {
            try await self.persistence.removeAnnotation(annotationId: a.annotationId)
        }
    }

    func test_updateHighlightColor_postsBus() async throws {
        let h = try await persistence.addHighlight(
            locator: locator(70), selectedText: "z", color: "yellow", note: nil,
            toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("updateHighlightColor posts") {
            try await self.persistence.updateHighlightColor(
                highlightId: h.highlightId, color: "green"
            )
        }
    }

    func test_removeBookmark_postsBus() async throws {
        let b = try await persistence.addBookmark(
            locator: locator(80), title: "bm", toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("removeBookmark posts") {
            try await self.persistence.removeBookmark(bookmarkId: b.bookmarkId)
        }
    }

    func test_updateBookmarkTitle_postsBus() async throws {
        let b = try await persistence.addBookmark(
            locator: locator(90), title: "old", toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("updateBookmarkTitle posts") {
            try await self.persistence.updateBookmarkTitle(
                bookmarkId: b.bookmarkId, title: "new"
            )
        }
    }

    func test_updateAnnotation_postsBus() async throws {
        let a = try await persistence.addAnnotation(
            locator: locator(100), content: "old note", toBookWithKey: fp.canonicalKey
        )
        try await expectBusPosts("updateAnnotation posts") {
            try await self.persistence.updateAnnotation(
                annotationId: a.annotationId, content: "edited note"
            )
        }
    }

    /// Import goes through the same `addHighlight`/`addAnnotation` chokepoints, so
    /// each imported item posts the bus. Two items → at least two posts.
    func test_import_postsBusPerItem() async throws {
        let importer = AnnotationImporter(
            highlightStore: persistence,
            bookmarkStore: persistence,
            annotationStore: persistence
        )
        let payload = AnnotationExportPayload(
            bookTitle: "Bus Book", bookAuthor: nil,
            exportedAt: Date(timeIntervalSince1970: 0),
            annotations: [
                ExportedAnnotation(
                    id: UUID(), type: .highlight, chapter: nil,
                    selectedText: "first", note: nil, color: "yellow", title: nil,
                    createdAt: Date(timeIntervalSince1970: 0),
                    updatedAt: Date(timeIntervalSince1970: 0)
                ),
                ExportedAnnotation(
                    id: UUID(), type: .note, chapter: nil,
                    selectedText: nil, note: "second", color: nil, title: nil,
                    createdAt: Date(timeIntervalSince1970: 0),
                    updatedAt: Date(timeIntervalSince1970: 0)
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        try await expectBusPosts(atLeast: 2, "import posts per item") {
            _ = try await importer.importJSON(
                data: data, bookFingerprintKey: self.fp.canonicalKey
            )
        }
    }

    /// A delete of a non-existent record is an idempotent no-op — no save, no bus.
    func test_removeHighlight_noOp_doesNotPost() async throws {
        try await expectBusSilent("no-op remove is silent") {
            try await self.persistence.removeHighlight(highlightId: UUID())
        }
    }

    /// A throwing mutation (update of a missing record) must NOT post — it never
    /// reaches `save()`.
    func test_updateAnnotation_missing_throwsAndDoesNotPost() async throws {
        try await expectBusSilent("throwing mutation is silent") {
            do {
                try await self.persistence.updateAnnotation(
                    annotationId: UUID(), content: "x"
                )
                XCTFail("expected updateAnnotation to throw for a missing record")
            } catch {
                // expected
            }
        }
    }
}
