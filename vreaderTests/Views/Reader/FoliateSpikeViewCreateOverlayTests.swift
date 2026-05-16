// Purpose: Bug #207 / GH #765 — pins the cross-boundary contract for
// the Foliate `create-overlay` → highlight-restore bridge.
//
// The bug is that `FoliateSpikeView.Coordinator.handleMessage`
// registers `"create-overlay"` in its WKScriptMessageHandler name
// list (line 131) but has NO `case "create-overlay":` — falls
// through to `default: break`, so the JS event announcing a section
// is ready for overlay injection is silently dropped. Saved AZW3/
// MOBI highlights persist in SwiftData but never re-paint on reopen.
//
// The fix is a `case "create-overlay":` that parses the section
// index via `FoliateMessageParser.parseCreateOverlay` and posts
// `.foliateOverlayReadyForSection` carrying `sectionIndex` +
// `fingerprintKey`. A sibling view modifier (`FoliateSpikeView+
// Restore.swift`) observes that notification, queries persistence,
// and posts per-CFI `.foliateRequestAnnotationJSCreate` events the
// Coordinator's existing observer already evaluates.
//
// This test pins JUST the Coordinator → notification slice; the
// modifier's persistence-query slice is covered by the
// FoliateSpikeRestoreDispatch test suite (pure-logic helper).

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bug #207 — FoliateSpikeView `create-overlay` posts overlay-ready notification")
struct FoliateSpikeViewCreateOverlayTests {

    /// Reference holder for notification capture from a `.main`-queue
    /// observer that isn't statically known to Swift concurrency as
    /// MainActor-isolated.
    @MainActor
    private final class NotificationCapture {
        var fired: Bool = false
        var sectionIndex: Int?
        var fingerprintKey: String?
    }

    private func makeCoordinator(fingerprintKey: String?) -> FoliateSpikeView.Coordinator {
        let coord = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "paginated",
            onBookReady: { _ in },
            onError: { _ in }
        )
        coord.fingerprintKey = fingerprintKey
        return coord
    }

    @Test("posts .foliateOverlayReadyForSection with sectionIndex + fingerprintKey when fingerprintKey is set")
    func happyPath() async {
        let coordinator = makeCoordinator(fingerprintKey: "azw3:abc123:2048")

        let capture = NotificationCapture()
        // queue: nil → synchronous in-thread delivery on the same
        // thread that posts the notification. handleMessage is
        // @MainActor; the observer therefore also runs on MainActor.
        // We extract the userInfo values eagerly so the non-Sendable
        // `Notification` doesn't cross the assumeIsolated boundary
        // (Swift 6 strict concurrency).
        let token = NotificationCenter.default.addObserver(
            forName: .foliateOverlayReadyForSection, object: nil, queue: nil
        ) { note in
            let sectionIndex = note.userInfo?["sectionIndex"] as? Int
            let fingerprintKey = note.userInfo?["fingerprintKey"] as? String
            MainActor.assumeIsolated {
                capture.fired = true
                capture.sectionIndex = sectionIndex
                capture.fingerprintKey = fingerprintKey
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await coordinator.handleMessage(name: "create-overlay", body: ["index": 3])

        #expect(capture.fired,
                "Bug #207: FoliateSpikeView's Coordinator must post .foliateOverlayReadyForSection on create-overlay messages so the restore modifier fires")
        #expect(capture.sectionIndex == 3)
        #expect(capture.fingerprintKey == "azw3:abc123:2048")
    }

    @Test("section index 0 round-trips (foliate emits create-overlay for section 0 on book open)")
    func sectionZero() async {
        let coordinator = makeCoordinator(fingerprintKey: "azw3:abc:1")

        let capture = NotificationCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .foliateOverlayReadyForSection, object: nil, queue: nil
        ) { note in
            let sectionIndex = note.userInfo?["sectionIndex"] as? Int
            MainActor.assumeIsolated {
                capture.fired = true
                capture.sectionIndex = sectionIndex
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await coordinator.handleMessage(name: "create-overlay", body: ["index": 0])

        #expect(capture.fired)
        #expect(capture.sectionIndex == 0)
    }

    @Test("does NOT post when fingerprintKey is nil (preview/test harness)")
    func nilFingerprintKey() async {
        // FoliateSpikeView's Coordinator carries fingerprintKey as an
        // optional; preview / non-production harnesses can legitimately
        // run with no identity. Without a key, the restore modifier
        // can't route the highlights to the right reader, so the
        // coordinator must NOT emit the notification.
        let coordinator = makeCoordinator(fingerprintKey: nil)

        let capture = NotificationCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .foliateOverlayReadyForSection, object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated { capture.fired = true }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await coordinator.handleMessage(name: "create-overlay", body: ["index": 3])

        #expect(!capture.fired,
                "create-overlay with nil fingerprintKey must NOT post — downstream observers can't route the highlights")
    }

    @Test("malformed body (missing index) is silently dropped")
    func malformedBody() async {
        let coordinator = makeCoordinator(fingerprintKey: "azw3:abc:1")

        let capture = NotificationCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .foliateOverlayReadyForSection, object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated { capture.fired = true }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await coordinator.handleMessage(name: "create-overlay", body: ["unknown": "value"])

        #expect(!capture.fired,
                "Malformed create-overlay body must NOT post — drop rather than emit garbage userInfo")
    }
}
#endif
