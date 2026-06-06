// Purpose: Bug #325 repro — the Foliate windowed scroller sticks at a
// heading-only divider section shorter than the viewport (`#ensureWindow`
// can't advance `#index` past it, so the next content section never mounts).
//
// Seeds the synthetic divider AZW3 (PART ONE → Content One → PART TWO →
// Content Two) native-to-Foliate in scroll mode, swipes down past the tall
// Content One into the short "PART TWO" divider, and checks whether Content
// Two becomes reachable. If it sticks, "Content Two" never appears.

import XCTest

final class Bug325DividerScrollVerificationTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testWindowedScrollAdvancesPastShortDivider() throws {
        let app = LaunchHelper.launchApp(
            seed: .dividerAZW3,
            extraLaunchArguments: ["--reader-default-layout=scroll"]
        )

        // Open the seeded AZW3.
        let bookCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'bookCard_'"))
            .firstMatch
        XCTAssertTrue(bookCard.waitForExistence(timeout: 20), "Divider AZW3 card should appear")
        bookCard.tap()

        // Let the Foliate reader settle.
        sleep(4)
        let beforeShot = XCTAttachment(screenshot: app.screenshot())
        beforeShot.name = "01-opened"; beforeShot.lifetime = .keepAlways
        add(beforeShot)

        // Scroll DOWN through tall Content One into the short PART TWO divider.
        for _ in 0..<14 {
            app.swipeUp(velocity: .fast)
        }
        sleep(2)
        let afterShot = XCTAttachment(screenshot: app.screenshot())
        afterShot.name = "02-after-scroll-to-divider"; afterShot.lifetime = .keepAlways
        add(afterShot)

        // If the windowed scroller advanced past the short divider, Content Two's
        // text becomes reachable; if it sticks, it never mounts. "Content Two"
        // appears as a heading in the second content section.
        let contentTwo = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Content Two'")
        ).firstMatch
        let reached = contentTwo.waitForExistence(timeout: 10)
        // Record the observed outcome as the assertion (RED if it sticks).
        XCTAssertTrue(
            reached,
            "BUG #325: scrolling past the short 'PART TWO' divider should mount Content Two; "
            + "if this fails, the windowed scroller stuck at the sub-viewport divider."
        )
    }
}
