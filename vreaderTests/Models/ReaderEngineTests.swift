// Purpose: Tests for ReaderEngine enum — the internal rendering-engine selector
// that replaces the user-visible ReadingMode toggle (feature #54 WI-1).
// Covers ReaderEngine.resolve(format:) for all 5 BookFormat cases plus
// Sendable / Hashable / CaseIterable conformance and raw-value stability.

import Testing
import Foundation
@testable import vreader

@Suite("ReaderEngine")
struct ReaderEngineTests {

    // MARK: - resolve(format:)

    @Test func resolve_txt_isTextNative() {
        #expect(ReaderEngine.resolve(format: .txt) == .textNative)
    }

    @Test func resolve_md_isMarkdownNative() {
        #expect(ReaderEngine.resolve(format: .md) == .markdownNative)
    }

    @Test func resolve_epub_isEPUBWKWebView() {
        #expect(ReaderEngine.resolve(format: .epub) == .epubWKWebView)
    }

    @Test func resolve_azw3_isFoliateWeb() {
        #expect(ReaderEngine.resolve(format: .azw3) == .foliateWeb)
    }

    @Test func resolve_pdf_isPDFKit() {
        #expect(ReaderEngine.resolve(format: .pdf) == .pdfKit)
    }

    /// Every BookFormat resolves to a non-nil engine — exhaustiveness guard.
    @Test func resolve_coversEveryBookFormat() {
        for format in BookFormat.allCases {
            let engine = ReaderEngine.resolve(format: format)
            // CaseIterable membership confirms it is a real enum case.
            #expect(ReaderEngine.allCases.contains(engine))
        }
    }

    // MARK: - CaseIterable

    @Test func caseIterable_hasSixCases() {
        // Six engines: feature #42 added `.epubReadium` (flag-gated EPUB).
        #expect(ReaderEngine.allCases.count == 6)
    }

    @Test func caseIterable_containsAllExpectedCases() {
        let all = ReaderEngine.allCases
        #expect(all.contains(.textNative))
        #expect(all.contains(.markdownNative))
        #expect(all.contains(.epubWKWebView))
        #expect(all.contains(.epubReadium))
        #expect(all.contains(.foliateWeb))
        #expect(all.contains(.pdfKit))
    }

    // MARK: - Raw values (stability contract)

    @Test func rawValues_areStable() {
        #expect(ReaderEngine.textNative.rawValue == "textNative")
        #expect(ReaderEngine.markdownNative.rawValue == "markdownNative")
        #expect(ReaderEngine.epubWKWebView.rawValue == "epubWKWebView")
        #expect(ReaderEngine.epubReadium.rawValue == "epubReadium")
        #expect(ReaderEngine.foliateWeb.rawValue == "foliateWeb")
        #expect(ReaderEngine.pdfKit.rawValue == "pdfKit")
    }

    @Test func initFromRawValue_roundTrips() {
        for engine in ReaderEngine.allCases {
            #expect(ReaderEngine(rawValue: engine.rawValue) == engine)
        }
        #expect(ReaderEngine(rawValue: "unknown") == nil)
        #expect(ReaderEngine(rawValue: "") == nil)
    }

    // MARK: - Hashable

    @Test func hashable_usableInSet() {
        var set = Set<ReaderEngine>()
        for engine in ReaderEngine.allCases {
            set.insert(engine)
        }
        set.insert(.textNative) // duplicate
        #expect(set.count == 6)
    }

    // MARK: - Sendable

    @Test func sendable_compiles() {
        let engine: ReaderEngine = .pdfKit
        let _: any Sendable = engine
        #expect(engine == .pdfKit)
    }
}
