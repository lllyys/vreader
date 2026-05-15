// Purpose: Tests for `HighlightCoordinator.handleTapAction(_:highlightID:)`
// added by Feature #53 / GH #596 WI-1. Verifies the `.delete` path calls
// persistence.removeHighlight + posts `.readerHighlightRemoved` so the
// existing bug-#78 visual-clear pipeline runs.
//
// Reuses HighlightCoordinatorTests' Mock helpers via fresh local copies
// (avoids cross-file private symbol coupling — Swift Testing test files
// don't share `private` types).
//
// @coordinates-with: HighlightCoordinator.swift, HighlightTapAction.swift,
//   HighlightRenderer.swift, HighlightPersisting.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

private let tapTestFP = DocumentFingerprint(
    contentSHA256: "tap_test_sha256_0000000000000000000000000000000000000000",
    fileByteCount: 100,
    format: .txt
)

@MainActor
private final class TapMockRenderer: HighlightRenderer {
    var removedIds: [UUID] = []
    var appliedRecords: [HighlightRecord] = []
    var restoreCalls = 0

    func apply(record: HighlightRecord) { appliedRecords.append(record) }
    func remove(id: UUID) { removedIds.append(id) }
    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) { restoreCalls += 1 }
}

private final class TapMockPersistence: HighlightPersisting, @unchecked Sendable {
    var removeCallCount = 0
    var removedIds: [UUID] = []
    var shouldThrowOnRemove = false

    func addHighlight(
        locator: Locator, selectedText: String, color: String,
        note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        try await addHighlight(
            locator: locator, anchor: nil, selectedText: selectedText,
            color: color, note: note, toBookWithKey: key
        )
    }

    func addHighlight(
        locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
        color: String, note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        HighlightRecord(
            highlightId: UUID(), locator: locator, anchor: anchor,
            profileKey: "\(key):hash", selectedText: selectedText, color: color,
            note: note, createdAt: Date(), updatedAt: Date()
        )
    }

    func removeHighlight(highlightId: UUID) async throws {
        if shouldThrowOnRemove { throw NSError(domain: "test", code: 1) }
        removeCallCount += 1
        removedIds.append(highlightId)
    }

    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}
    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] { [] }
}

@Suite("HighlightCoordinator.handleTapAction")
struct HighlightCoordinatorTapHandlerTests {

    @Test @MainActor
    func handleTapAction_delete_callsPersistenceRemove() async {
        let renderer = TapMockRenderer()
        let persistence = TapMockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )
        let id = UUID()

        await coordinator.handleTapAction(.delete, highlightID: id)

        #expect(persistence.removeCallCount == 1)
        #expect(persistence.removedIds == [id])
    }

    @Test @MainActor
    func handleTapAction_delete_postsHighlightRemovedNotification() async {
        let renderer = TapMockRenderer()
        let persistence = TapMockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )
        let id = UUID()
        // Filter for the specific UUID to avoid cross-pollination with
        // concurrently-running tests on Swift Testing's parallel runner.
        let expectedString = id.uuidString
        let captured = LockedBox<String?>(nil)
        let captureToken = NotificationCenter.default.addObserver(
            forName: .readerHighlightRemoved,
            object: nil,
            queue: .main
        ) { notification in
            if let s = notification.object as? String, s == expectedString {
                captured.set(s)
            }
        }
        defer { NotificationCenter.default.removeObserver(captureToken) }

        await coordinator.handleTapAction(.delete, highlightID: id)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(captured.value == id.uuidString)
    }

    @Test @MainActor
    func handleTapAction_delete_persistenceFailure_doesNotPostNotification() async {
        let renderer = TapMockRenderer()
        let persistence = TapMockPersistence()
        persistence.shouldThrowOnRemove = true
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )
        let id = UUID()
        let expectedString = id.uuidString
        let captured = LockedBox<String?>(nil)
        let captureToken = NotificationCenter.default.addObserver(
            forName: .readerHighlightRemoved,
            object: nil,
            queue: .main
        ) { notification in
            // Only set if THIS test's UUID arrives — other parallel tests
            // posting their own UUIDs are filtered out.
            if let s = notification.object as? String, s == expectedString {
                captured.set(s)
            }
        }
        defer { NotificationCenter.default.removeObserver(captureToken) }

        await coordinator.handleTapAction(.delete, highlightID: id)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Persistence failed → no notification with THIS test's UUID.
        #expect(captured.value == nil)
        // And the persistence mock should have NOT counted a successful remove.
        #expect(persistence.removeCallCount == 0)
    }
}

/// Tiny thread-safe box used to capture notification payloads from the main
/// queue into the test assertion thread.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ initial: T) { self._value = initial }

    func set(_ newValue: T) {
        lock.lock(); defer { lock.unlock() }
        _value = newValue
    }

    var value: T {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}
#endif
