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
        #expect(caps.contains(.unifiedReflow))
        #expect(caps.contains(.annotations))
        // Bug #156 / GH #456: TXT host wires AutoPageTurner.
        #expect(caps.contains(.autoPageTurn))
        // TXT does NOT have TOC
        #expect(!caps.contains(.toc))
    }

    @Test func md_supportsTextSelection_highlights_tts_pagination() {
        let caps = FormatCapabilities.capabilities(for: .md)
        #expect(caps.contains(.textSelection))
        #expect(caps.contains(.highlights))
        #expect(caps.contains(.tts))
        #expect(caps.contains(.nativePagination))
        #expect(caps.contains(.unifiedReflow))
        #expect(caps.contains(.annotations))
        // Bug #156 / GH #456: MD host wires AutoPageTurner.
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

    @Test func only_txt_and_md_supportAutoPageTurn() {
        // Bug #156 / GH #456: regression-guard. If any future format gains
        // working AutoPageTurner wiring (or TXT/MD lose it), this test
        // forces the codebase to update both the capability set AND the
        // ReaderSettingsPanel gate together.
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            switch format {
            case .txt, .md:
                #expect(caps.contains(.autoPageTurn), "Expected \(format) to support autoPageTurn")
            case .epub, .pdf, .azw3:
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
