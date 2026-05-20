// Purpose: Tests for ReaderTapZoneRouter — the side-tap → page-turn producer
// restored after Bug #239 (feature #54 WI-3 deleted the previous TapZoneOverlay
// mount, leaving every native reader's `.readerNextPage` / `.readerPreviousPage`
// observer dead).
//
// The router maps a tap's x-coordinate + the current layout preference to a
// concrete TapAction, and the `dispatchAndPost` overload broadcasts the result
// over NotificationCenter (the existing notification names every native reader
// container already observes).
//
// Invariants under test:
// - In .paged layout, side zones post .readerNextPage / .readerPreviousPage; the
//   center zone posts .readerContentTapped.
// - In .scroll layout (and when layout is nil), every zone posts only
//   .readerContentTapped — side-tap navigation is paged-mode-only.
// - Custom TapZoneConfig mappings are honored (matches the legacy
//   TapZoneDispatcher contract).
//
// @coordinates-with: ReaderTapZoneRouter.swift, TapZoneConfig.swift,
//                    ReaderNotifications.swift, EPUBLayoutPreference.swift

import XCTest
import Foundation
@testable import vreader

final class ReaderTapZoneRouterTests: XCTestCase {

    // MARK: - Pure dispatch (no notification side effects)

    func test_paged_leftZone_resolvesToPreviousPage() {
        let action = ReaderTapZoneRouter.action(
            x: 50, totalWidth: 1000, layout: .paged
        )
        XCTAssertEqual(action, .previousPage)
    }

    func test_paged_centerZone_resolvesToToggleChrome() {
        let action = ReaderTapZoneRouter.action(
            x: 500, totalWidth: 1000, layout: .paged
        )
        XCTAssertEqual(action, .toggleChrome)
    }

    func test_paged_rightZone_resolvesToNextPage() {
        let action = ReaderTapZoneRouter.action(
            x: 900, totalWidth: 1000, layout: .paged
        )
        XCTAssertEqual(action, .nextPage)
    }

    func test_scroll_leftZone_resolvesToToggleChrome_notPreviousPage() {
        let action = ReaderTapZoneRouter.action(
            x: 50, totalWidth: 1000, layout: .scroll
        )
        XCTAssertEqual(action, .toggleChrome)
    }

    func test_scroll_rightZone_resolvesToToggleChrome_notNextPage() {
        let action = ReaderTapZoneRouter.action(
            x: 900, totalWidth: 1000, layout: .scroll
        )
        XCTAssertEqual(action, .toggleChrome)
    }

    func test_nilLayout_anyZone_resolvesToToggleChrome() {
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 50, totalWidth: 1000, layout: nil),
            .toggleChrome
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 500, totalWidth: 1000, layout: nil),
            .toggleChrome
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 900, totalWidth: 1000, layout: nil),
            .toggleChrome
        )
    }

    // MARK: - Edge cases

    func test_paged_zeroWidth_resolvesToCenter() {
        // Defensive — degenerate width falls through to .center per TapZoneConfig.
        let action = ReaderTapZoneRouter.action(
            x: 0, totalWidth: 0, layout: .paged
        )
        XCTAssertEqual(action, .toggleChrome)
    }

    func test_paged_negativeX_resolvesToPreviousPage() {
        let action = ReaderTapZoneRouter.action(
            x: -10, totalWidth: 1000, layout: .paged
        )
        XCTAssertEqual(action, .previousPage)
    }

    func test_paged_xExceedsWidth_resolvesToNextPage() {
        let action = ReaderTapZoneRouter.action(
            x: 1500, totalWidth: 1000, layout: .paged
        )
        XCTAssertEqual(action, .nextPage)
    }

    // MARK: - Custom config

    func test_paged_customConfig_isHonored() {
        let config = TapZoneConfig(
            leftAction: .toggleChrome,
            centerAction: .none,
            rightAction: .previousPage
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 50, totalWidth: 1000, layout: .paged, config: config),
            .toggleChrome
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 500, totalWidth: 1000, layout: .paged, config: config),
            .none
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 900, totalWidth: 1000, layout: .paged, config: config),
            .previousPage
        )
    }

    func test_scroll_customConfig_stillCollapsesToToggleChrome() {
        // The layout gate must take precedence over the custom mapping —
        // scroll mode never produces page-turn notifications.
        let config = TapZoneConfig(
            leftAction: .nextPage,
            centerAction: .previousPage,
            rightAction: .nextPage
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 50, totalWidth: 1000, layout: .scroll, config: config),
            .toggleChrome
        )
        XCTAssertEqual(
            ReaderTapZoneRouter.action(x: 500, totalWidth: 1000, layout: .scroll, config: config),
            .toggleChrome
        )
    }

    // MARK: - dispatch posts the correct notification

    func test_dispatch_pagedLeft_postsReaderPreviousPage() {
        let exp = expectation(description: "readerPreviousPage posted")
        nonisolated(unsafe) var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in
            posted = true
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ReaderTapZoneRouter.dispatch(x: 50, totalWidth: 1000, layout: .paged)

        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(posted)
    }

    func test_dispatch_pagedRight_postsReaderNextPage() {
        let exp = expectation(description: "readerNextPage posted")
        let token = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ReaderTapZoneRouter.dispatch(x: 900, totalWidth: 1000, layout: .paged)

        wait(for: [exp], timeout: 1.0)
    }

    func test_dispatch_pagedCenter_postsReaderContentTapped() {
        let exp = expectation(description: "readerContentTapped posted")
        let token = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ReaderTapZoneRouter.dispatch(x: 500, totalWidth: 1000, layout: .paged)

        wait(for: [exp], timeout: 1.0)
    }

    func test_dispatch_scrollLeft_postsReaderContentTapped_notPreviousPage() {
        let exp = expectation(description: "readerContentTapped posted")
        nonisolated(unsafe) var previousPagePosted = false
        let contentToken = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        let prevToken = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in previousPagePosted = true }
        defer {
            NotificationCenter.default.removeObserver(contentToken)
            NotificationCenter.default.removeObserver(prevToken)
        }

        ReaderTapZoneRouter.dispatch(x: 50, totalWidth: 1000, layout: .scroll)

        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(previousPagePosted,
            ".readerPreviousPage MUST NOT fire in scroll layout")
    }

    func test_dispatch_nilLayout_postsReaderContentTapped() {
        let exp = expectation(description: "readerContentTapped posted")
        let token = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ReaderTapZoneRouter.dispatch(x: 900, totalWidth: 1000, layout: nil)

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - .none action posts nothing (legacy contract from TapZoneDispatcher)

    func test_dispatch_pagedWithNoneAction_postsNothing() {
        let config = TapZoneConfig(
            leftAction: .none, centerAction: .none, rightAction: .none
        )
        nonisolated(unsafe) var fired = false
        let names: [Notification.Name] = [
            .readerNextPage, .readerPreviousPage, .readerContentTapped
        ]
        let tokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in fired = true }
        }
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }

        ReaderTapZoneRouter.dispatch(x: 50, totalWidth: 1000, layout: .paged, config: config)
        ReaderTapZoneRouter.dispatch(x: 500, totalWidth: 1000, layout: .paged, config: config)
        ReaderTapZoneRouter.dispatch(x: 900, totalWidth: 1000, layout: .paged, config: config)

        // Spin briefly so any erroneously-posted notifications drain.
        let drain = expectation(description: "drain runloop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drain.fulfill() }
        wait(for: [drain], timeout: 0.5)

        XCTAssertFalse(fired,
            "no notification should fire when all zones map to .none")
    }
}
