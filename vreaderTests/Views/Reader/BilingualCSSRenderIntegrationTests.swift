// Bug #304 — verification-exception integration test. The fix injects the
// `.vreader-bilingual` interlinear CSS into the modern engines (Readium spine /
// Foliate setStyles) so translation blocks render styled (smaller, muted, accent
// left border, indent) instead of plain body text. The end-to-end VISUAL (a real
// AI translation rendered + styled) is AI-provider-gated and can't be exercised
// CU-free without a credential. This test closes that gap at the real subsystem
// boundary WITHOUT AI: it loads a document containing a
// `.vreader-bilingual[data-vreader-decoration]` block into a LIVE WKWebView,
// injects the PRODUCTION `EPUBBilingualJS.bilingualStyleJS(css:)` with the real
// per-theme rule, and asserts the element's COMPUTED style reflects the fix —
// i.e. the injected CSS actually styles a bilingual block (the exact failure mode
// #304 describes: "render as plain body text — no smaller size, no accent left
// border"). The `.vreader-bilingual` element's text is synthetic, but the class +
// `data-vreader-decoration` attribute are exactly what the CSS targets, so this
// drives the same inject→render→style path a real translation block would.
//
// @coordinates-with vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift,
//   vreader/Models/ReaderThemeV2+EPUBCSS.swift

#if canImport(WebKit)
import Testing
import WebKit
@testable import vreader

@MainActor
@Suite("Bilingual interlinear CSS renders styled in a live WKWebView (Bug #304)")
struct BilingualCSSRenderIntegrationTests {

    /// A document whose body is a known 20px so the `0.88em` rule resolves to a
    /// deterministic 17.6px, with a `.vreader-bilingual[data-vreader-decoration]`
    /// block and a plain sibling for contrast.
    private let html = """
    <!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>html, body { -webkit-text-size-adjust: none; text-size-adjust: none; }</style>
    </head>
    <body style="font-size:20px;">
      <p id="plain">source line</p>
      <div id="bi" class="vreader-bilingual" data-vreader-decoration>译文</div>
    </body></html>
    """

    /// Loads `html`, injects the production bilingual style JS for `theme`, then
    /// reads back `readback` (a single JS expression) from the live document.
    private func renderAndRead(theme: ReaderThemeV2, readback: String) async throws -> String? {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            delegate.onFinish = { cont.resume() }
            webView.loadHTMLString(html, baseURL: nil)
        }
        try await webView.run(EPUBBilingualJS.bilingualStyleJS(css: theme.bilingualBlockCSSRule()))
        return try await webView.evaluateString(readback)
    }

    @Test("the injected <style id=vreader-bilingual-style> is present after injection")
    func styleElementInjected() async throws {
        let count = try await renderAndRead(
            theme: .paper,
            readback: "document.querySelectorAll('#vreader-bilingual-style').length")
        #expect(count == "1", "the production JS must inject exactly one bilingual <style> element")
    }

    @Test("the bilingual block renders SMALLER than the plain sibling (0.88em ratio)")
    func blockIsSmaller() async throws {
        // Read the RATIO of the two computed font-sizes — robust against WKWebView's
        // -webkit-text-size-adjust scaling both equally (the absolute px shifts, the
        // 0.88 ratio is preserved). The bug was "no smaller size"; the ratio proves it.
        let ratio = try await renderAndRead(
            theme: .paper,
            readback: "(parseFloat(getComputedStyle(document.getElementById('bi')).fontSize) / parseFloat(getComputedStyle(document.getElementById('plain')).fontSize)).toFixed(2)")
        #expect(ratio == "0.88",
                "the .vreader-bilingual block must render at 0.88× the plain sibling (smaller), not plain body size")
    }

    @Test("the bilingual block has the 2px solid accent LEFT BORDER")
    func blockHasAccentLeftBorder() async throws {
        let width = try await renderAndRead(
            theme: .paper, readback: "getComputedStyle(document.getElementById('bi')).borderLeftWidth")
        #expect(width == "2px", "the accent left border must be 2px (was absent pre-fix)")
        let style = try await renderAndRead(
            theme: .paper, readback: "getComputedStyle(document.getElementById('bi')).borderLeftStyle")
        #expect(style == "solid", "the left border must be solid")
        // The plain sibling has no left border.
        let plainWidth = try await renderAndRead(
            theme: .paper, readback: "getComputedStyle(document.getElementById('plain')).borderLeftWidth")
        #expect(plainWidth == "0px", "the plain sibling has no left border — the affordance is unique to the translation")
    }

    @Test("the bilingual block is non-selectable (user-select: none)")
    func blockIsNonSelectable() async throws {
        let sel = try await renderAndRead(
            theme: .paper,
            readback: "(getComputedStyle(document.getElementById('bi')).webkitUserSelect || getComputedStyle(document.getElementById('bi')).userSelect)")
        #expect(sel == "none", "translation blocks must be non-selectable (design intent)")
    }

    @Test("the style holds across themes (sepia accent differs but the structure is styled)")
    func stylesUnderSepiaToo() async throws {
        let ratio = try await renderAndRead(
            theme: .sepia,
            readback: "(parseFloat(getComputedStyle(document.getElementById('bi')).fontSize) / parseFloat(getComputedStyle(document.getElementById('plain')).fontSize)).toFixed(2)")
        #expect(ratio == "0.88")
        let width = try await renderAndRead(
            theme: .sepia, readback: "getComputedStyle(document.getElementById('bi')).borderLeftWidth")
        #expect(width == "2px")
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?(); onFinish = nil
    }
}

private extension WKWebView {
    func run(_ js: String) async throws {
        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            evaluateJavaScript("{ \(js) }; true") { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: true) }
            }
        }
    }
    func evaluateString(_ js: String) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            evaluateJavaScript("String(\(js))") { value, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: value as? String) }
            }
        }
    }
}
#endif
