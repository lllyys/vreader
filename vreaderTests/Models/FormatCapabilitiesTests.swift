// Purpose: Tests for FormatCapabilities — per-format capability sets,
// context-aware factory, and edge cases (complex EPUB, PDF restrictions).

import Testing
import Foundation
@testable import vreader

@Suite("FormatCapabilities")
struct FormatCapabilitiesTests {

    // MARK: - Per-Format Capabilities

    @Test func txt_supportsTextSelection_highlights_tts_pagination() {
        let caps = FormatCapabilities.capabilities(for: .txt)
        #expect(caps.contains(.textSelection))
        #expect(caps.contains(.highlights))
        #expect(caps.contains(.tts))
        #expect(caps.contains(.nativePagination))
        #expect(caps.contains(.annotations))
        // Bug #158 / GH #468: TXT lost `.unifiedReflow` after the verify cron
        // discovered that `UnifiedScrollView` for TXT renders only the first
        // ~12 lines, has no bottom chrome (no progress, no pager, no TOC),
        // and blanks out completely when toggled from Native at a non-zero
        // scroll position. Capability-gate matches #120/#156/#157 cheap-path
        // pattern: hide the broken mode rather than ship a partial UX.
        #expect(!caps.contains(.unifiedReflow))
        // Bug #157 / GH #461: TXT host does NOT wire AutoPageTurner —
        // `TXTReaderContainerView.updatePaginationIfNeeded()` is defined but
        // never called, and there is no paged renderer that observes
        // `pageNavigator.currentPage`. The toggle was previously incorrectly
        // shown via the `reflowableBase` preset (regression from #156's gate).
        #expect(!caps.contains(.autoPageTurn))
        // TXT does NOT have TOC
        #expect(!caps.contains(.toc))
    }

    @Test func txt_doesNotSupportUnifiedReflow() {
        // Bug #158 / GH #468: regression-guard. Removing `.unifiedReflow` from
        // `reflowableBase` is the cheap-path mitigation; this test pins the
        // post-fix capability set. If TXT later gains a working unified
        // renderer (full content, bottom chrome, TOC integration, no
        // toggle-blank), flip this expectation AND verify the
        // `ReaderSettingsPanel.readingModeSection` gate together.
        let caps = FormatCapabilities.capabilities(for: .txt)
        #expect(!caps.contains(.unifiedReflow))
    }

