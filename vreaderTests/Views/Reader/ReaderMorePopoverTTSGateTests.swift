// Purpose: Regression-guard tests for the per-format `.tts` capability
// gate on the reader More-menu popover (`ReaderMorePopover`) — the
// `Read aloud` row is shown only when the active format advertises
// `.tts`. The gate originated with bug #176 / GH #602 (which removed
// `.tts` from `FormatCapabilities.capabilities(for: .azw3)` while
// AZW3/MOBI TTS was unimplemented); feature #60 WI-6c's
// `ReaderMorePopover` then had to honor that gate rather than render
// every row unconditionally.
//
// Feature #57 wired the AZW3/MOBI TTS path and re-added `.tts` to the
// AZW3 capability set, so AZW3/MOBI now SHOW the `Read aloud` row. PDF
// remains the format that genuinely lacks `.tts`. These tests pin the
// gate as a per-capability contract: TTS-capable formats show the row,
// non-TTS formats (PDF, empty caps) hide it.
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
        // PDF never had `.tts` (PDFKit has no TTS path) — it must drop
        // the Read aloud row. (AZW3/MOBI used to be here too, under the
        // bug #176 cap-gate; feature #57 wired AZW3 TTS and re-added
        // `.tts`, so AZW3 now moves to the positive test below.)
        let caps = FormatCapabilities.capabilities(for: .pdf)
        let rows = ReaderMoreMenuRow.visibleRows(for: caps)
        #expect(
            !rows.contains(.readAloud),
            "Expected pdf to hide the Read aloud row"
        )
    }

    @Test func readAloud_present_whenFormatHasTTS() {
        // TXT, MD, EPUB, and — since feature #57 — AZW3/MOBI advertise
        // `.tts`, so the row stays.
        for format in [BookFormat.txt, .md, .epub, .azw3] {
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
        // not supply `formatCapabilities` see every non-conditional
        // row — same default as the bug #156 / #158 gates (`nil` →
        // show). Feature #56 WI-8: `.reTranslateChapter` is still
        // gated on `bilingualOn` (default `false`) so it stays out
        // of the default visible set.
        let rows = ReaderMoreMenuRow.visibleRows(for: nil)
        let expected = ReaderMoreMenuRow.allCases.filter { $0 != .reTranslateChapter && $0 != .translationSettings }
        #expect(rows == expected)
    }

    @Test func nonReadAloudRows_unaffected_byTTSGate() {
        // The non-TTS rows (Auto-turn / Bilingual / Book details /
        // Share / Export) must survive the gate regardless of `.tts`
        // — only the Read aloud row is capability-gated.
        // `.reTranslateChapter` is gated on bilingualOn, not TTS, so
        // it's excluded from the loop.
        let caps = FormatCapabilities.capabilities(for: .pdf) // no `.tts`
        let rows = ReaderMoreMenuRow.visibleRows(for: caps)
        for row in ReaderMoreMenuRow.allCases
        where row != .readAloud && row != .reTranslateChapter && row != .translationSettings {
            #expect(
                rows.contains(row),
                "Expected \(row) to survive the TTS gate"
            )
        }
    }

    @Test func visibleRows_preserveDeclaredOrder() {
        // Filtering must not reorder rows — `ReaderMorePopover` draws its
        // divider after the runtime cluster anchor by index, so order
        // is a contract.
        //
        // Feature #56 WI-8: the default `bilingualOn=false` hides
        // `.reTranslateChapter`, so the visible set is `allCases`
        // minus that row plus whatever the TTS gate filters out.
        let withTTS = ReaderMoreMenuRow.visibleRows(for: [.tts])
        let expectedWithTTS = ReaderMoreMenuRow.allCases.filter {
            $0 != .reTranslateChapter && $0 != .translationSettings
        }
        #expect(withTTS == expectedWithTTS)

        let withoutTTS = ReaderMoreMenuRow.visibleRows(for: [])
        let expected = ReaderMoreMenuRow.allCases.filter {
            $0 != .readAloud && $0 != .reTranslateChapter
                && $0 != .translationSettings
        }
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
        // `visibleRows(for:)` itself stays correct. PDF is the format
        // that genuinely lacks `.tts`.
        let pdf = FormatCapabilities.capabilities(for: .pdf)
        #expect(!makePopover(capabilities: pdf).resolvedRows.contains(.readAloud))
    }

    @MainActor
    @Test func popover_resolvedRows_keepReadAloud_forFormatWithTTS() {
        let epub = FormatCapabilities.capabilities(for: .epub)
        #expect(makePopover(capabilities: epub).resolvedRows.contains(.readAloud))
    }

    @MainActor
    @Test func popover_resolvedRows_keepReadAloud_forAZW3() {
        // Feature #57: AZW3/MOBI regained `.tts`, so the popover must
        // surface the Read aloud row for it — the user-visible half of
        // the WI-3 cap-gate reversal.
        let azw3 = FormatCapabilities.capabilities(for: .azw3)
        #expect(makePopover(capabilities: azw3).resolvedRows.contains(.readAloud))
    }

    @MainActor
    @Test func popover_resolvedRows_allRows_whenCapabilitiesNil() {
        // The popover's `nil` default renders every non-conditional
        // row. Feature #56 WI-8: `.reTranslateChapter` is gated on
        // bilingual state (`.off` by default in `makePopover`) so it
        // stays out of the visible set.
        let expected = ReaderMoreMenuRow.allCases.filter { $0 != .reTranslateChapter && $0 != .translationSettings }
        #expect(makePopover(capabilities: nil).resolvedRows == expected)
    }
}
