// Purpose: Feature #60 WI-6c — pins the More-menu popover's
// state-driven sub-detail text. `vreader-more.jsx` updates each
// designed row's secondary line as state changes ("Off" → "Every
// 30s", "Start text-to-speech" → "Playing · System voice"). The
// pure mapping is pinned here so a render regression is caught
// without a SwiftUI host.
//
// Design source:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// (the `Row sub={...}` expressions) +
// `design-notes/reader-search-and-more-menu.md` §2.
//
// @coordinates-with: ReaderMorePopover.swift, ReaderMoreMenuRow.swift

import Testing
@testable import vreader

@Suite("Feature #60 WI-6c — ReaderMorePopover sub-detail text")
struct ReaderMorePopoverStateTests {

    // MARK: - Read aloud

    @Test("Read aloud sub-detail is the idle prompt when TTS is not playing")
    func readAloudSubIdle() {
        let sub = ReaderMoreMenuRow.readAloud.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30
        )
        #expect(sub == "Start text-to-speech")
    }

    @Test("Read aloud sub-detail reflects the playing state")
    func readAloudSubPlaying() {
        let sub = ReaderMoreMenuRow.readAloud.subDetail(
            ttsPlaying: true, autoTurnOn: false, autoTurnInterval: 30
        )
        #expect(sub == "Playing \u{00b7} System voice")
    }

    // MARK: - Auto-turn pages

    @Test("Auto-turn sub-detail is Off when disabled")
    func autoTurnSubOff() {
        let sub = ReaderMoreMenuRow.autoTurnPages.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30
        )
        #expect(sub == "Off")
    }

    @Test("Auto-turn sub-detail shows the interval when enabled")
    func autoTurnSubOn() {
        let sub = ReaderMoreMenuRow.autoTurnPages.subDetail(
            ttsPlaying: false, autoTurnOn: true, autoTurnInterval: 30
        )
        #expect(sub == "Every 30s")
    }

    @Test("Auto-turn interval is rounded to a whole-second label")
    func autoTurnSubRoundsInterval() {
        // `ReaderSettingsStore.autoPageTurnInterval` is a TimeInterval
        // (Double, clamped 1...60). The design's label is "Every Ns" —
        // an integer. A 12.5s interval must not render "Every 12.5s".
        let sub = ReaderMoreMenuRow.autoTurnPages.subDetail(
            ttsPlaying: false, autoTurnOn: true, autoTurnInterval: 12.5
        )
        #expect(sub == "Every 13s")
    }

    @Test("Auto-turn interval clamps to the design's 1...60 range")
    func autoTurnSubClampsInterval() {
        // Defensive: a drifted/out-of-range stored interval still
        // renders a sane label rather than "Every 0s" / "Every 999s".
        let low = ReaderMoreMenuRow.autoTurnPages.subDetail(
            ttsPlaying: false, autoTurnOn: true, autoTurnInterval: 0
        )
        let high = ReaderMoreMenuRow.autoTurnPages.subDetail(
            ttsPlaying: false, autoTurnOn: true, autoTurnInterval: 999
        )
        #expect(low == "Every 1s")
        #expect(high == "Every 60s")
    }

    // MARK: - Book actions (static / nil sub-detail)

    @Test("Book details has no sub-detail")
    func bookDetailsNoSub() {
        let sub = ReaderMoreMenuRow.bookDetails.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30
        )
        #expect(sub == nil)
    }

    @Test("Share book has no sub-detail")
    func shareBookNoSub() {
        let sub = ReaderMoreMenuRow.shareBook.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30
        )
        #expect(sub == nil)
    }

    @Test("Export annotations sub-detail lists the formats")
    func exportSub() {
        let sub = ReaderMoreMenuRow.exportAnnotations.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 30
        )
        #expect(sub == "Markdown \u{00b7} JSON \u{00b7} VReader JSON")
    }

    // MARK: - Active (accent-tinted) state

    @Test("Read aloud row is active only while TTS is playing")
    func readAloudActive() {
        // The design accent-tints the icon background of an active
        // row. Read aloud is active iff TTS is playing.
        #expect(ReaderMoreMenuRow.readAloud.isActive(
            ttsPlaying: true, autoTurnOn: false
        ))
        #expect(!ReaderMoreMenuRow.readAloud.isActive(
            ttsPlaying: false, autoTurnOn: false
        ))
    }

    @Test("Auto-turn row is active only while the toggle is on")
    func autoTurnActive() {
        #expect(ReaderMoreMenuRow.autoTurnPages.isActive(
            ttsPlaying: false, autoTurnOn: true
        ))
        #expect(!ReaderMoreMenuRow.autoTurnPages.isActive(
            ttsPlaying: false, autoTurnOn: false
        ))
    }

    @Test("Static rows are never active")
    func staticRowsNeverActive() {
        for row in [ReaderMoreMenuRow.bookDetails, .shareBook, .exportAnnotations] {
            #expect(!row.isActive(ttsPlaying: true, autoTurnOn: true), "row \(row) should not be active")
        }
    }
}
