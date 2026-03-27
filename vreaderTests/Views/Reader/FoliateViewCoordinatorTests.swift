// Purpose: Tests for FoliateViewCoordinator — message routing from WKScriptMessage
// to typed callbacks, and WKNavigationDelegate policy decisions.
//
// Strategy: Use mock callbacks to verify routing. FoliateMessageParser parsing is
// already tested exhaustively — these tests focus on routing and callback invocation.
//
// @coordinates-with: FoliateViewCoordinator.swift, FoliateMessageParser.swift, FoliateTypes.swift

#if canImport(UIKit)
import Testing
import Foundation
import WebKit
@testable import vreader

// MARK: - Test Helpers

/// Creates a FoliateViewCoordinator with no-op defaults. Override only the callbacks
/// you need in each test to reduce boilerplate.
@MainActor
private func makeCoordinator(
    bookFormat: String = "azw3",
    onBookReady: @escaping @MainActor (FoliateBookInfo) -> Void = { _ in },
    onRelocate: @escaping @MainActor (FoliateRelocateEvent) -> Void = { _ in },
    onSelection: @escaping @MainActor (FoliateSelectionEvent) -> Void = { _ in },
    onTap: @escaping @MainActor () -> Void = {},
    onCreateOverlay: @escaping @MainActor (Int) -> Void = { _ in },
    onAnnotationShow: @escaping @MainActor (String) -> Void = { _ in },
    onExternalLink: @escaping @MainActor (String) -> Void = { _ in },
    onError: @escaping @MainActor (String) -> Void = { _ in }
) -> FoliateViewCoordinator {
    FoliateViewCoordinator(
        bookFormat: bookFormat,
        onBookReady: onBookReady,
        onRelocate: onRelocate,
        onSelection: onSelection,
        onTap: onTap,
        onCreateOverlay: onCreateOverlay,
        onAnnotationShow: onAnnotationShow,
        onExternalLink: onExternalLink,
        onError: onError
    )
}

// MARK: - Fixtures

// swiftlint:disable let_var_whitespace
private nonisolated(unsafe) let sampleBookReadyBody: [String: Any] = [
    "title": "Test Book",
    "author": "Test Author",
    "language": "en",
    "sections": 42,
    "layout": "reflowable",
    "toc": [
        ["label": "Chapter 1", "href": "ch1.xhtml", "subitems": []] as [String: Any],
    ] as [[String: Any]],
]

private nonisolated(unsafe) let sampleRelocateBody: [String: Any] = [
    "cfi": "epubcfi(/6/14!/4/2/1:0)",
    "fraction": 0.23,
    "sectionIndex": 5,
    "sectionTotal": 65,
    "tocLabel": "Chapter 5",
    "tocHref": "chapter5.xhtml",
]

private nonisolated(unsafe) let sampleSelectionBody: [String: Any] = [
    "cfi": "epubcfi(/6/8!/4/2/3:5,/6/8!/4/2/3:42)",
    "text": "selected text passage",
    "rect": [
        "x": 100.0,
        "y": 200.0,
        "width": 250.0,
        "height": 18.0,
    ] as [String: Any],
    "index": 3,
]

private nonisolated(unsafe) let sampleErrorBody: [String: Any] = [
    "message": "Failed to parse: DRM protected",
    "type": "parse",
]

// MARK: - Message Routing Tests

@Suite("FoliateViewCoordinator — message routing")
struct FoliateViewCoordinatorMessageRoutingTests {

    @Test("handleMessage bridge-ready with base64 triggers openBook JS evaluation")
    @MainActor
    func bridgeReadyTriggersOpenBook() {
        var jsEvaluated = false
        let coordinator = makeCoordinator()
        coordinator.bookBase64 = "dGVzdA==" // base64 for "test"
        coordinator.jsEvaluator = { js in
            if js.contains("readerAPI.open") { jsEvaluated = true }
        }
        coordinator.handleMessage(name: "bridge-ready", body: "")
        #expect(jsEvaluated, "bridge-ready should trigger JS with readerAPI.open")
    }

    @Test("handleMessage bridge-ready without base64 reports error")
    @MainActor
    func bridgeReadyWithoutBase64ReportsError() {
        var receivedError: String?
        let coordinator = makeCoordinator(onError: { receivedError = $0 })
        coordinator.jsEvaluator = { _ in }
        coordinator.handleMessage(name: "bridge-ready", body: "")
        #expect(receivedError != nil, "Missing book data should report error")
    }

