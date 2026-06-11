// Purpose: Feature #56 WI-8 — pins the More-menu popover's bilingual row
// (3-way `TrailingControl` presentation) and the conditional
// `reTranslateChapter` row.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/feature-60-followups.md`
//     §2.3 (More-menu row states: Off / On / Unavailable)
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/needs-design-issues.md`
//     §#864 (per-chapter re-translate row; conditional on `bilingualOn`)
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderMorePopover.swift,
//   ReaderNotifications.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-8 — bilingual row + re-translate row contract")
struct ReaderMoreMenuBilingualTests {

    // MARK: - Cardinality + order

    @Test("Bilingual row is shipped (third row, after Auto-turn, before Book details)")
    func bilingualRowShipped() {
        // Design §2.3 places the row in the 3rd slot — between the
        // reading-controls cluster (Read aloud / Auto-turn) and the
        // book-action cluster (Book details / Share / Export).
        #expect(ReaderMoreMenuRow.allCases.contains(.bilingual))
        let cases = ReaderMoreMenuRow.allCases
        let bilingualIdx = cases.firstIndex(of: .bilingual)
        let autoTurnIdx = cases.firstIndex(of: .autoTurnPages)
        let bookDetailsIdx = cases.firstIndex(of: .bookDetails)
        #expect(bilingualIdx != nil && autoTurnIdx != nil && bookDetailsIdx != nil)
        if let bi = bilingualIdx, let at = autoTurnIdx, let bd = bookDetailsIdx {
            #expect(at < bi, "Bilingual must come after Auto-turn")
            #expect(bi < bd, "Bilingual must come before Book details")
        }
    }

    @Test("Re-translate chapter row exists in the enum (conditional in visibleRows)")
    func reTranslateRowExists() {
        // The case must exist so the conditional `visibleRows` can
        // include it when bilingual is on. It is NEVER present when
        // bilingual is off — that's the visibility contract.
        #expect(ReaderMoreMenuRow.allCases.contains(.reTranslateChapter))
    }

    @Test("Static divider anchor is the bilingual row")
    func dividerStaticAnchor() {
        // The static `dividerAfter` is the canonical cluster boundary
        // when the conditional re-translate row is hidden. When the
        // re-translate row is visible, the boundary slides one row
        // down — see `dividerAnchor(in:)` below.
        #expect(ReaderMoreMenuRow.dividerAfter == .bilingual)
    }

    @Test("dividerAnchor returns .bilingual when re-translate is hidden")
    func dividerAnchorWhenReTranslateHidden() {
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .epub),
            bilingualOn: false
        )
        #expect(ReaderMoreMenuRow.dividerAnchor(in: rows) == .bilingual)
    }

    @Test("dividerAnchor slides to .reTranslateChapter when shown")
    func dividerAnchorWhenReTranslateShown() {
        // Design §2.3 + #864: the cluster boundary follows the LAST
        // bilingual-cluster row in the visible set. With re-translate
        // shown, that's the re-translate row itself.
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .epub),
            bilingualOn: true
        )
        #expect(ReaderMoreMenuRow.dividerAnchor(in: rows) == .reTranslateChapter)
    }

    // MARK: - Visibility — bilingualOn parameter

    @Test("visibleRows omits reTranslateChapter when bilingualOn is false")
    func reTranslateHiddenWhenBilingualOff() {
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .epub),
            bilingualOn: false
        )
        #expect(!rows.contains(.reTranslateChapter),
                "re-translate row must be absent when bilingual is off")
    }

    @Test("visibleRows includes reTranslateChapter when bilingualOn is true")
    func reTranslateShownWhenBilingualOn() {
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .epub),
            bilingualOn: true
        )
        #expect(rows.contains(.reTranslateChapter),
                "re-translate row must be present when bilingual is on")
    }

    @Test("visibleRows places reTranslateChapter directly after Bilingual when on")
    func reTranslatePlacement() {
        // Design §2.3 + #864: the re-translate row belongs in the
        // bilingual neighborhood — it ships right after the bilingual
        // row so the cluster reads as the "translation actions" group.
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .epub),
            bilingualOn: true
        )
        guard let biIdx = rows.firstIndex(of: .bilingual),
              let rtIdx = rows.firstIndex(of: .reTranslateChapter)
        else {
            Issue.record("expected both rows in visible set")
            return
        }
        // Feature #99: the Translation settings row sits between the
        // toggle and re-translate rows inside the cluster.
        #expect(rtIdx == biIdx + 2)
        #expect(rows.firstIndex(of: .translationSettings) == biIdx + 1)
    }

    @Test("visibleRows preserves declared order with bilingualOn=false")
    func visibleRowsOrder() {
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .epub),
            bilingualOn: false
        )
        // Bilingual always renders (Off / Unavailable both visible); only
        // re-translate is gated.
        #expect(rows == [.readAloud, .autoTurnPages, .bilingual,
                         .bookDetails, .shareBook, .exportAnnotations])
    }

    @Test("Bilingual row survives the TTS cap-gate (PDF: no TTS, bilingual stays)")
    func bilingualSurvivesTTSGate() {
        let rows = ReaderMoreMenuRow.visibleRows(
            for: FormatCapabilities.capabilities(for: .pdf),
            bilingualOn: false
        )
        #expect(rows.contains(.bilingual),
                "bilingual is not gated by .tts")
        #expect(!rows.contains(.readAloud),
                "PDF still drops Read aloud as before")
    }

    // MARK: - Notification routing

    @Test("Bilingual row routes to .readerMoreBilingual")
    func bilingualRoutes() {
        #expect(ReaderMoreMenuRow.bilingual.notification == .readerMoreBilingual)
    }

    @Test("Re-translate row routes to .readerMoreReTranslateChapter")
    func reTranslateRoutes() {
        #expect(ReaderMoreMenuRow.reTranslateChapter.notification == .readerMoreReTranslateChapter)
    }

    @Test("Bilingual/re-translate round-trip via init?(notification:)")
    func newRowsRoundTrip() {
        #expect(ReaderMoreMenuRow(notification: .readerMoreBilingual) == .bilingual)
        #expect(ReaderMoreMenuRow(notification: .readerMoreReTranslateChapter) == .reTranslateChapter)
    }

    @Test("All More-menu notifications stay namespaced under vreader.")
    func notificationsStillNamespaced() {
        for row in ReaderMoreMenuRow.allCases {
            #expect(row.notification.rawValue.hasPrefix("vreader."))
        }
    }

    @Test("Every row still maps to a distinct notification")
    func everyRowDistinct() {
        let names = ReaderMoreMenuRow.allCases.map(\.notification)
        #expect(Set(names).count == ReaderMoreMenuRow.allCases.count)
    }

    // MARK: - TrailingControl — 3-way bilingual presentation

    @Test("Auto-turn produces a toggle reflecting autoTurnOn")
    func autoTurnTrailingToggle() {
        let off = ReaderMoreMenuRow.autoTurnPages.trailingControl(
            bilingualState: .off, autoTurnOn: false
        )
        let on = ReaderMoreMenuRow.autoTurnPages.trailingControl(
            bilingualState: .off, autoTurnOn: true
        )
        #expect(off == .toggle(false))
        #expect(on == .toggle(true))
    }

    @Test("Bilingual.off renders an OFF toggle")
    func bilingualOffTrailingToggle() {
        let control = ReaderMoreMenuRow.bilingual.trailingControl(
            bilingualState: .off, autoTurnOn: false
        )
        #expect(control == .toggle(false))
    }

    @Test("Bilingual.on renders an ON toggle")
    func bilingualOnTrailingToggle() {
        let control = ReaderMoreMenuRow.bilingual.trailingControl(
            bilingualState: .on(targetLanguage: "Chinese"), autoTurnOn: false
        )
        #expect(control == .toggle(true))
    }

    @Test("Bilingual.unavailable renders a chevron (no toggle — tap-to-configure)")
    func bilingualUnavailableTrailing() {
        // Per design §2.3: "(no toggle)" + "Configure AI provider first
        // + chevron". `trailingControl` returns `.chevron` for the
        // unavailable state — the iOS-standard "Settings → Cellular
        // when no SIM" pattern. The toggle slot is replaced by the
        // tap-row chevron so the row reads as "tap to configure".
        let control = ReaderMoreMenuRow.bilingual.trailingControl(
            bilingualState: .unavailable, autoTurnOn: false
        )
        #expect(control == .chevron)
    }

    @Test("Re-translate row renders a chevron (tap row)")
    func reTranslateTrailingChevron() {
        let control = ReaderMoreMenuRow.reTranslateChapter.trailingControl(
            bilingualState: .on(targetLanguage: "Chinese"), autoTurnOn: false
        )
        #expect(control == .chevron)
    }

    @Test("Other tap rows render a chevron")
    func tapRowsTrailingChevron() {
        for row in [ReaderMoreMenuRow.readAloud, .bookDetails, .shareBook, .exportAnnotations] {
            let control = row.trailingControl(bilingualState: .off, autoTurnOn: false)
            #expect(control == .chevron, "row \(row) should render a chevron trailing control")
        }
    }

    // MARK: - Sub-detail — bilingual states

    @Test("Bilingual.off sub-detail is the inline prompt")
    func bilingualOffSub() {
        let sub = ReaderMoreMenuRow.bilingual.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .off
        )
        #expect(sub == "Translate inline")
    }

    @Test("Bilingual.on sub-detail shows the EN ↔ <target> bidi pair")
    func bilingualOnSub() {
        let sub = ReaderMoreMenuRow.bilingual.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .on(targetLanguage: "Chinese")
        )
        // Design §2.3: "English ↔ Chinese (or current target)"
        #expect(sub == "English \u{2194} Chinese")
    }

    @Test("Bilingual.unavailable sub-detail prompts to configure AI")
    func bilingualUnavailableSub() {
        let sub = ReaderMoreMenuRow.bilingual.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .unavailable
        )
        #expect(sub == "Configure AI provider first")
    }

    @Test("Re-translate sub-detail mentions the source")
    func reTranslateSub() {
        // The static idle copy from #864 — the running/complete/error
        // states are owned by a downstream view model (WI-15), not the
        // pure row contract. The row's default sub-detail describes the
        // idle state.
        let sub = ReaderMoreMenuRow.reTranslateChapter.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .on(targetLanguage: "Chinese")
        )
        #expect(sub == "Re-translate this chapter")
    }

    // MARK: - Active (accent-tinted) state

    @Test("Bilingual row is active only when state is .on(_)")
    func bilingualActive() {
        // The design accent-tints the icon chip of an active row. The
        // bilingual row is active in `.on`, inactive in `.off` and
        // `.unavailable`.
        #expect(ReaderMoreMenuRow.bilingual.isActive(
            ttsPlaying: false, autoTurnOn: false,
            bilingualState: .on(targetLanguage: "Chinese")
        ))
        #expect(!ReaderMoreMenuRow.bilingual.isActive(
            ttsPlaying: false, autoTurnOn: false,
            bilingualState: .off
        ))
        #expect(!ReaderMoreMenuRow.bilingual.isActive(
            ttsPlaying: false, autoTurnOn: false,
            bilingualState: .unavailable
        ))
    }

    @Test("Re-translate row is never accent-tinted (tap row)")
    func reTranslateNeverActive() {
        for state: BilingualRowState in [.off, .on(targetLanguage: "Chinese"), .unavailable] {
            #expect(!ReaderMoreMenuRow.reTranslateChapter.isActive(
                ttsPlaying: false, autoTurnOn: false,
                bilingualState: state
            ), "re-translate row should never be active for state \(state)")
        }
    }

    // MARK: - Accessibility identifiers

    @Test("Bilingual row exposes a stable accessibility identifier")
    func bilingualAxId() {
        #expect(ReaderMoreMenuRow.bilingual.accessibilityIdentifier == "readerMoreBilingual")
    }

    @Test("Re-translate row exposes a stable accessibility identifier")
    func reTranslateAxId() {
        #expect(ReaderMoreMenuRow.reTranslateChapter.accessibilityIdentifier == "readerMoreReTranslateChapter")
    }

    @Test("All accessibility identifiers are still distinct")
    func axIdsDistinct() {
        let ids = ReaderMoreMenuRow.allCases.map(\.accessibilityIdentifier)
        #expect(Set(ids).count == ReaderMoreMenuRow.allCases.count)
    }

    // MARK: - Label + icon contract

    @Test("Bilingual row label matches the design")
    func bilingualLabel() {
        #expect(ReaderMoreMenuRow.bilingual.label == "Bilingual mode")
    }

    @Test("Re-translate row label matches the design")
    func reTranslateLabel() {
        #expect(ReaderMoreMenuRow.reTranslateChapter.label == "Re-translate chapter")
    }

    @Test("Bilingual + re-translate use the translate glyph")
    func translationGlyph() {
        // Design §2.3 / #864 both call for the Translate icon.
        #expect(ReaderMoreMenuRow.bilingual.systemImage == "character.book.closed")
        #expect(ReaderMoreMenuRow.reTranslateChapter.systemImage == "arrow.triangle.2.circlepath")
    }
}

// MARK: - Popover wiring guards

@Suite("Feature #56 WI-8 — ReaderMorePopover bilingual wiring")
struct ReaderMorePopoverBilingualTests {

    @MainActor
    private func makePopover(
        capabilities: FormatCapabilities?,
        bilingualState: BilingualRowState
    ) -> ReaderMorePopover {
        ReaderMorePopover(
            theme: .paper,
            ttsPlaying: false,
            autoTurnOn: false,
            autoTurnInterval: 5,
            formatCapabilities: capabilities,
            bilingualState: bilingualState,
            topInset: 0,
            onClose: {}
        )
    }

    @MainActor
    @Test func resolvedRows_dropReTranslate_whenBilingualOff() {
        let popover = makePopover(
            capabilities: FormatCapabilities.capabilities(for: .epub),
            bilingualState: .off
        )
        #expect(!popover.resolvedRows.contains(.reTranslateChapter))
    }

    @MainActor
    @Test func resolvedRows_includeReTranslate_whenBilingualOn() {
        let popover = makePopover(
            capabilities: FormatCapabilities.capabilities(for: .epub),
            bilingualState: .on(targetLanguage: "Chinese")
        )
        #expect(popover.resolvedRows.contains(.reTranslateChapter))
    }

    @MainActor
    @Test func resolvedRows_dropReTranslate_whenBilingualUnavailable() {
        // No bilingual state means no chapter to re-translate.
        let popover = makePopover(
            capabilities: FormatCapabilities.capabilities(for: .epub),
            bilingualState: .unavailable
        )
        #expect(!popover.resolvedRows.contains(.reTranslateChapter))
    }

    @MainActor
    @Test func resolvedRows_keepBilingual_acrossAllStates() {
        for state: BilingualRowState in [.off, .on(targetLanguage: "Chinese"), .unavailable] {
            let popover = makePopover(
                capabilities: FormatCapabilities.capabilities(for: .epub),
                bilingualState: state
            )
            #expect(popover.resolvedRows.contains(.bilingual),
                    "bilingual row missing for state \(state)")
        }
    }

    // MARK: - Defensive: dividerAnchor fallback

    @Test func dividerAnchor_fallsBack_whenBothBilingualRowsHidden() {
        // Future capability filter could hide both bilingual-cluster
        // rows. The anchor must fall back to an actually-rendered
        // row so the divider doesn't silently vanish.
        let rows: [ReaderMoreMenuRow] = [.readAloud, .autoTurnPages,
                                          .bookDetails, .shareBook, .exportAnnotations]
        let anchor = ReaderMoreMenuRow.dividerAnchor(in: rows)
        #expect(anchor != nil)
        if let a = anchor {
            #expect(rows.contains(a),
                    "fallback anchor must be present in the visible rows")
        }
    }

    @Test func dividerAnchor_isNil_whenRowsEmpty() {
        // Empty input → nil. The popover renders nothing in this case.
        #expect(ReaderMoreMenuRow.dividerAnchor(in: []) == nil)
    }

    // MARK: - Defensive: empty / whitespace target-language

    @Test func bilingualOnSub_safeOn_whenTargetIsEmpty() {
        let sub = ReaderMoreMenuRow.bilingual.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .on(targetLanguage: "")
        )
        // Falls back to a generic "On" label rather than "English ↔ ".
        #expect(sub == "On")
    }

    @Test func bilingualOnSub_safeOn_whenTargetIsWhitespace() {
        let sub = ReaderMoreMenuRow.bilingual.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .on(targetLanguage: "   \t  ")
        )
        #expect(sub == "On")
    }

    @Test func bilingualOnSub_trimsAndRendersCJKTarget() {
        // A long CJK target language ("简体中文") is functional —
        // SwiftUI truncates if necessary. Trimming whitespace doesn't
        // change CJK content; the sub-detail renders the trimmed
        // language verbatim.
        let sub = ReaderMoreMenuRow.bilingual.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30,
            bilingualState: .on(targetLanguage: "  简体中文  ")
        )
        #expect(sub == "English \u{2194} 简体中文")
    }

    // MARK: - Observer wiring (regression for Gate 4 High finding)

    @Test func actionObserverDispatches_bilingualNotification() async {
        // Posting `.readerMoreBilingual` must surface in the host's
        // `(ReaderMoreMenuRow) -> Void` funnel as `.bilingual`. The
        // round-trip goes Notification → init?(notification:) → row.
        // The observer modifier lives in `ReaderMorePopoverParts`;
        // here we verify the funnel logic via the inverse initializer
        // (the same path `ReaderMoreMenuActionObservers.dispatch`
        // uses). A future regression that drops the inverse case
        // would fail at runtime — this test pins it at compile time.
        #expect(ReaderMoreMenuRow(notification: .readerMoreBilingual) == .bilingual)
        #expect(ReaderMoreMenuRow(notification: .readerMoreReTranslateChapter) == .reTranslateChapter)
    }
}
