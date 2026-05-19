// Purpose: Feature #57 — the pure decision logic behind the AZW3/MOBI
// TTS text-source branch in `ReaderContainerView.startTTS()`.
//
// `startTTS()` is `@MainActor` SwiftUI-view code (not unit-instantiable),
// so the two decisions it makes are factored here into a pure,
// testable type:
//   1. `source(for:)` — which text source a format uses. AZW3/MOBI text
//      lives only inside the Foliate WKWebView (no Swift-side parser),
//      so it routes to `.foliateExtraction`; TXT/MD/PDF/EPUB keep the
//      existing file-load path (`.fileLoad`).
//   2. `shouldStartExtraction(extractionInFlight:cachedText:)` — the
//      in-flight extraction gate. The whole-book `extractPlainText()`
//      section walk takes noticeable time; a rapid second speaker tap
//      before it completes must not spawn a duplicate walk. Combined
//      with `startTTS()`'s own `ttsService.state != .idle` early-return,
//      this gives three-layer idempotency: playing / in-flight /
//      post-cache.

import Foundation

/// Feature #57: where `startTTS()` sources the book's plain text for a
/// given format.
enum TTSTextSource: Equatable {
    /// Extract the whole-book text from the live Foliate WKWebView via
    /// `readerAPI.extractPlainText()` — AZW3/MOBI, which have no
    /// Swift-side parser.
    case foliateExtraction
    /// Load the text from the book file via `loadBookTextContent` /
    /// `BookContentCache` — TXT/MD/PDF/EPUB.
    case fileLoad

    /// The text source for a book format.
    static func source(for format: BookFormat) -> TTSTextSource {
        switch format {
        case .azw3:
            return .foliateExtraction
        case .txt, .md, .pdf, .epub:
            return .fileLoad
        }
    }

    /// Whether a fresh `extractPlainText()` whole-book walk should
    /// start, given the in-flight gate and the post-extraction cache.
    ///
    /// - `extractionInFlight` — true when a previous `extractPlainText()`
    ///   walk has not yet completed. A rapid second speaker tap during
    ///   that window must NOT spawn a duplicate walk (round-2 Finding 1).
    /// - `cachedText` — the AI coordinator's `loadedTextContent`. A
    ///   non-empty value means a prior walk already produced text; the
    ///   caller takes the cached-text fast path instead of re-extracting.
    ///   An *empty* string is not a usable cache (an image-only book or
    ///   a timed-out walk) — a later tap may extract again.
    ///
    /// Returns `true` only when no walk is in flight AND there is no
    /// usable cached text.
    static func shouldStartExtraction(extractionInFlight: Bool, cachedText: String?) -> Bool {
        if extractionInFlight { return false }
        if let cachedText, !cachedText.isEmpty { return false }
        return true
    }
}
