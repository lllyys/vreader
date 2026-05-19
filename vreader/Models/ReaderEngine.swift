// Purpose: Internal rendering-engine selector for the reader. Replaces the
// user-visible ReadingMode (Native/Unified) toggle with a per-format engine
// chosen entirely inside the app (feature #54).
//
// Key decisions:
// - Five engines, one per current rendering host. `epubWKWebView` and
//   `foliateWeb` both exist now; `resolve(format:)` maps EPUB to
//   `epubWKWebView` unconditionally until feature #42 introduces a
//   Foliate-EPUB flag that differentiates the two.
// - `resolve(format:)` is a pure, total function over BookFormat — the
//   typed replacement for the previous `book.format.lowercased()` switch.
// - String-backed RawRepresentable so the value is stable and debuggable;
//   it is NOT persisted (no UserDefaults key) — the engine is derived from
//   the book's format on every open.
//
// @coordinates-with: BookFormat.swift — `resolve(format:)` input
// @coordinates-with: ReaderContainerView.swift — dispatch consumer (WI-3)

/// The rendering engine used for a book, selected internally by format.
///
/// This is an implementation detail: unlike the retired `ReadingMode`, it is
/// never shown to the user and never persisted. The reader dispatcher calls
/// `resolve(format:)` to pick the host for a book.
enum ReaderEngine: String, Sendable, Hashable, CaseIterable {
    /// Native TXT reader (UITextView / chunked UITableView host).
    case textNative
    /// Native Markdown reader (UITextView with attributed string).
    case markdownNative
    /// Legacy EPUB reader (custom WKWebView + JS bridge).
    case epubWKWebView
    /// Foliate-js based reader (WKWebView + Foliate bundle) — AZW3/MOBI today.
    case foliateWeb
    /// PDF reader (PDFKit `PDFView`).
    case pdfKit

    /// Selects the rendering engine for a book format.
    ///
    /// Total over `BookFormat` — every case maps to exactly one engine. EPUB
    /// resolves to `epubWKWebView` unconditionally; feature #42 will later
    /// route EPUB to `foliateWeb` behind a flag.
    static func resolve(format: BookFormat) -> ReaderEngine {
        switch format {
        case .txt:  return .textNative
        case .md:   return .markdownNative
        case .epub: return .epubWKWebView
        case .azw3: return .foliateWeb
        case .pdf:  return .pdfKit
        }
    }
}
