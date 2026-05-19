// Purpose: Feature #57 WI-2 — pins the pure decision logic behind the
// AZW3/MOBI TTS text-source branch in `startTTS()`.
//
// `startTTS()` itself is `@MainActor` SwiftUI-view code and is not
// directly unit-instantiable, so WI-2 factors the two decisions it
// makes into a pure `TTSTextSource` type that IS unit-testable:
//   - which text source a format uses (Foliate-webview extraction for
//     AZW3/MOBI vs file-load for TXT/MD/PDF/EPUB);
//   - whether a fresh `extractPlainText()` walk should start, given the
//     in-flight gate and the post-extraction cache (the three-layer
//     idempotency: playing / in-flight / post-cache).

import Testing
@testable import vreader

@Suite("Feature #57 WI-2 — TTSTextSource routing + in-flight extraction gate")
struct TTSTextSourceTests {

    // MARK: - source(for:) — which text source per format

    @Test("AZW3/MOBI routes to the Foliate-webview extraction source")
    func source_azw3_usesFoliateExtraction() {
        #expect(TTSTextSource.source(for: .azw3) == .foliateExtraction)
    }

    @Test(
        "TXT / MD / PDF / EPUB route to the file-load source (regression guard)",
        arguments: [BookFormat.txt, .md, .pdf, .epub]
    )
    func source_nonAZW3_usesFileLoad(_ format: BookFormat) {
        #expect(TTSTextSource.source(for: format) == .fileLoad,
                "Feature #57 must not change the text source for \(format) — only AZW3/MOBI gains Foliate extraction")
    }

    @Test("every BookFormat resolves to exactly one source (no format unrouted)")
    func source_everyFormatRoutes() {
        for format in BookFormat.allCases {
            let source = TTSTextSource.source(for: format)
            #expect(source == .foliateExtraction || source == .fileLoad)
        }
    }

    // MARK: - shouldStartExtraction — the in-flight gate (round-2 Finding 1)

    @Test("starts a walk when nothing is in flight and nothing is cached")
    func shouldStart_idleNoCacheNoInflight_startsWalk() {
        #expect(TTSTextSource.shouldStartExtraction(extractionInFlight: false, cachedText: nil) == true)
    }

    @Test("does NOT start a second walk while a first extraction is in flight (rapid-repeat gate)")
    func shouldStart_extractionInFlight_doesNotStart() {
        // Round-2 Finding 1: a rapid second speaker tap before the first
        // whole-book walk completes must not spawn a duplicate
        // extractPlainText() walk.
        #expect(TTSTextSource.shouldStartExtraction(extractionInFlight: true, cachedText: nil) == false)
        // Even if there were somehow cached text too, in-flight still blocks.
        #expect(TTSTextSource.shouldStartExtraction(extractionInFlight: true, cachedText: "cached") == false)
    }

    @Test("does NOT re-extract when text is already cached (post-cache fast path)")
    func shouldStart_cachedText_doesNotReextract() {
        // A re-tap after a completed, non-empty extraction takes the
        // cached-text fast path — no second evaluateJavaScript.
        #expect(TTSTextSource.shouldStartExtraction(extractionInFlight: false, cachedText: "the book text") == false)
    }

    @Test("empty cached text is NOT a usable cache — a later tap may extract again")
    func shouldStart_emptyCachedText_mayStartWalk() {
        // An extraction that genuinely returned "" (image-only book, or
        // a timed-out walk) leaves no usable cache; a later tap should
        // be allowed to try again rather than being permanently blocked.
        #expect(TTSTextSource.shouldStartExtraction(extractionInFlight: false, cachedText: "") == true)
    }
}
