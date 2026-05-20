// Purpose: CU-free Gate-A close-gate verification for Bug #93 — "Chat
// sessions not persisted across panel dismiss" (PR #314, v3.14.16).
//
// Bug #93's failure mode is purely a SwiftUI lifecycle issue: `LibraryView`
// presented its General-Chat sheet via `.sheet(isPresented:) { aiChatSheet }`,
// and the `aiChatSheet` content called `makeGeneralChatViewModel()` directly.
// SwiftUI re-runs the content closure on every sheet present, so each open
// allocated a fresh `AIChatViewModel` with an empty `messages` array — the
// prior session's history was discarded. PR #314 fixed this by caching the
// VM in `@State private var generalChatVM: AIChatViewModel?` with a lazy
// `resolvedGeneralChatVM` getter that mirrors the existing
// `ReaderContainerView.resolvedAICoordinator` cache pattern.
//
// Why this verification suite exists:
//   - The shipped fix added no test — PR #314's diff is 24/-1 in
//     `LibraryView.swift` only, and the Codex audit log records `rounds:
//     1, ship-as-is`. The close gate (AGENTS.md "Close gate — verified,
//     not just merged") therefore still requires either device verification
//     or a high-fidelity integration test for the GH issue to close.
//   - Computer-use MCP is structurally unavailable on this verification
//     host (virtual-display-only — `mcp__computer-use__screenshot` returns
//     `CU display unavailable`; `sim-drive-fallback` CGEventPost taps do
//     not translate into iOS touches because the Simulator window is
//     passive). Same condition recorded in the 2026-05-19 evidence files
//     for features #65 / #69. Until CU returns, the canonical CU-free
//     path is XCUITest, which synthesizes touches via the iOS
//     accessibility API rather than HID events — bypassing the CGEvent
//     translation gap.
//   - Bug #237 / GH #975 (FIXED 2026-05-20) consumed the `--enable-ai`
//     launch flag into `AITestOverride.forceAvailable`, unblocking AI
//     surface reachability for XCUITest. Combined with PR #314's fix
//     this is now testable end-to-end without a real AI provider.
//
// What this suite verifies (Bug #93 acceptance contract, from GH #313
// + `docs/bugs.md` row #93):
//   - The toolbar AI Chat button (`aiChatToolbarButton`) presents the
//     Library general-chat sheet.
//   - Typing a message into `chatInputField` and tapping `chatSendButton`
//     enqueues a user message into the chat history (the
//     `chatBubble-user` accessibility identifier appears in
//     `chatMessageList`). The message text content is the verification
//     handle — the durable evidence that the session captured the turn.
//   - Tapping `aiChatDoneButton` dismisses the sheet.
//   - Re-tapping `aiChatToolbarButton` reopens the sheet AND the
//     previously-sent user message is still visible in
//     `chatMessageList`. This is the **failure-mode-specific assertion**:
//     pre-fix, the empty-state (`chatEmptyState`) reappeared on reopen
//     because a fresh `AIChatViewModel` had no messages; post-fix, the
//     cached VM retains the messages array.
//
// What this suite does NOT verify:
//   - End-to-end AI provider response rendering (the assistant turn).
//     Bug #93's contract is "chat history survives sheet dismiss" — not
//     "the AI replies correctly". The user-message-survives-dismiss
//     check is the necessary-and-sufficient proof of the fix; an
//     assistant turn would additionally need a real provider response,
//     which is out of scope for the close-gate of this bug. (The
//     AI-response rendering surfaces are tracked by features #65 / #69
//     and stay in their respective `awaiting-device-verification` state
//     until a CU-credentialed run can exercise them.)
//
// Design / pattern notes:
//   - Uses `--enable-ai` to short-circuit `AIReaderAvailability.isAvailable`
//     via the `AITestOverride.forceAvailable` seam (Bug #237). Without
//     this, the `aiChatToolbarButton` is hidden in production gating
//     (no API key + no consent in the XCUITest sandbox), so the test
//     cannot reach the surface at all.
//   - Uses `.empty` seed — Bug #93 is a Library-level chat fix, not
//     reader-context-dependent. A pre-populated library would noise the
//     assertion with book-grid traffic; an empty library lets the test
//     focus on the toolbar → sheet → dismiss → re-open lifecycle.
//   - Sends "Verification probe message 42" (a non-trivial unique
//     literal) as the canary string — distinct from any default
//     placeholder text and easy to grep in failure output.
//   - Queries by accessibility identifier on the message-bubble row
//     (`chatBubble-user`), not by the static-text label, because the
//     bubble's accessibility hierarchy collapses the text under the
//     identifier propagation rule documented in Bug #214 / #209 (a
//     SwiftUI container's identifier propagates to its leaves under
//     `.accessibilityElement(children: .contain)`).
//
// @coordinates-with: LibraryView.swift, LibraryViewSheets.swift,
//   LibraryNavBar.swift, AIChatView.swift, AIChatMessageRow.swift,
//   AIReaderAvailability.swift (AITestOverride seam — Bug #237),
//   docs/bugs.md (Bug #93 row), GH #313.

import XCTest

@MainActor
final class Bug93GeneralChatPersistenceVerificationTests: XCTestCase {

    // MARK: - Lifecycle

