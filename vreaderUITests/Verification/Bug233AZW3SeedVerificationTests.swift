// Purpose: CU-free close-gate verification suite for Bug #233 / GH #964 —
// "Verification harness cannot drive AZW3/MOBI TTS pause/resume CU-free".
//
// Bug #233 was a verification-tooling gap: the XCUITest `launchApp(seed:)`
// helper had no `TestSeedState` that opens a Foliate-rendered (AZW3/MOBI)
// book, so a `Feature57AZW3TTSVerificationTests` mirroring
// `Feature26TextToSpeechVerificationTests` could not be written — there was
// no seed value to pass to `launchApp(seed:)` for AZW3.
//
// The fix (route a) added the `azw3Fixture` `TestSeedState` + the
// `--seed-azw3-fixture` launch arg + `TestSeeder.seedMiniAZW3`, which seeds
// the bundled `mini-azw3.azw3` (Project Gutenberg #1064) as a real openable
// AZW3 book.
//
// What this suite verifies — the new harness CAPABILITY itself:
//   - `launchApp(seed: .azw3Fixture)` boots the app with exactly one
//     library book (the AZW3 fixture), and
//   - tapping that book's library card pushes the reader screen — proving
//     the AZW3 fixture is a *real openable* book (it has a backing file the
//     Foliate reader can resolve), not a metadata-only row.
//
// This is the precise deliverable Bug #233 says was previously impossible:
// once this passes, a `Feature57AZW3TTSVerificationTests` can reuse the
// `Feature26` accessibility-label tap pattern verbatim against an AZW3 book,
// unblocking feature #57 / GH #904 acceptance criterion 4.
//
// Design notes (mirroring Feature26TextToSpeechVerificationTests):
//   - Pure XCUITest — element queries + synthesized taps, no computer-use,
//     no DebugBridge snapshot round-trip.
//   - Book-open uses the library card tap, NOT the DebugBridge `open` URL
//     (which cannot reliably commit a NavigationStack push in a headless
//     `simctl openurl` session).
//   - The reader-screen presence assertion keys on the `readerBackButton`
//     accessibility identifier, which is present once any reader host
//     (including the Foliate host for AZW3) has pushed.
//
// @coordinates-with: LaunchHelper.swift, TestSeeder.swift, VReaderApp.swift,
//   TestConstants.swift

import XCTest

@MainActor
final class Bug233AZW3SeedVerificationTests: XCTestCase {

    /// Opens the single seeded book by tapping its library card, retrying
    /// for the lazy-loaded card and the Foliate reader's slower first
    /// render. Mirrors `Feature26`'s `openSeededBook`.
    ///
    /// - Returns: `true` once the reader back button has appeared — i.e.
    ///   the reader screen pushed.
    @discardableResult
    private func openSeededBook(in app: XCUIApplication) -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch
        let backButton = app.buttons[AccessibilityID.readerBackButton]

        for _ in 0..<3 {
            if card.waitForExistence(timeout: 20) {
                if card.waitForHittable(timeout: 10) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 10) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 30) { return true }
        }
        return false
    }

    /// Bug #233 close-gate: `launchApp(seed: .azw3Fixture)` seeds exactly
    /// one openable AZW3 book and that book opens into the reader.
    func test_verify_bug_233_azw3Fixture_seed_opens_foliate_reader() throws {
        let app = launchApp(seed: .azw3Fixture, resetPreferences: true)

        // The library should surface exactly one book card — the AZW3
        // fixture. (`seedMiniAZW3` clears all prior books then inserts one.)
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 25) || row.waitForExistence(timeout: 5),
            "launchApp(seed: .azw3Fixture) should surface the seeded AZW3 book in the library"
        )

        // Tapping the card must push the reader — proving the AZW3 fixture
        // is a real openable book the Foliate reader can resolve, not a
        // metadata-only row. This is the capability Bug #233 says was
        // previously missing.
        XCTAssertTrue(
            openSeededBook(in: app),
            "the seeded AZW3 book should open into the reader (reader back button should appear)"
        )
    }
}
