// Purpose: Feature #86 Gate-5 end-to-end acceptance — the whole-book-scope chat
// ANSWERS and renders its reply, verified KEY-FREE via the DEBUG MockAIProvider
// (`--mock-ai`, v3.59.10). This closes the residual that was "provider-key-blocked
// → keyed-verification before VERIFIED": with the mock injected into AIService,
// the reader AI Chat tab at Book-so-far scope drives the real coordinator →
// whole-book retrieval → chat → streamed reply path and renders a deterministic
// [MOCK] answer — no real API key required.
//
// All accessibility identifiers already exist on the shipped UI (readerAIButton,
// aiReaderPanel, aiReaderTabPicker, chatContextScopeChip, chatScopeRow.*,
// chatInputField, chatSendButton, chatBubble-assistant).

import XCTest

final class Feature86WholeBookChatVerificationTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens the seeded EPUB → reader → AI panel → Chat tab, sends a question,
    /// and asserts the deterministic [MOCK] assistant reply renders — verifying
    /// #86's "answering" residual KEY-FREE (the part that was provider-key-blocked).
    /// Scope selection / whole-book retrieval / "Drew on" citation rendering are
    /// device-verified separately across WI-3..WI-6 (see the `docs/features.md` row).
    func testReaderAIChatAnswersKeyFree() throws {
        let app = LaunchHelper.launchApp(
            seed: .epubFixture,
            enableAI: true,
            extraLaunchArguments: ["--mock-ai"]
        )

        // 1. Open the seeded book (first library card).
        let bookCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'bookCard_'"))
            .firstMatch
        XCTAssertTrue(bookCard.waitForExistence(timeout: 20), "Seeded EPUB card should appear in the library")
        bookCard.tap()

        // 2. Reveal the reader chrome + open the AI panel. The reader chrome
        //    auto-hides, so the AI button may exist but not be hittable — reveal
        //    chrome with a center tap, then tap the button once it is hittable.
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let aiButton = app.buttons["readerAIButton"]
        _ = aiButton.waitForExistence(timeout: 15)
        let panel = app.descendants(matching: .any).matching(identifier: "aiReaderPanel").firstMatch
        var opened = false
        for _ in 0..<4 {
            center.tap()                       // reveal chrome
            if aiButton.waitForExistence(timeout: 3), aiButton.isHittable {
                aiButton.tap()
                if panel.waitForExistence(timeout: 6) { opened = true; break }
            }
        }
        XCTAssertTrue(opened, "AI Reader panel should present after tapping the reader AI button")

        // 3. Switch to the Chat tab. The tab control is a UISegmentedControl
        //    (ThemedSegmentedPicker), so the "Chat" segment is a button WITHIN it.
        let tabPicker = app.segmentedControls.firstMatch
        XCTAssertTrue(tabPicker.waitForExistence(timeout: 8), "AI tab picker should be present")
        let chatSegment = tabPicker.buttons["Chat"]
        XCTAssertTrue(chatSegment.waitForExistence(timeout: 5), "Chat tab segment should be present")
        chatSegment.tap()

        // The reader AI panel's container `.accessibilityIdentifier("aiReaderPanel")`
        // propagates onto descendants (Bug #209/#214), shadowing the chat element
        // IDs — so from here we query by element TYPE + accessibility LABEL, which
        // the panel does not shadow (the tab picker above worked the same way).

        // 4. The composer is the only text input on the Chat tab — a multiline
        //    `TextField(axis:.vertical)`, exposed as a textView (fall back textField).
        var input = app.textViews.firstMatch
        if !input.waitForExistence(timeout: 12) { input = app.textFields.firstMatch }
        XCTAssertTrue(input.waitForExistence(timeout: 5),
                      "Chat composer input should be present on the active Chat tab")
        input.tap()
        input.typeText("What is this book about?")

        // 5. Send via the button labelled "Send" (label survives ID shadowing).
        let sendButton = app.buttons.matching(NSPredicate(format: "label == 'Send'")).firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 6), "Send button (label 'Send') should be present")
        sendButton.tap()

        // 6. The chat answers KEY-FREE via the mock. Assert a staticText carrying the
        //    deterministic [MOCK] marker renders — the answering residual that was
        //    provider-key-blocked is now verified without a real API key.
        let mockReply = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '[MOCK]'")
        ).firstMatch
        XCTAssertTrue(
            mockReply.waitForExistence(timeout: 30),
            "The rendered assistant answer should contain the deterministic [MOCK] marker"
        )
    }
}
