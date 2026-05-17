// Purpose: Regression-guard tests for bug #176 / GH #602 (REOPENED) —
// the `Read aloud` row is hidden in the reader More-menu popover
// (`ReaderMorePopover`) when the active format does not advertise
// `.tts`. The original bug #176 fix removed `.tts` from
// `FormatCapabilities.capabilities(for: .azw3)`, but feature #60
// WI-6c's `ReaderMorePopover` re-surfaced a `Read aloud` row for ALL
// formats unconditionally (`ForEach(ReaderMoreMenuRow.allCases)`),
// bypassing that capability gate. On AZW3/MOBI the row reappeared and
// tapping it was a silent no-op. This gate is the user-visible half of
// the fix; the capability declaration in `FormatCapabilities.swift` is
// the other half.
//
// The gate lives in `ReaderMoreMenuRow.visibleRows(for:)` so the
// design's row contract stays testable without a SwiftUI render path —
// the same pattern `ReaderSettingsPanel.shouldShowReadingModeSection`
// uses for the bug #158 gate.
//
// @coordinates-with: vreader/Views/Reader/ReaderMoreMenuRow.swift,
// vreader/Views/Reader/ReaderMorePopover.swift,
// vreader/Models/FormatCapabilities.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderMorePopover Read-aloud TTS gate (bug #176 / GH #602)")
struct ReaderMorePopoverTTSGateTests {

    @Test func readAloud_absent_whenFormatLacksTTS() {
        // AZW3 / MOBI route through Foliate-js; `FormatCapabilities`
        // excludes `.tts` for `.azw3` (bug #176). PDF never had `.tts`.
        // All three must drop the Read aloud row.
        for format in [BookFormat.azw3, .pdf] {
            let caps = FormatCapabilities.capabilities(for: format)
            let rows = ReaderMoreMenuRow.visibleRows(for: caps)
            #expect(
                !rows.contains(.readAloud),
                "Expected \(format) to hide the Read aloud row"
            )
        }
    }

    @Test func readAloud_present_whenFormatHasTTS() {
        // TXT, MD, and EPUB advertise `.tts` — the row stays.
        for format in [BookFormat.txt, .md, .epub] {
            let caps = FormatCapabilities.capabilities(for: format)
            let rows = ReaderMoreMenuRow.visibleRows(for: caps)
            #expect(
                rows.contains(.readAloud),
                "Expected \(format) to show the Read aloud row"
            )
        }
    }

    @Test func readAloud_absent_whenEmptyCapabilities() {
        // An empty capability set excludes `.tts`, so the row is hidden —
        // defending against a future format shipping with all caps off.
        let rows = ReaderMoreMenuRow.visibleRows(for: [])
        #expect(!rows.contains(.readAloud))
    }

    @Test func readAloud_present_whenExplicitTTSSupplied() {
        // Option-set membership rule, independent of the per-format
        // factory.
        let rows = ReaderMoreMenuRow.visibleRows(for: [.tts])
        #expect(rows.contains(.readAloud))
    }

    @Test func allRows_visible_whenCapabilitiesNotSupplied() {
        // Backward compat: previews / older tests / call sites that do
        // not supply `formatCapabilities` see every row — same default
        // as the bug #156 / #158 gates (`nil` → show).
        let rows = ReaderMoreMenuRow.visibleRows(for: nil)
        #expect(rows == ReaderMoreMenuRow.allCases)
    }

    @Test func nonReadAloudRows_unaffected_byTTSGate() {
        // The four non-TTS rows (Auto-turn / Book details / Share /
        // Export) must survive the gate regardless of `.tts` — only the
        // Read aloud row is capability-gated.
        let caps = FormatCapabilities.capabilities(for: .azw3) // no `.tts`
        let rows = ReaderMoreMenuRow.visibleRows(for: caps)
        for row in ReaderMoreMenuRow.allCases where row != .readAloud {
            #expect(
                rows.contains(row),
                "Expected \(row) to survive the TTS gate"
            )
        }
    }

    @Test func visibleRows_preserveDeclaredOrder() {
        // Filtering must not reorder rows — `ReaderMorePopover` draws its
        // divider after `.autoTurnPages` by index, so order is a
        // contract.
        let withTTS = ReaderMoreMenuRow.visibleRows(for: [.tts])
        #expect(withTTS == ReaderMoreMenuRow.allCases)

        let withoutTTS = ReaderMoreMenuRow.visibleRows(for: [])
        let expected = ReaderMoreMenuRow.allCases.filter { $0 != .readAloud }
        #expect(withoutTTS == expected)
    }

    @Test func dividerAfterRow_alwaysPresent_underTTSGate() {
        // `ReaderMorePopover` inserts the hairline divider after
        // `ReaderMoreMenuRow.dividerAfter`. That row must never be gated
        // out, or the divider would silently vanish.
        let withoutTTS = ReaderMoreMenuRow.visibleRows(for: [])
        #expect(withoutTTS.contains(ReaderMoreMenuRow.dividerAfter))
    }

    // MARK: - Popover wiring

    /// Builds a `ReaderMorePopover` with the given capability set —
    /// every other field is an inert placeholder.
    @MainActor
    private func makePopover(capabilities: FormatCapabilities?) -> ReaderMorePopover {
        ReaderMorePopover(
            theme: .paper,
            ttsPlaying: false,
            autoTurnOn: false,
            autoTurnInterval: 5,
            formatCapabilities: capabilities,
            topInset: 0,
            onClose: {}
        )
    }

    @MainActor
    @Test func popover_resolvedRows_dropReadAloud_forFormatWithoutTTS() {
        // Wiring guard: `ReaderMorePopover` must consult
        // `formatCapabilities` — a revert to `allCases`, or passing the
        // wrong capability set, regresses this even while
        // `visibleRows(for:)` itself stays correct.
        let azw3 = FormatCapabilities.capabilities(for: .azw3)
        #expect(!makePopover(capabilities: azw3).resolvedRows.contains(.readAloud))
    }

    @MainActor
    @Test func popover_resolvedRows_keepReadAloud_forFormatWithTTS() {
        let epub = FormatCapabilities.capabilities(for: .epub)
        #expect(makePopover(capabilities: epub).resolvedRows.contains(.readAloud))
    }

    @MainActor
    @Test func popover_resolvedRows_allRows_whenCapabilitiesNil() {
        // The popover's `nil` default still renders every row.
        #expect(makePopover(capabilities: nil).resolvedRows == ReaderMoreMenuRow.allCases)
    }
}
