// Purpose: Feature #60 WI-6c / Feature #56 WI-8 — pins the reader
// More-menu popover's row → action/notification routing contract.
// `ReaderMorePopover` renders these rows declaratively and
// `ReaderContainerView` observes the posted notifications; a swapped
// mapping would silently open the wrong surface, so the contract is
// pinned here before any SwiftUI render path runs.
//
// Design source:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// + `design-notes/reader-search-and-more-menu.md` §2
// + `design-notes/feature-60-followups.md` §2.3 (bilingual row's
//   3-way Off / On / Unavailable presentation reinstated in WI-8)
// + `design-notes/needs-design-issues.md` §#864 (per-chapter
//   re-translate row, conditional on `bilingualOn`).
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderMorePopover.swift,
//   ReaderNotifications.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #60 WI-6c / Feature #56 WI-8 — ReaderMoreMenuRow contract")
struct ReaderMoreMenuRowTests {

    // MARK: - Cardinality + order

    @Test("Menu enumerates the seven design rows (Bilingual + Re-translate reinstated)")
    func rowCount() {
        // WI-8 reinstates the Bilingual row (formerly deferred under
        // GH #790) and adds the conditional Re-translate row. The
        // declared enum carries both as cases; `visibleRows` gates
        // Re-translate on bilingual on/off.
        #expect(ReaderMoreMenuRow.allCases.count == 7)
    }

    @Test("Row order matches the design bundle (vreader-more.jsx + feature-60-followups §2.3)")
    func rowOrder() {
        // Top → bottom: Read aloud / Auto-turn pages / Bilingual mode /
        // Re-translate chapter (conditional) / (divider) / Book details /
        // Share book / Export annotations.
        #expect(ReaderMoreMenuRow.allCases == [
            .readAloud, .autoTurnPages, .bilingual, .reTranslateChapter,
            .bookDetails, .shareBook, .exportAnnotations,
        ])
    }

    @Test("Bilingual mode IS a shipped row (WI-8 reinstates it — formerly GH #790)")
    func bilingualRowShipped() {
        // The WI-6c "deferred" note is gone — design §2.3 lands the
        // 3-way TrailingControl that gives the row real backing state.
        // Pin its presence + raw value so a future regression that
        // removes the case is a deliberate, tested change.
        #expect(ReaderMoreMenuRow.allCases.contains(.bilingual))
        #expect(ReaderMoreMenuRow.bilingual.rawValue == "bilingual")
    }

    // MARK: - Divider placement

    @Test("Static divider anchor is Bilingual mode")
    func dividerPlacement() {
        // The static `dividerAfter` is the canonical cluster boundary
        // when the conditional re-translate row is hidden. When the
        // re-translate row is visible, the runtime anchor slides one
        // row down — covered by `ReaderMoreMenuBilingualTests`.
        #expect(ReaderMoreMenuRow.dividerAfter == .bilingual)
    }

    // MARK: - Toggle vs tap rows

    @Test("Auto-turn pages is the only row reporting isToggle=true")
    func toggleRowIdentity() {
        // The legacy `isToggle` boolean is preserved for backward
        // compat. Only Auto-turn returns `true` — the bilingual row's
        // 3-way presentation (off-toggle / on-toggle / no-toggle when
        // AI unavailable) is queried via `trailingControl(_:)` instead.
        #expect(ReaderMoreMenuRow.autoTurnPages.isToggle)
        #expect(!ReaderMoreMenuRow.readAloud.isToggle)
        #expect(!ReaderMoreMenuRow.bilingual.isToggle)
        #expect(!ReaderMoreMenuRow.reTranslateChapter.isToggle)
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
        // The notification is the seam; `ReaderContainerView` maps it
        // via `ReaderMoreMenuEffect` to the dedicated Book Details
        // sheet (feature #61 WI-3). The row → effect routing contract
        // is pinned by `BookDetailsRouteTests`.
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
