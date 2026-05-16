// Purpose: Feature #60 WI-6c — pins the reader More-menu popover's
// row → action/notification routing contract. `ReaderMorePopover`
// renders these rows declaratively and `ReaderContainerView` observes
// the posted notifications; a swapped mapping would silently open the
// wrong surface, so the contract is pinned here before any SwiftUI
// render path runs.
//
// Design source:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// + `design-notes/reader-search-and-more-menu.md` §2. The design
// depicts six rows; WI-6c ships five — the Bilingual row is deferred
// (GH #790, no backing toggle state). These tests pin the shipped
// five-row contract.
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderMorePopover.swift,
//   ReaderNotifications.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #60 WI-6c — ReaderMoreMenuRow contract")
struct ReaderMoreMenuRowTests {

    // MARK: - Cardinality + order

    @Test("Menu has exactly 5 rows (design's 6 minus deferred Bilingual)")
    func rowCount() {
        #expect(ReaderMoreMenuRow.allCases.count == 5)
    }

    @Test("Row order matches the design bundle (vreader-more.jsx)")
    func rowOrder() {
        // Mirrors `vreader-more.jsx` top → bottom minus the deferred
        // Bilingual row (GH #790): Read aloud / Auto-turn pages /
        // (divider) / Book details / Share book / Export annotations.
        #expect(ReaderMoreMenuRow.allCases == [
            .readAloud, .autoTurnPages,
            .bookDetails, .shareBook, .exportAnnotations,
        ])
    }

    @Test("Bilingual mode is not a shipped row (deferred — GH #790)")
    func bilingualRowAbsent() {
        // The design's Bilingual row has no backing toggle state;
        // shipping it would be self-designed UI (rule 51). Pin its
        // absence so a future re-add is a deliberate, tested change.
        #expect(!ReaderMoreMenuRow.allCases.contains { $0.rawValue == "bilingualMode" })
    }

    // MARK: - Divider placement

    @Test("Divider sits after Auto-turn pages (before Book details)")
    func dividerPlacement() {
        // The design draws one hairline divider between the
        // reading-controls cluster and the book-action cluster. In the
        // design it follows Bilingual; with that row deferred it
        // follows Auto-turn — still the cluster boundary.
        #expect(ReaderMoreMenuRow.dividerAfter == .autoTurnPages)
    }

    // MARK: - Toggle vs tap rows

    @Test("Auto-turn pages is the only toggle row")
    func toggleRowIdentity() {
        // `vreader-more.jsx` draws a ToggleSwitch on Auto-turn. It has
        // real backing state (`ReaderSettingsStore.autoPageTurn`).
        // Pin: exactly one toggle row, and it's Auto-turn.
        #expect(ReaderMoreMenuRow.autoTurnPages.isToggle)
        #expect(!ReaderMoreMenuRow.readAloud.isToggle)
        #expect(!ReaderMoreMenuRow.bookDetails.isToggle)
        #expect(!ReaderMoreMenuRow.shareBook.isToggle)
        #expect(!ReaderMoreMenuRow.exportAnnotations.isToggle)
        #expect(ReaderMoreMenuRow.allCases.filter(\.isToggle).count == 1)
    }

    // MARK: - Row → notification routing (exhaustive)

    @Test("Read aloud routes to .readerMoreReadAloud")
    func readAloudRoutes() {
        #expect(ReaderMoreMenuRow.readAloud.notification == .readerMoreReadAloud)
    }

    @Test("Auto-turn pages routes to .readerMoreToggleAutoTurn")
    func autoTurnRoutes() {
        #expect(ReaderMoreMenuRow.autoTurnPages.notification == .readerMoreToggleAutoTurn)
    }

    @Test("Book details routes to .readerMoreBookDetails")
    func bookDetailsRoutes() {
        // Destination Book Details sheet is undesigned (design note
        // §4); GH #789 tracks it. WI-6c routes the row to the existing
        // reader settings panel — the design prototype's own interim
        // punt (`vreader-more.jsx`/`vreader-reader.jsx`:
        // `onAction('details') → onOpenSettings`). The notification is
        // the seam; the container picks the interim destination.
        #expect(ReaderMoreMenuRow.bookDetails.notification == .readerMoreBookDetails)
    }

    @Test("Share book routes to .readerMoreShareBook")
    func shareBookRoutes() {
        #expect(ReaderMoreMenuRow.shareBook.notification == .readerMoreShareBook)
    }

    @Test("Export annotations routes to .readerMoreExportAnnotations")
    func exportAnnotationsRoutes() {
        #expect(ReaderMoreMenuRow.exportAnnotations.notification == .readerMoreExportAnnotations)
    }

    @Test("Every row maps to a distinct notification")
    func everyRowMapsToDistinctNotification() {
        // Exhaustive over the enum — a future row without a mapping,
        // or a duplicated mapping, fails here.
        let names = ReaderMoreMenuRow.allCases.map(\.notification)
        #expect(Set(names).count == ReaderMoreMenuRow.allCases.count)
    }

    @Test("All More-menu notifications are namespaced under vreader.")
    func notificationsAreNamespaced() {
        for row in ReaderMoreMenuRow.allCases {
            #expect(row.notification.rawValue.hasPrefix("vreader."))
        }
    }

    // MARK: - Inverse routing (notification → row)

    @Test("Each row round-trips through notification and back")
    func notificationRoundTrips() {
        // `ReaderMoreMenuActionObservers` resolves a tapped row from
        // the observed notification name via `init?(notification:)`.
        // A drift between `.notification` and the inverse breaks the
        // popover's action funnel — pin the round-trip exhaustively.
        for row in ReaderMoreMenuRow.allCases {
            #expect(ReaderMoreMenuRow(notification: row.notification) == row)
        }
    }

    @Test("An unrelated notification name resolves to nil")
    func unrelatedNotificationIsNil() {
        // The observer modifier ignores names that aren't More-menu
        // rows. A non-More notification (or a typo'd name) must not
        // resolve to a row.
        #expect(ReaderMoreMenuRow(notification: .readerOpenContents) == nil)
        #expect(ReaderMoreMenuRow(notification: Notification.Name("vreader.bogus")) == nil)
    }

    // MARK: - Display strings

    @Test("Each row carries a non-empty label")
    func labelsNonEmpty() {
        for row in ReaderMoreMenuRow.allCases {
            #expect(!row.label.isEmpty, "row \(row) has empty label")
        }
    }

    @Test("Row labels match the design bundle text")
    func labelsMatchDesign() {
        #expect(ReaderMoreMenuRow.readAloud.label == "Read aloud")
        #expect(ReaderMoreMenuRow.autoTurnPages.label == "Auto-turn pages")
        #expect(ReaderMoreMenuRow.bookDetails.label == "Book details")
        #expect(ReaderMoreMenuRow.shareBook.label == "Share book")
        #expect(ReaderMoreMenuRow.exportAnnotations.label == "Export annotations")
    }

    @Test("Each row carries a non-empty SF Symbol name")
    func symbolNamesNonEmpty() {
        for row in ReaderMoreMenuRow.allCases {
            #expect(!row.systemImage.isEmpty, "row \(row) has empty systemImage")
        }
    }

    @Test("SF Symbol names are well-formed (no whitespace, no leading dot)")
    func symbolNamesWellFormed() {
        for row in ReaderMoreMenuRow.allCases {
            #expect(!row.systemImage.contains(" "), "row \(row) systemImage has a space")
            #expect(!row.systemImage.hasPrefix("."), "row \(row) systemImage starts with '.'")
        }
    }

    // MARK: - Stable accessibility identifiers

    @Test("Each row exposes a stable accessibility identifier")
    func accessibilityIdentifiers() {
        // XCUITest + verify-cron snapshots look these up. Stable
        // contract — do not rename without updating every harness.
        #expect(ReaderMoreMenuRow.readAloud.accessibilityIdentifier == "readerMoreReadAloud")
        #expect(ReaderMoreMenuRow.autoTurnPages.accessibilityIdentifier == "readerMoreAutoTurn")
        #expect(ReaderMoreMenuRow.bookDetails.accessibilityIdentifier == "readerMoreBookDetails")
        #expect(ReaderMoreMenuRow.shareBook.accessibilityIdentifier == "readerMoreShareBook")
        #expect(ReaderMoreMenuRow.exportAnnotations.accessibilityIdentifier == "readerMoreExportAnnotations")
    }

    @Test("Accessibility identifiers are all distinct")
    func accessibilityIdentifiersDistinct() {
        let ids = ReaderMoreMenuRow.allCases.map(\.accessibilityIdentifier)
        #expect(Set(ids).count == ReaderMoreMenuRow.allCases.count)
    }
}
