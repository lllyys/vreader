// Purpose: RED test for bug #108 — AZW3/Foliate reader center tap doesn't
// toggle chrome. FoliateSpikeView's Coordinator handled `bridge-ready`,
// `book-ready`, and `error` messages but no-oped on the `tap` message
// the JS bundle posts on center taps. The chrome-toggle path
// (`.readerContentTapped` notification observed by `ReaderContainerView`)
// never fired.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bug #108 — FoliateSpikeView center tap toggles chrome")
struct FoliateSpikeViewTapTests {

    /// Reference holder for notification capture from a notification
    /// observer that runs on `.main` queue but isn't statically known
    /// to Swift concurrency as MainActor-isolated.
    @MainActor
    private final class NotificationCapture {
        var fired: Bool = false
    }

    @Test func tapMessage_postsReaderContentTappedNotification() async {
        let coordinator = FoliateSpikeView.Coordinator(
            onBookReady: { _ in },
            onError: { _ in }
        )

        let capture = NotificationCapture()
        // queue: nil → synchronous in-thread delivery on the same
        // thread that posts the notification. The handleMessage call
        // is @MainActor, the post happens on MainActor, and our
        // observer runs synchronously inside the post — no runloop
        // drain needed and no flake under load.
        let token = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated { capture.fired = true }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await coordinator.handleMessage(name: "tap", body: NSNull())

        #expect(capture.fired,
                "Bug #108: FoliateSpikeView's Coordinator must post `.readerContentTapped` on `tap` messages so ReaderContainerView's chrome-toggle observer fires")
    }
}
#endif