    @Test("handleMessage book-ready calls onBookReady with parsed info")
    @MainActor
    func bookReadyCallsCallback() {
        var receivedInfo: FoliateBookInfo?
        let coordinator = makeCoordinator(onBookReady: { receivedInfo = $0 })
        coordinator.jsEvaluator = { _ in }
        coordinator.handleMessage(name: "book-ready", body: sampleBookReadyBody)
        #expect(receivedInfo != nil)
        #expect(receivedInfo?.title == "Test Book")
        #expect(receivedInfo?.sections == 42)
        #expect(receivedInfo?.toc.count == 1)
    }

    @Test("handleMessage book-ready with unparseable body does not crash and does not call onBookReady")
    @MainActor
    func bookReadyUnparseableBody() {
        var called = false
        let coordinator = makeCoordinator(onBookReady: { _ in called = true })
        coordinator.jsEvaluator = { _ in }
        coordinator.handleMessage(name: "book-ready", body: "not a dict")
        #expect(!called)
    }

    @Test("handleMessage book-ready triggers readerAPI.init via JS evaluator")
    @MainActor
    func bookReadyTriggersInit() {
        var jsContainsInit = false
        let coordinator = makeCoordinator()
        coordinator.jsEvaluator = { js in
            if js.contains("readerAPI.init") { jsContainsInit = true }
        }
        coordinator.handleMessage(name: "book-ready", body: sampleBookReadyBody)
        #expect(jsContainsInit, "book-ready should trigger readerAPI.init")
    }

    @Test("handleMessage book-ready with saved CFI passes it to readerAPI.init")
    @MainActor
    func bookReadyWithSavedCFI() {
        var evalJS: String?
        let coordinator = makeCoordinator()
        coordinator.lastLocationCFI = "epubcfi(/6/4!/4/2)"
        coordinator.jsEvaluator = { js in
            if js.contains("readerAPI.init") { evalJS = js }
        }
        coordinator.handleMessage(name: "book-ready", body: sampleBookReadyBody)
        #expect(evalJS?.contains("epubcfi(/6/4!/4/2)") == true)
    }

    @Test("handleMessage relocate calls onRelocate with parsed event")
    @MainActor
    func relocateCallsCallback() {
        var receivedEvent: FoliateRelocateEvent?
        let coordinator = makeCoordinator(onRelocate: { receivedEvent = $0 })
        coordinator.handleMessage(name: "relocate", body: sampleRelocateBody)
        #expect(receivedEvent != nil)
        #expect(receivedEvent?.cfi == "epubcfi(/6/14!/4/2/1:0)")
        #expect(receivedEvent?.fraction == 0.23)
        #expect(receivedEvent?.sectionIndex == 5)
    }

    @Test("handleMessage relocate with unparseable body does not call onRelocate")
    @MainActor
    func relocateUnparseableBody() {
        var called = false
        let coordinator = makeCoordinator(onRelocate: { _ in called = true })
        coordinator.handleMessage(name: "relocate", body: 42)
        #expect(!called)
    }

    @Test("handleMessage selection calls onSelection with parsed event")
    @MainActor
    func selectionCallsCallback() {
        var receivedEvent: FoliateSelectionEvent?
        let coordinator = makeCoordinator(onSelection: { receivedEvent = $0 })
        coordinator.handleMessage(name: "selection", body: sampleSelectionBody)
        #expect(receivedEvent != nil)
        #expect(receivedEvent?.text == "selected text passage")
    }

    @Test("handleMessage selection with collapsed body does not call onSelection")
    @MainActor
    func selectionCollapsed() {
        var called = false
        let body: [String: Any] = [
            "cfi": "x",
            "text": "",
            "rect": ["x": 0, "y": 0, "width": 0, "height": 0] as [String: Any],
            "index": 0,
            "collapsed": true,
        ]
        let coordinator = makeCoordinator(onSelection: { _ in called = true })
        coordinator.handleMessage(name: "selection", body: body)
        #expect(!called)
    }

    @Test("handleMessage tap calls onTap")
    @MainActor
    func tapCallsCallback() {
        var called = false
        let coordinator = makeCoordinator(onTap: { called = true })
        coordinator.handleMessage(name: "tap", body: "")
        #expect(called)
    }

