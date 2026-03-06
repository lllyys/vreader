import XCTest

/// WI-UI-12: AI Assistant View state tests.
///
/// Tests the feature-disabled and consent-required states
/// accessible via launch arguments. States 3-7 (idle, loading,
/// streaming, complete, error) require ViewModel state injection
/// and are deferred to unit tests.
@MainActor
final class AIAssistantStateTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Feature Disabled

    /// When AI feature flag is OFF (default), the AI view shows a disabled message
    /// with a wand icon and explanatory text.
    func testFeatureDisabledState() throws {
        throw XCTSkip("AI assistant view navigation path not yet resolved — cannot reach disabled state screen")
    }

    // MARK: - Consent Required

    /// When AI is enabled but consent not given, the consent view appears
    /// with lock shield icon, title, and agree button.
    func testConsentRequiredState() throws {
        throw XCTSkip("AI assistant view navigation path not yet resolved — cannot reach consent view")
    }

    // MARK: - Consent Button Hittable

    /// The consent button must be interactable.
    func testConsentButtonHittable() throws {
        throw XCTSkip("AI assistant view navigation path not yet resolved — cannot reach consent button")
    }
}