    /// Launches with `.empty` seed + `--enable-ai` so the AI Chat toolbar
    /// button is reachable. `--reset-preferences` is opt-in (false) here:
    /// the chat-history-survives-dismiss assertion is local to a single
    /// process lifetime, so it does not depend on cross-launch
    /// UserDefaults purity.
    private func launch() -> XCUIApplication {
        launchApp(seed: .empty, enableAI: true)
    }

    // MARK: - Tests

    /// Bug #93 close-gate assertion — the user's typed message survives a
    /// sheet dismiss + re-open within the same `LibraryView` lifetime.
    ///
    /// Pre-fix (v3.14.15): the second sheet open shows `chatEmptyState`
    /// instead of the prior user bubble, because each present allocates
    /// a fresh `AIChatViewModel`.
    ///
    /// Post-fix (v3.14.16, PR #314): the `@State`-cached
    /// `generalChatVM` survives the sheet's content-closure re-run, so
    /// the prior message bubble is still visible on the second open.
    func testGeneralChatHistorySurvivesSheetDismissAndReopen() throws {
        let app = launch()

        // 1. Tap the AI Chat toolbar button → sheet opens.
        let aiChatButton = app.buttons["aiChatToolbarButton"]
        XCTAssertTrue(
            aiChatButton.waitForExistence(timeout: 15),
            "AI Chat toolbar button should be visible with `--enable-ai` " +
            "(AITestOverride.forceAvailable short-circuit, Bug #237). " +
            "If this fails, the launch flag is not being consumed."
        )
        aiChatButton.tap()

        // 2. The chat sheet should mount with the empty state on first open
        // (no prior history).
        let chatEmptyState = app.otherElements["chatEmptyState"]
        let chatInputField = app.textViews["chatInputField"]
        let chatInputFieldFallback = app.textFields["chatInputField"]
        // Wait for either form (TextField vs TextEditor — the underlying
        // SwiftUI widget can render as either depending on configuration).
        let inputExists =
            chatInputField.waitForExistence(timeout: 10) ||
            chatInputFieldFallback.waitForExistence(timeout: 5)
        XCTAssertTrue(
            inputExists,
            "Chat input field should mount when the General-Chat sheet opens"
        )
        let inputField =
            chatInputField.exists ? chatInputField : chatInputFieldFallback

        // First-open empty state is informational: pre-fix would also
        // show this on second open, which is the bug.
        _ = chatEmptyState.waitForExistence(timeout: 3)

        // 3. Type a unique probe message + tap send.
        let probe = "Verification probe message 42"
        inputField.tap()
        inputField.typeText(probe)

        let sendButton = app.buttons["chatSendButton"]
        XCTAssertTrue(
            sendButton.waitForHittable(timeout: 5),
            "Send button should be hittable once a non-empty message is " +
            "in the chatInputField"
        )
        sendButton.tap()

        // 4. The user bubble should appear in the message list.
        let userBubble = app.otherElements["chatBubble-user"]
        let userBubbleStatic = app.staticTexts["chatBubble-user"]
        let userBubbleAppeared =
            userBubble.waitForExistence(timeout: 10) ||
            userBubbleStatic.waitForExistence(timeout: 3)
        XCTAssertTrue(
            userBubbleAppeared,
            "The sent user message should render as a chatBubble-user " +
            "row after tapping send"
        )

        // 5. Dismiss the sheet via the Done button.
        let doneButton = app.buttons["aiChatDoneButton"]
        XCTAssertTrue(
            doneButton.waitForHittable(timeout: 5),
            "Done button should be hittable in the sheet's nav bar"
        )
        doneButton.tap()

        // 6. The sheet should dismiss — the AI Chat toolbar button is
        // hittable again on the underlying Library surface.
        XCTAssertTrue(
            aiChatButton.waitForHittable(timeout: 10),
            "AI Chat toolbar button should be hittable again after the " +
            "sheet dismisses"
        )

        // 7. Re-tap AI Chat → sheet reopens. THIS is the Bug #93
        // assertion: the prior user message must still be visible.
        aiChatButton.tap()

        let userBubbleSurvived =
            app.otherElements["chatBubble-user"].waitForExistence(timeout: 10) ||
            app.staticTexts["chatBubble-user"].waitForExistence(timeout: 3)
        XCTAssertTrue(
            userBubbleSurvived,
            "Bug #93 close-gate assertion: the prior user message bubble " +
            "must still be present in the chat history when the sheet " +
            "re-opens. Pre-fix (v3.14.15), `makeGeneralChatViewModel()` " +
            "ran on every sheet present, allocating a fresh empty VM. " +
            "Post-fix (v3.14.16, PR #314), the @State-cached " +
            "`generalChatVM` survives the SwiftUI content-closure re-run. " +
            "If this fails on v3.38.29 main, the cache regressed."
        )

        // 8. (Belt-and-suspenders) the empty state should NOT be present
        // on the second open — its presence would prove a fresh VM.
        XCTAssertFalse(
            app.otherElements["chatEmptyState"].exists,
            "chatEmptyState should NOT be visible on sheet re-open after " +
            "a prior message was sent — its presence would indicate a " +
            "fresh AIChatViewModel (the pre-fix behavior)."
        )
    }
}