    @Test("handleMessage error calls onError with parsed message")
    @MainActor
    func errorCallsCallback() {
        var receivedError: String?
        let coordinator = makeCoordinator(onError: { receivedError = $0 })
        coordinator.handleMessage(name: "error", body: sampleErrorBody)
        #expect(receivedError != nil)
        #expect(receivedError?.contains("DRM protected") == true)
    }

    @Test("handleMessage error with unparseable body calls onError with fallback message")
    @MainActor
    func errorUnparseableBody() {
        var receivedError: String?
        let coordinator = makeCoordinator(onError: { receivedError = $0 })
        coordinator.handleMessage(name: "error", body: "just a string")
        #expect(receivedError != nil)
    }

    @Test("handleMessage create-overlay calls onCreateOverlay with section index")
    @MainActor
    func createOverlayCallsCallback() {
        var receivedIndex: Int?
        let coordinator = makeCoordinator(onCreateOverlay: { receivedIndex = $0 })
        coordinator.handleMessage(name: "create-overlay", body: ["index": 7] as [String: Any])
        #expect(receivedIndex == 7)
    }

    @Test("handleMessage annotation-show calls onAnnotationShow with value")
    @MainActor
    func annotationShowCallsCallback() {
        var receivedValue: String?
        let coordinator = makeCoordinator(onAnnotationShow: { receivedValue = $0 })
        coordinator.handleMessage(name: "annotation-show", body: ["value": "epubcfi(/6/4!/4/2/3:5)"] as [String: Any])
        #expect(receivedValue == "epubcfi(/6/4!/4/2/3:5)")
    }

    @Test("handleMessage external-link calls onExternalLink with href")
    @MainActor
    func externalLinkCallsCallback() {
        var receivedURL: String?
        let coordinator = makeCoordinator(onExternalLink: { receivedURL = $0 })
        coordinator.handleMessage(name: "external-link", body: ["href": "https://example.com"] as [String: Any])
        #expect(receivedURL == "https://example.com")
    }

    @Test("handleMessage unknown name does not crash")
    @MainActor
    func unknownMessageName() {
        let coordinator = makeCoordinator()
        coordinator.handleMessage(name: "totally-unknown-event", body: [:] as [String: Any])
    }

    @Test("handleMessage section-load does not crash")
    @MainActor
    func sectionLoadDoesNotCrash() {
        let coordinator = makeCoordinator()
        coordinator.handleMessage(name: "section-load", body: ["index": 3] as [String: Any])
    }
}

// MARK: - Navigation Policy Tests

@Suite("FoliateViewCoordinator — navigation policy")
struct FoliateViewCoordinatorNavigationPolicyTests {

    @Test("allows vreader-resource:// scheme")
    @MainActor
    func allowsSchemeHandler() {
        let coordinator = makeCoordinator()
        let url = URL(string: "vreader-resource://localhost/index.html")!
        #expect(FoliateViewCoordinator.shouldAllowNavigation(to: url) == true)
    }

    @Test("allows blob:// scheme")
    @MainActor
    func allowsBlobScheme() {
        let coordinator = makeCoordinator()
        let url = URL(string: "blob:vreader-resource://localhost/abc123")!
        #expect(FoliateViewCoordinator.shouldAllowNavigation(to: url) == true)
    }

    @Test("allows about:blank")
    @MainActor
    func allowsAboutBlank() {
        let coordinator = makeCoordinator()
        let url = URL(string: "about:blank")!
        #expect(FoliateViewCoordinator.shouldAllowNavigation(to: url) == true)
    }

    @Test("blocks http:// scheme")
    @MainActor
    func blocksHTTP() {
        let coordinator = makeCoordinator()
        let url = URL(string: "http://example.com")!
        #expect(FoliateViewCoordinator.shouldAllowNavigation(to: url) == false)
    }

    @Test("blocks https:// scheme")
    @MainActor
    func blocksHTTPS() {
        let coordinator = makeCoordinator()
        let url = URL(string: "https://example.com/page")!
        #expect(FoliateViewCoordinator.shouldAllowNavigation(to: url) == false)
    }

    @Test("blocks file:// scheme")
    @MainActor
    func blocksFile() {
        let coordinator = makeCoordinator()
        let url = URL(string: "file:///etc/passwd")!
        #expect(FoliateViewCoordinator.shouldAllowNavigation(to: url) == false)
    }
}

