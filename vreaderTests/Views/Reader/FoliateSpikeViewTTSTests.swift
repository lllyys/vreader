// Purpose: Feature #57 WI-1 — pins the Swift side of the AZW3/MOBI
// TTS text-extraction seam.
//
// Feature #57 wires read-aloud for AZW3/MOBI by extracting the
// rendered book's whole-book plain text from the Foliate WKWebView
// (`readerAPI.extractPlainText()`, a section-walk over
// `view.book.sections[].createDocument()`) and feeding it to the
// shared `AVSpeechSynthesizer` pipeline.
//
// This file covers the unit-testable contract:
//   - `FoliateSpikeView.Coordinator.extractPlainText()` guards
//     (book-not-ready → nil, webView-deallocated → nil).
//   - `FoliateCoordinatorBox` weak-holding (no retain cycle) and
//     its nil default.
//
// NOT covered here (by design — needs a live WKWebView + Foliate
// render the XCUnit harness cannot provide): real `extractPlainText`
// output against a rendered book, and whether the returned
// `Promise<string>` resolves to that text in Swift. Those are the
// WI-1 device-slice feasibility gate (plan §5) and WI-4's acceptance
// pass.

#if canImport(UIKit)
import Testing
import Foundation
import WebKit
@testable import vreader

@MainActor
@Suite("Feature #57 WI-1 — FoliateSpikeView TTS text-extraction seam")
struct FoliateSpikeViewTTSTests {

    private func makeCoordinator() -> FoliateSpikeView.Coordinator {
        FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            onBookReady: { _ in },
            onError: { _ in }
        )
    }

    // MARK: - extractPlainText() guards

    @Test("extractPlainText returns nil when the book is not yet ready (no extraction before layout-ready)")
    func extractPlainText_returnsNil_whenBookNotReady() async {
        let coordinator = makeCoordinator()
        // A fresh coordinator has not received `layout-ready`, so
        // `isBookReady` is false. A WKWebView is attached but the
        // book-readiness gate must still short-circuit.
        coordinator.webView = WKWebView()
        #expect(coordinator.isBookReady == false)

        let text = await coordinator.extractPlainText()

        #expect(text == nil,
                "Feature #57: extractPlainText must return nil before the book is ready — the section-walk is invalid until Foliate finished rendering")
    }

    @Test("extractPlainText returns nil when the webView has been deallocated (teardown safety)")
    func extractPlainText_returnsNil_whenWebViewDeallocated() async {
        let coordinator = makeCoordinator()
        // Simulate the reader being dismissed: book was ready, but the
        // weak webView is gone.
        coordinator.isBookReady = true
        coordinator.webView = nil

        let text = await coordinator.extractPlainText()

        #expect(text == nil,
                "Feature #57: extractPlainText must return nil when the weak webView is gone — a dismissed reader must not crash")
    }

    @Test("extractPlainText runs exactly the fixed readerAPI.extractPlainText() body (no interpolation, no injection surface)")
    func extractPlainText_evaluatesExactHelperScript() {
        // The callAsyncJavaScript body is a fixed literal — there is no
        // string interpolation of book content or user input into it,
        // so there is no JS-injection surface. Pinned so a refactor
        // that accidentally interpolates is caught. `callAsyncJavaScript`
        // (not evaluateJavaScript) is used so the returned Promise is
        // awaited — hence the `return await` form.
        #expect(FoliateSpikeView.Coordinator.extractPlainTextScript
                == "return await readerAPI.extractPlainText();")
    }

    @Test("extractPlainText carries a bounded timeout so a hung JS extraction cannot wedge a TTS caller")
    func extractPlainText_hasBoundedTimeout() {
        // A malformed Foliate section or a wedged WebKit render could
        // leave callAsyncJavaScript suspended forever; the timeout is
        // the defense so a downstream TTS caller can never hang.
        #expect(FoliateSpikeView.Coordinator.extractPlainTextTimeout > .zero)
        #expect(FoliateSpikeView.Coordinator.extractPlainTextTimeout <= .seconds(30),
                "timeout must be short enough that a wedged extraction frees the caller promptly")
    }

    // MARK: - FoliateCoordinatorBox

    @Test("FoliateCoordinatorBox defaults to a nil coordinator (a startTTS before render is a clean no-op)")
    func foliateCoordinatorBox_defaultsToNilCoordinator() {
        let box = FoliateCoordinatorBox()
        #expect(box.coordinator == nil,
                "Feature #57: a fresh box has no coordinator — startTTS() before the reader mounts must see nil and no-op")
    }

    @Test("FoliateCoordinatorBox holds the coordinator weakly (no retain cycle)")
    func foliateCoordinatorBox_holdsCoordinatorWeakly() {
        let box = FoliateCoordinatorBox()
        do {
            let coordinator = makeCoordinator()
            box.coordinator = coordinator
            #expect(box.coordinator === coordinator)
        }
        // The strong reference dropped at the end of the `do` scope.
        // If the box held the coordinator strongly, this would still
        // be non-nil — a retain cycle (box → coordinator → webView →
        // ... → box) would leak the whole reader.
        #expect(box.coordinator == nil,
                "Feature #57: FoliateCoordinatorBox must hold the coordinator weakly — a strong hold leaks the reader")
    }
}
#endif
