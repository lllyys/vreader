// Purpose: Feature #60 WI-6b — pins the bottom-chrome toolbar's
// button → notification routing. `ReaderContainerView` observes these
// four notifications and presents the matching sheet/panel; a swapped
// mapping would silently open the wrong surface, so the contract is
// pinned here before any SwiftUI render path runs.
//
// @coordinates-with: ReaderBottomChrome.swift, ReaderChromeButton.swift,
//   ReaderNotifications.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #60 WI-6b — ReaderBottomChrome toolbar routing")
struct ReaderBottomChromeTests {

    @Test("Contents button posts .readerOpenContents")
    func contentsRoutesToOpenContents() {
        #expect(ReaderBottomChrome.notification(for: .contents) == .readerOpenContents)
    }

    @Test("Notes button posts .readerOpenNotes")
    func notesRoutesToOpenNotes() {
        #expect(ReaderBottomChrome.notification(for: .notes) == .readerOpenNotes)
    }

    @Test("Display button posts .readerOpenDisplay")
    func displayRoutesToOpenDisplay() {
        #expect(ReaderBottomChrome.notification(for: .display) == .readerOpenDisplay)
    }

    @Test("AI button posts .readerOpenAI")
    func aiRoutesToOpenAI() {
        #expect(ReaderBottomChrome.notification(for: .ai) == .readerOpenAI)
    }

    @Test("Every toolbar button maps to a distinct notification")
    func everyButtonMapsToDistinctNotification() {
        // Exhaustive over the enum — a future 5th button without a
        // mapping, or a duplicated mapping, fails here.
        let names = ReaderBottomChromeButton.allCases.map {
            ReaderBottomChrome.notification(for: $0)
        }
        #expect(Set(names).count == ReaderBottomChromeButton.allCases.count)
    }

    @Test("Toolbar notifications are namespaced under vreader.")
    func notificationsAreNamespaced() {
        for button in ReaderBottomChromeButton.allCases {
            let raw = ReaderBottomChrome.notification(for: button).rawValue
            #expect(raw.hasPrefix("vreader."))
        }
    }
}
