// Purpose: Bridge-level integration tests for Bug #239's side-tap → page-turn
// producer restoration. The unit tests in `ReaderTapZoneRouterTests` cover
// the routing logic; these tests verify that the native bridges' tap handlers
// actually call `ReaderTapZoneRouter.dispatch` with the right coordinates so
// the `.readerNextPage` / `.readerPreviousPage` consumers wake up.
//
// We exercise the TXT path (`TXTTextViewBridge.Coordinator.handleContentTap`)
// directly with a real UITextView fixture — the UIKit gesture system is hard
// to simulate from XCTest, so we synthesize a `UITapGestureRecognizer` and
// fold a stub `location(in:)` through subclassing. The chunked TXT path
// (`TXTChunkedReaderBridge.Coordinator.handleContentTap`) follows the same
// shape.
//
// The PDF / EPUB / Foliate paths route through more UIKit / WKWebView surface
// area that XCTest cannot drive without an instance of the host; those are
// covered by the unit test on `ReaderTapZoneRouter` (the function the bridges
// all call into) plus the on-device verification in `dev-docs/verification/`.
//
// @coordinates-with: ReaderTapZoneRouter.swift, TXTTextViewBridge.swift,
//                    TXTTextViewBridgeCoordinator.swift,
//                    TXTChunkedReaderBridge.swift, ReaderNotifications.swift

import XCTest
import UIKit
@testable import vreader

/// Subclass of UITapGestureRecognizer that lets the test set a deterministic
/// `location(in:)` return value — the production UIKit machinery doesn't fire
/// our recognizer in an XCTest context, so we stub the geometry.
@MainActor
private final class FakeTapRecognizer: UITapGestureRecognizer {
    var stubLocation: CGPoint = .zero
    var stubView: UIView?

    override func location(in view: UIView?) -> CGPoint {
        return stubLocation
    }

    override var view: UIView? {
        return stubView
    }
}

@MainActor
final class ReaderBridgeSideTapWiringTests: XCTestCase {

    // MARK: - TXT non-chunked path (TXTTextViewBridge.Coordinator)

    func test_txtBridge_pagedLeftZoneTap_postsPreviousPage() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.pagedLayout = .paged

        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        coordinator.activeTextView = textView

        let gesture = FakeTapRecognizer()
        gesture.stubView = textView
        gesture.stubLocation = CGPoint(x: 50, y: 500)

        let exp = expectation(description: "previousPage")
        nonisolated(unsafe) var nextPageFired = false
        let prevToken = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let nextToken = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in nextPageFired = true }
        defer {
            NotificationCenter.default.removeObserver(prevToken)
            NotificationCenter.default.removeObserver(nextToken)
        }

        coordinator.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(nextPageFired)
    }

    func test_txtBridge_pagedRightZoneTap_postsNextPage() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.pagedLayout = .paged

        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        coordinator.activeTextView = textView

        let gesture = FakeTapRecognizer()
        gesture.stubView = textView
        gesture.stubLocation = CGPoint(x: 900, y: 500)

        let exp = expectation(description: "nextPage")
        let token = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
    }

    func test_txtBridge_pagedCenterTap_postsContentTapped() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.pagedLayout = .paged

        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        coordinator.activeTextView = textView

        let gesture = FakeTapRecognizer()
        gesture.stubView = textView
        gesture.stubLocation = CGPoint(x: 500, y: 500)

        let exp = expectation(description: "contentTapped")
        let token = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
    }

    func test_txtBridge_scrollLeftZoneTap_postsContentTapped_notPreviousPage() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.pagedLayout = .scroll

        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        coordinator.activeTextView = textView

        let gesture = FakeTapRecognizer()
        gesture.stubView = textView
        gesture.stubLocation = CGPoint(x: 50, y: 500)

        let exp = expectation(description: "contentTapped")
        nonisolated(unsafe) var prevPageFired = false
        let contentToken = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let prevToken = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in prevPageFired = true }
        defer {
            NotificationCenter.default.removeObserver(contentToken)
            NotificationCenter.default.removeObserver(prevToken)
        }

        coordinator.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(prevPageFired, "scroll-mode side-tap MUST NOT fire .readerPreviousPage")
    }

    func test_txtBridge_nilLayout_pagedLooksLikeSideTap_postsContentTapped_notPageTurn() {
        // The default (unwired) state — `pagedLayout` is nil. The router
        // must treat this as scroll-equivalent (every tap → toggleChrome)
        // so existing callers that have not yet been threaded through
        // continue to behave the legacy way.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        XCTAssertNil(coordinator.pagedLayout, "precondition: default is nil")

        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        coordinator.activeTextView = textView

        let gesture = FakeTapRecognizer()
        gesture.stubView = textView
        gesture.stubLocation = CGPoint(x: 900, y: 500)  // would be right-zone in paged

        let exp = expectation(description: "contentTapped")
        nonisolated(unsafe) var nextPageFired = false
        let contentToken = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let nextToken = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in nextPageFired = true }
        defer {
            NotificationCenter.default.removeObserver(contentToken)
            NotificationCenter.default.removeObserver(nextToken)
        }

        coordinator.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(nextPageFired, "nil layout MUST NOT fire .readerNextPage")
    }
}