// MARK: - openBookJS generation

@Suite("FoliateViewCoordinator — openBookJS")
struct FoliateViewCoordinatorOpenBookJSTests {

    @Test("openBookJS includes fetch from scheme handler URL")
    @MainActor
    func openBookJSIncludesFetch() {
        let js = FoliateViewCoordinator.openBookJS(format: "azw3")
        #expect(js.contains("fetch"))
        #expect(js.contains("vreader-resource://localhost/book/file"))
    }

    @Test("openBookJS includes book extension")
    @MainActor
    func openBookJSIncludesExtension() {
        let js = FoliateViewCoordinator.openBookJS(format: "azw3")
        #expect(js.contains("book.azw3"))
    }

    @Test("openBookJS for epub uses epub extension")
    @MainActor
    func openBookJSForEpub() {
        let js = FoliateViewCoordinator.openBookJS(format: "epub")
        #expect(js.contains("book.epub"))
    }

    @Test("openBookJS includes readerAPI.open call")
    @MainActor
    func openBookJSIncludesAPIOpen() {
        let js = FoliateViewCoordinator.openBookJS(format: "mobi")
        #expect(js.contains("readerAPI.open"))
    }

    @Test("openBookJS includes error handler posting to webkit.messageHandlers")
    @MainActor
    func openBookJSIncludesErrorHandler() {
        let js = FoliateViewCoordinator.openBookJS(format: "azw3")
        #expect(js.contains("messageHandlers"))
        #expect(js.contains("error"))
    }
}

// MARK: - initJS generation

@Suite("FoliateViewCoordinator — initJS")
struct FoliateViewCoordinatorInitJSTests {

    @Test("initJS without CFI generates empty init")
    @MainActor
    func initJSWithoutCFI() {
        let js = FoliateViewCoordinator.initJS(cfi: nil)
        #expect(js.contains("readerAPI.init"))
        #expect(!js.contains("epubcfi"))
    }

    @Test("initJS with CFI includes the CFI value")
    @MainActor
    func initJSWithCFI() {
        let js = FoliateViewCoordinator.initJS(cfi: "epubcfi(/6/4!/4/2)")
        #expect(js.contains("readerAPI.init"))
        #expect(js.contains("epubcfi(/6/4!/4/2)"))
    }

    @Test("initJS with CFI containing special chars escapes properly")
    @MainActor
    func initJSEscapesCFI() {
        let js = FoliateViewCoordinator.initJS(cfi: "epubcfi(/6/4[it's]!/4/2)")
        #expect(js.contains("readerAPI.init"))
        #expect(js.contains("\\'"))
    }
}

// MARK: - openBookBase64JS generation

@Suite("FoliateViewCoordinator — openBookBase64JS")
struct FoliateViewCoordinatorOpenBookBase64JSTests {

    @Test("includes atob and Uint8Array for base64 decoding")
    @MainActor
    func includesBase64Decoding() {
        let js = FoliateViewCoordinator.openBookBase64JS(base64: "AAAA", format: "azw3")
        #expect(js.contains("atob"))
        #expect(js.contains("Uint8Array"))
    }

    @Test("includes the base64 data")
    @MainActor
    func includesBase64Data() {
        let js = FoliateViewCoordinator.openBookBase64JS(base64: "dGVzdA==", format: "azw3")
        #expect(js.contains("dGVzdA=="))
    }

    @Test("includes book format extension")
    @MainActor
    func includesFormat() {
        let js = FoliateViewCoordinator.openBookBase64JS(base64: "AA==", format: "mobi")
        #expect(js.contains("book.mobi"))
    }

    @Test("includes readerAPI.open call")
    @MainActor
    func includesAPIOpen() {
        let js = FoliateViewCoordinator.openBookBase64JS(base64: "AA==", format: "azw3")
        #expect(js.contains("readerAPI.open"))
    }

    @Test("includes error handler")
    @MainActor
    func includesErrorHandler() {
        let js = FoliateViewCoordinator.openBookBase64JS(base64: "AA==", format: "azw3")
        #expect(js.contains("messageHandlers"))
        #expect(js.contains("error"))
    }

    @Test("creates a File object from decoded bytes")
    @MainActor
    func createsFileObject() {
        let js = FoliateViewCoordinator.openBookBase64JS(base64: "AA==", format: "epub")
        #expect(js.contains("new File"))
    }
}
#endif
