// Purpose: Bug #215 / GH #837 regression test for the MD paged-mode tap
// routing. PR #1098 restored side-tap → page-turn for renderers that route
// through `TXTTextViewBridge` (TXT scroll mode, EPUB, AZW3, PDF). MD paged
// mode uses `NativeTextPagedView` whose `NativePagedContainer` had NO tap
// gesture at all — every tap (left, center, right) was inert, so the user
// could neither navigate nor toggle the chrome.
//
// These tests assert the same shape that `ReaderBridgeSideTapWiringTests`
// proves for TXT: paged-left → `.readerPreviousPage`, paged-right →
// `.readerNextPage`, paged-center → `.readerContentTapped`. Scroll layout
// collapses every tap to `.readerContentTapped`. Nil layout (unwired) is
// scroll-equivalent — preserves the legacy unhandled-tap behavior so a
// future caller that forgets to thread layout doesn't suddenly start
// firing page-turn events.
//
// The container exposes an `@objc handleContentTap(_:)` selector matching
// the bridge coordinator's, called by an internal `UITapGestureRecognizer`
// in production. We drive the selector directly with a `FakeTapRecognizer`
// (same pattern as `ReaderBridgeSideTapWiringTests`).
//
// @coordinates-with: NativeTextPagedView.swift, ReaderTapZoneRouter.swift,
//                    ReaderNotifications.swift, MDReaderContainerView.swift

import XCTest
import UIKit
@testable import vreader

/// Subclass of `UITapGestureRecognizer` that lets the test stub
/// `location(in:)`. UIKit's gesture system does not fire recognizers in an
/// XCTest context — we synthesize the geometry the production handler
/// reads. Mirrors `ReaderBridgeSideTapWiringTests.FakeTapRecognizer`.
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
final class NativeTextPagedViewSideTapTests: XCTestCase {

    // MARK: - Paged layout → side-tap routes to page-turn

    func test_pagedLeftZoneTap_postsPreviousPage() {
        let container = NativePagedContainer()
        container.pagedLayout = .paged
        container.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let gesture = FakeTapRecognizer()
        gesture.stubView = container
        gesture.stubLocation = CGPoint(x: 50, y: 500)

        let exp = expectation(description: "previousPage")
        nonisolated(unsafe) var nextFired = false
        let prevToken = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let nextToken = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in nextFired = true }
        defer {
            NotificationCenter.default.removeObserver(prevToken)
            NotificationCenter.default.removeObserver(nextToken)
        }

        container.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(nextFired)
    }

    func test_pagedRightZoneTap_postsNextPage() {
        let container = NativePagedContainer()
        container.pagedLayout = .paged
        container.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let gesture = FakeTapRecognizer()
        gesture.stubView = container
        gesture.stubLocation = CGPoint(x: 900, y: 500)

        let exp = expectation(description: "nextPage")
        let token = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        container.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
    }

    func test_pagedCenterTap_postsContentTapped() {
        let container = NativePagedContainer()
        container.pagedLayout = .paged
        container.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let gesture = FakeTapRecognizer()
        gesture.stubView = container
        gesture.stubLocation = CGPoint(x: 500, y: 500)

        let exp = expectation(description: "contentTapped")
        let token = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        container.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Scroll / nil layouts collapse to chrome-toggle

    func test_scrollLeftZoneTap_postsContentTapped_notPreviousPage() {
        let container = NativePagedContainer()
        container.pagedLayout = .scroll
        container.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let gesture = FakeTapRecognizer()
        gesture.stubView = container
        gesture.stubLocation = CGPoint(x: 50, y: 500)

        let exp = expectation(description: "contentTapped")
        nonisolated(unsafe) var prevFired = false
        let contentToken = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let prevToken = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in prevFired = true }
        defer {
            NotificationCenter.default.removeObserver(contentToken)
            NotificationCenter.default.removeObserver(prevToken)
        }

        container.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(prevFired, "scroll-mode tap MUST NOT fire .readerPreviousPage")
    }

    func test_nilLayout_rightZoneTap_postsContentTapped_notNextPage() {
        // Default (unwired) state: pagedLayout is nil. The router treats
        // this as scroll-equivalent (every tap → toggleChrome) so callers
        // that have not yet been threaded through behave the legacy way.
        let container = NativePagedContainer()
        XCTAssertNil(container.pagedLayout, "precondition: default is nil")
        container.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let gesture = FakeTapRecognizer()
        gesture.stubView = container
        gesture.stubLocation = CGPoint(x: 900, y: 500)  // would be right-zone in paged

        let exp = expectation(description: "contentTapped")
        nonisolated(unsafe) var nextFired = false
        let contentToken = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let nextToken = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in nextFired = true }
        defer {
            NotificationCenter.default.removeObserver(contentToken)
            NotificationCenter.default.removeObserver(nextToken)
        }

        container.handleContentTap(gesture)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(nextFired, "nil layout MUST NOT fire .readerNextPage")
    }
}
