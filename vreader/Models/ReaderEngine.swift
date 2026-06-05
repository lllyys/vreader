// Purpose: Internal rendering-engine selector for the reader. Replaces the
// user-visible ReadingMode (Native/Unified) toggle with a per-format engine
// chosen entirely inside the app (feature #54).
//
// Key decisions:
// - Six engines, one per current rendering host plus the Readium EPUB engine
//   (feature #42 Phase 1, flag-gated). `epubWKWebView` is the live EPUB default;
//   `epubReadium` is the Readium-Navigator host selected only when the
//   `readiumEPUBEngine` flag is ON.
// - `resolve(format:)` stays a pure, total function over BookFormat and maps
//   EPUB to `epubWKWebView` UNCONDITIONALLY (the typed replacement for the old
//   `book.format.lowercased()` switch). The Readium flag branch is a SEPARATE
//   pure helper — `routeEPUB(readiumFlagEnabled:)` — so `resolve` never reads a
//   feature flag (the flag check lives in the dispatcher; feature #42 plan).
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
    /// Legacy EPUB reader (custom WKWebView + JS bridge). The live default.
    case epubWKWebView
    /// Readium Swift Toolkit EPUB reader (`EPUBNavigatorViewController`).
    /// Selected only when the `readiumEPUBEngine` flag is ON (feature #42).
    case epubReadium
    /// Foliate-js based reader (WKWebView + Foliate bundle) — AZW3/MOBI today.
    case foliateWeb
    /// PDF reader (PDFKit `PDFView`).
    case pdfKit

    /// Selects the rendering engine for a book format.
    ///
    /// Total over `BookFormat` — every case maps to exactly one engine. EPUB
    /// resolves to `epubWKWebView` unconditionally; the Readium-vs-legacy EPUB
    /// choice is made by `routeEPUB(readiumFlagEnabled:)` in the dispatcher so
    /// this function never reads a feature flag.
    static func resolve(format: BookFormat) -> ReaderEngine {
        switch format {
        case .txt:  return .textNative
        case .md:   return .markdownNative
        case .epub: return .epubWKWebView
        case .azw3: return .foliateWeb
        case .pdf:  return .pdfKit
        }
    }

    /// Picks the EPUB rendering engine given the `readiumEPUBEngine` flag state.
    /// Pure (no flag read inside — the caller passes the resolved flag value) so
    /// the dispatcher's routing decision is unit-testable. Feature #42 Phase 1:
    /// flag ON → the Readium host (paged) or the legacy host (scroll); flag OFF
    /// → the legacy `EPUBWebViewBridge` for both modes.
    ///
    /// Feature #85 (approach C): Readium's per-resource paginator has an
    /// inherent chapter-boundary SEAM in **scroll** mode (its closed paginator
    /// has no stitch injection point). Route EPUB scroll to the legacy
    /// `epubWKWebView` engine — which activates the feature-#71 continuous-scroll
    /// stitch (single-column, seamless) — even when Readium is the default.
    /// **Paged** mode keeps Readium (no seam there; Readium's paged parity is the
    /// WI-13 acceptance work). Pure (the caller passes the resolved flag +
    /// layout) so the routing truth table is unit-testable.
    static func routeEPUB(
        readiumFlagEnabled: Bool,
        layout: EPUBLayoutPreference
    ) -> ReaderEngine {
        guard readiumFlagEnabled else { return .epubWKWebView }
        return layout == .scroll ? .epubWKWebView : .epubReadium
    }
}