    @Test func only_md_epub_azw3_supportUnifiedReflow_simpleEPUB() {
        // Bug #158 / GH #468: regression-guard for the post-fix capability
        // gate. After #158 narrowed the `.unifiedReflow` set from
        // {TXT, MD, simple-EPUB, AZW3} to {MD, simple-EPUB, AZW3}, this
        // test pins the per-format expectation. Complex EPUB (covered by
        // `capabilities_contextAware_epubComplex_noUnifiedReflow`) and PDF
        // remain excluded — same as before.
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            switch format {
            case .md, .epub, .azw3:
                #expect(caps.contains(.unifiedReflow), "Expected \(format) to support unifiedReflow")
            case .txt, .pdf:
                #expect(!caps.contains(.unifiedReflow), "Expected \(format) to NOT support unifiedReflow")
            }
        }
    }

    @Test func md_supportsTextSelection_highlights_tts_pagination() {
        let caps = FormatCapabilities.capabilities(for: .md)
        #expect(caps.contains(.textSelection))
        #expect(caps.contains(.highlights))
        #expect(caps.contains(.tts))
        #expect(caps.contains(.nativePagination))
        #expect(caps.contains(.unifiedReflow))
        #expect(caps.contains(.annotations))
        // Bug #156 / GH #456: MD host wires AutoPageTurner end-to-end.
        // `MDReaderContainerView` calls `updatePaginationIfNeeded()` from
        // `.task` + `.onChange` of layout/fontSize and renders pages via
        // `pagedReaderContent` (line 278) which observes
        // `pageNavigator.currentPage`. Bug #157 confirmed MD is the only
        // format with a fully wired paged renderer + AutoPageTurner.
        #expect(caps.contains(.autoPageTurn))
        // MD has TOC (headings)
        #expect(caps.contains(.toc))
    }

    @Test func epub_supportsAll() {
        let caps = FormatCapabilities.capabilities(for: .epub)
        #expect(caps.contains(.textSelection))
        #expect(caps.contains(.highlights))
        #expect(caps.contains(.bookmarks))
        #expect(caps.contains(.search))
        #expect(caps.contains(.tts))
        #expect(caps.contains(.nativePagination))
        #expect(caps.contains(.unifiedReflow))
        #expect(caps.contains(.toc))
        #expect(caps.contains(.annotations))
        // Bug #156 / GH #456: EPUB host does NOT yet wire AutoPageTurner.
        #expect(!caps.contains(.autoPageTurn))
    }

    @Test func pdf_supportsSelection_highlights_pagination_notTTS_notUnifiedReflow() {
        let caps = FormatCapabilities.capabilities(for: .pdf)
        #expect(caps.contains(.textSelection))
        #expect(caps.contains(.highlights))
        #expect(caps.contains(.nativePagination))
        #expect(caps.contains(.annotations))
        // PDF never gets TTS or unifiedReflow
        #expect(!caps.contains(.tts))
        #expect(!caps.contains(.unifiedReflow))
        // Bug #156 / GH #456: PDF host does NOT wire AutoPageTurner.
        #expect(!caps.contains(.autoPageTurn))
    }

    @Test func azw3_doesNotSupportAutoPageTurn() {
        // Bug #156 / GH #456: AZW3 / MOBI go through Foliate-js,
        // which does not currently observe `store.autoPageTurn`.
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(!caps.contains(.autoPageTurn))
    }

    @Test func azw3_doesNotSupportTTS() {
        // Bug #176 / GH #602: AZW3 / MOBI go through Foliate-js, but
        // `ReaderAICoordinator.loadBookTextContent` has no azw3/mobi
        // case — falls through to `default: return nil`, so
        // `startTTS()`'s guard skips `ttsService.startSpeaking` and the
        // user sees silent failure. `FoliateTTSAdapter` exists (JS-side
        // hooks shipped) but is unwired in production. Until the
        // Foliate-webview TTS extraction (or in-webview TTS pipeline)
        // lands as a proper feature, hide the speaker button by
        // removing `.tts` from the AZW3 capability set — eliminates
        // the silent-failure surface. Re-add this capability when the
        // production wire-up ships.
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(!caps.contains(.tts))
    }

    @Test func txt_doesNotSupportAutoPageTurn() {
        // Bug #157 / GH #461: TXT lost AutoPageTurner support after the
        // verify cron discovered the renderer is not wired —
        // `TXTReaderContainerView.updatePaginationIfNeeded()` is dead code,
        // and there is no equivalent of MD's `pagedReaderContent` that
        // observes `pageNavigator.currentPage`.
        let caps = FormatCapabilities.capabilities(for: .txt)
        #expect(!caps.contains(.autoPageTurn))
    }

    @Test func only_md_supportsAutoPageTurn() {
        // Bug #157 / GH #461: regression-guard. After #157 narrowed the gate
        // from {TXT, MD} to {MD only} (because `TXTReaderContainerView` never
        // calls `updatePaginationIfNeeded()` and has no paged renderer), this
        // test pins the capability set. If TXT later gains a real paged
        // renderer + AutoPageTurner wiring, flip the case below AND verify the
        // `ReaderSettingsPanel.autoPageTurnSection` gate together.
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            switch format {
            case .md:
                #expect(caps.contains(.autoPageTurn), "Expected \(format) to support autoPageTurn")
            case .txt, .epub, .pdf, .azw3:
                #expect(!caps.contains(.autoPageTurn), "Expected \(format) to NOT support autoPageTurn")
            }
        }
    }

    // MARK: - Universal Capabilities

    @Test func allFormats_supportSearch() {
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(caps.contains(.search), "Expected \(format) to support search")
        }
    }

    @Test func allFormats_supportBookmarks() {
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(caps.contains(.bookmarks), "Expected \(format) to support bookmarks")
        }
    }

    // MARK: - Context-Aware (isComplexEPUB)

    @Test func capabilities_contextAware_epubSimple_hasUnifiedReflow() {
        let caps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: false)
        #expect(caps.contains(.unifiedReflow))
    }

    @Test func capabilities_contextAware_epubComplex_noUnifiedReflow() {
        let caps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: true)
        #expect(!caps.contains(.unifiedReflow))
        // Complex EPUB still has everything else
        #expect(caps.contains(.textSelection))
        #expect(caps.contains(.highlights))
        #expect(caps.contains(.tts))
        #expect(caps.contains(.toc))
        #expect(caps.contains(.search))
        #expect(caps.contains(.bookmarks))
        #expect(caps.contains(.nativePagination))
        #expect(caps.contains(.annotations))
    }

    @Test func capabilities_pdfAlwaysNative_regardlessOfEngine() {
        // isComplexEPUB param should have no effect on PDF
        let capsDefault = FormatCapabilities.capabilities(for: .pdf)
        let capsComplex = FormatCapabilities.capabilities(for: .pdf, isComplexEPUB: true)
        let capsSimple = FormatCapabilities.capabilities(for: .pdf, isComplexEPUB: false)
        #expect(capsDefault == capsComplex)
        #expect(capsDefault == capsSimple)
        #expect(!capsDefault.contains(.tts))
        #expect(!capsDefault.contains(.unifiedReflow))
    }

    // MARK: - Convenience Property on BookFormat

    @Test func bookFormat_convenienceProperty_usesDefaults() {
        // The convenience property should use default (non-complex) parameters
        let caps = BookFormat.epub.capabilities
        #expect(caps.contains(.unifiedReflow))
        #expect(caps == FormatCapabilities.capabilities(for: .epub))
    }

    @Test func bookFormat_convenienceProperty_allFormats() {
        for format in BookFormat.allCases {
            let convenience = format.capabilities
            let direct = FormatCapabilities.capabilities(for: format)
            #expect(convenience == direct, "Convenience and direct should match for \(format)")
        }
    }

    // MARK: - OptionSet Behavior

    @Test func optionSet_union() {
        let a: FormatCapabilities = [.textSelection, .highlights]
        let b: FormatCapabilities = [.highlights, .search]
        let union = a.union(b)
        #expect(union.contains(.textSelection))
        #expect(union.contains(.highlights))
        #expect(union.contains(.search))
    }

    @Test func optionSet_intersection() {
        let a: FormatCapabilities = [.textSelection, .highlights]
        let b: FormatCapabilities = [.highlights, .search]
        let intersection = a.intersection(b)
        #expect(intersection.contains(.highlights))
        #expect(!intersection.contains(.textSelection))
        #expect(!intersection.contains(.search))
    }

    @Test func optionSet_isEmpty() {
        let empty = FormatCapabilities()
        #expect(empty.isEmpty)
        let nonEmpty: FormatCapabilities = [.search]
        #expect(!nonEmpty.isEmpty)
    }

    // MARK: - Edge Cases

    @Test func isComplexEPUB_ignoredForNonEPUB() {
        // isComplexEPUB should not affect txt, md, or pdf
        for format in [BookFormat.txt, BookFormat.md, BookFormat.pdf] {
            let normal = FormatCapabilities.capabilities(for: format, isComplexEPUB: false)
            let complex = FormatCapabilities.capabilities(for: format, isComplexEPUB: true)
            #expect(normal == complex, "isComplexEPUB should not affect \(format)")
        }
    }

    @Test func sendableConformance() {
        // FormatCapabilities must be Sendable for concurrent use
        let caps: FormatCapabilities = [.search, .bookmarks]
        let _: any Sendable = caps  // Compile-time check
        #expect(caps.contains(.search))
    }

    @Test func hashableConformance() {
        // FormatCapabilities must be Hashable for use as dictionary keys / sets
        let caps1: FormatCapabilities = [.search, .bookmarks]
        let caps2: FormatCapabilities = [.search, .bookmarks]
        let caps3: FormatCapabilities = [.search, .tts]
        #expect(caps1.hashValue == caps2.hashValue)
        #expect(caps1 != caps3)

        var set = Set<FormatCapabilities>()
        set.insert(caps1)
        set.insert(caps2)
        #expect(set.count == 1)
    }
}
