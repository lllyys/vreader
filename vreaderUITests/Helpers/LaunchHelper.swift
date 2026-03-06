// Purpose: Configurable app launch helper for XCUITest.
// Provides typed API for seed state, color scheme, dynamic type, and feature flags.
// Includes XCUIElement wait extensions for anti-flake compliance.
//
// Key decisions:
// - Launch arguments map to the flags defined in WI-UI-0 (VReaderApp).
// - Wait extensions use NSPredicate expectations, never Thread.sleep().
// - Default timeout is 5 seconds for existence, 5 seconds for hittable.
//
// @coordinates-with: VReaderApp.swift (launch argument handling)

import XCTest

// MARK: - Seed State

/// Database seed state for test launches.
enum TestSeedState {
    /// Empty database (no books).
    case empty
    /// Pre-populated with fixture books.
    case books
    /// Corrupted database (triggers init error screen).
    case corruptDB

    /// Launch argument flag.
    var launchArgument: String {
        switch self {
        case .empty: return "--seed-empty"
        case .books: return "--seed-books"
        case .corruptDB: return "--seed-corrupt-db"
        }
    }
}

// MARK: - Color Scheme

/// Color scheme override for test launches.
enum TestColorScheme {
    /// Light mode.
    case light
    /// Dark mode.
    case dark
    /// System default (no override).
    case system

    /// Launch argument flag, or nil for system default.
    var launchArgument: String? {
        switch self {
        case .light: return "--force-light"
        case .dark: return "--force-dark"
        case .system: return nil
        }
    }
}

// MARK: - Dynamic Type

/// Dynamic Type size override for test launches.
enum TestDynamicType {
    /// Extra small text.
    case xSmall
    /// System default (no override).
    case `default`
    /// Triple extra large text.
    case xxxLarge
    /// Largest accessibility size (accessibilityExtraExtraExtraLarge).
    case ax5

    /// Launch argument flag, or nil for default.
    var launchArgument: String? {
        switch self {
        case .xSmall: return "--dynamic-type-XS"
        case .default: return nil
        case .xxxLarge: return "--dynamic-type-XXXL"
        case .ax5: return "--dynamic-type-AX5"
        }
    }
}

// MARK: - Launch Helper

/// Namespace for app launch utilities.
/// Callers can use either `LaunchHelper.launchApp()` or the free `launchApp()` function.
enum LaunchHelper {
    /// Launches the app with configurable test arguments.
    @discardableResult
    static func launchApp(
        seed: TestSeedState = .books,
        colorScheme: TestColorScheme = .system,
        dynamicType: TestDynamicType = .default,
        enableAI: Bool = false,
        enableSync: Bool = false,
        reduceMotion: Bool = false
    ) -> XCUIApplication {
        vreaderUITests_launchApp(
            seed: seed,
            colorScheme: colorScheme,
            dynamicType: dynamicType,
            enableAI: enableAI,
            enableSync: enableSync,
            reduceMotion: reduceMotion
        )
    }
}

/// Launches the app with configurable test arguments.
///
/// - Parameters:
///   - seed: Database seed state (default: `.books`).
///   - colorScheme: Color scheme override (default: `.system`).
///   - dynamicType: Dynamic Type size override (default: `.default`).
///   - enableAI: Whether to enable AI feature flag (default: `false`).
///   - enableSync: Whether to enable sync feature flag (default: `false`).
///   - reduceMotion: Whether to simulate reduce motion (default: `false`).
/// - Returns: The launched `XCUIApplication` instance.
@discardableResult
func vreaderUITests_launchApp(
    seed: TestSeedState = .books,
    colorScheme: TestColorScheme = .system,
    dynamicType: TestDynamicType = .default,
    enableAI: Bool = false,
    enableSync: Bool = false,
    reduceMotion: Bool = false
) -> XCUIApplication {
    let app = XCUIApplication()

    var args: [String] = ["--uitesting"]
    args.append(seed.launchArgument)

    if let colorArg = colorScheme.launchArgument {
        args.append(colorArg)
    }

    if let typeArg = dynamicType.launchArgument {
        args.append(typeArg)
    }

    if enableAI {
        args.append("--enable-ai")
    }

    if enableSync {
        args.append("--enable-sync")
    }

    if reduceMotion {
        args.append("--reduce-motion")
    }

    app.launchArguments = args
    app.launch()

    return app
}

/// Convenience alias — use `launchApp()` or `LaunchHelper.launchApp()` interchangeably.
@discardableResult
func launchApp(
    seed: TestSeedState = .books,
    colorScheme: TestColorScheme = .system,
    dynamicType: TestDynamicType = .default,
    enableAI: Bool = false,
    enableSync: Bool = false,
    reduceMotion: Bool = false
) -> XCUIApplication {
    vreaderUITests_launchApp(
        seed: seed,
        colorScheme: colorScheme,
        dynamicType: dynamicType,
        enableAI: enableAI,
        enableSync: enableSync,
        reduceMotion: reduceMotion
    )
}

// MARK: - Book Navigation Helpers

/// Taps a book in the library by title, independent of grid/list mode.
/// Scrolls down if the book is not initially visible (LazyVGrid only loads visible elements).
@MainActor
func tapBook(titled title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let predicate = NSPredicate(format: "label CONTAINS[cd] %@", title)
    let scrollTarget = app.scrollViews.firstMatch

    // Try up to 6 scroll attempts for lazy-loaded elements
    for _ in 0..<6 {
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists {
            button.tap()
            return
        }
        // Scroll down to load more elements
        if scrollTarget.exists {
            scrollTarget.swipeUp()
        } else {
            app.swipeUp()
        }
    }

    XCTFail("Could not find book '\(title)' in library", file: file, line: line)
}

/// Taps the first available book in the library, independent of grid/list mode.
@MainActor
func tapFirstBook(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    // Grid mode: buttons with bookCard_ prefix
    let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
    let card = app.buttons.matching(cardPredicate).firstMatch
    if card.waitForExistence(timeout: 5) {
        card.tap()
        return
    }
    // List mode: buttons with bookRow_ prefix
    let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
    let row = app.buttons.matching(rowPredicate).firstMatch
    if row.waitForExistence(timeout: 3) {
        row.tap()
        return
    }
    // Last resort: cells
    let cell = app.cells.firstMatch
    if cell.waitForExistence(timeout: 3) {
        cell.tap()
        return
    }
    XCTFail("Could not find any book in library", file: file, line: line)
}

// MARK: - XCUIElement Wait Extensions

extension XCUIElement {
    /// Waits for the element to become hittable (exists, visible, and enabled).
    ///
    /// Uses NSPredicate expectation instead of sleep for anti-flake compliance.
    ///
    /// - Parameter timeout: Maximum time to wait in seconds (default: 5).
    /// - Returns: `true` if the element became hittable within the timeout.
    func waitForHittable(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the element to no longer exist.
    ///
    /// Useful for verifying dismissal of alerts, sheets, and overlays.
    ///
    /// - Parameter timeout: Maximum time to wait in seconds (default: 5).
    /// - Returns: `true` if the element disappeared within the timeout.
    func waitForDisappearance(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
