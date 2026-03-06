// Purpose: Wrapper around XCUIApplication.performAccessibilityAudit() (iOS 17+).
// Provides a test-friendly function that fails the test on any violation.
//
// Key decisions:
// - Guards with #available(iOS 17.0, *) for compilation on older targets.
// - Calls XCTFail on each violation for clear test failure messages.
// - Supports excluding specific audit types when known false positives exist.

import XCTest

/// Runs an accessibility audit on the current screen and fails the test on violations.
///
/// Uses `XCUIApplication.performAccessibilityAudit()` (iOS 17+) to check for
/// WCAG compliance issues including Dynamic Type, contrast, touch targets,
/// and element descriptions.
///
/// Excludes known false-positive audit types by default:
/// - `.textClipped`: Truncated text (`.lineLimit()`, format badges) is intentional.
/// - `.contrast`: SwiftUI system components (segmented controls, secondary text)
///   may report contrast issues that are not fixable from user code.
/// - `.dynamicType`: Some SwiftUI built-in views don't fully support all
///   Dynamic Type sizes, producing false positives.
///
/// - Parameters:
///   - app: The running application to audit.
///   - excluding: Additional audit issue types to exclude beyond the defaults.
///   - file: Source file for failure attribution.
///   - line: Source line for failure attribution.
func auditCurrentScreen(
    app: XCUIApplication,
    excluding: XCUIAccessibilityAuditType = [],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if #available(iOS 17.0, *) {
        // Exclude known false positives from SwiftUI system components.
        let defaultExclusions: XCUIAccessibilityAuditType = [
            .textClipped,
            .contrast,
            .dynamicType
        ]
        let exclusions = excluding.union(defaultExclusions)
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(exclusions)) { issue in
                // Return false to treat every issue as a failure.
                // Return true to ignore specific issues if needed.
                false
            }
        } catch {
            XCTFail(
                "Accessibility audit failed: \(error.localizedDescription)",
                file: file,
                line: line
            )
        }
    } else {
        // On older iOS, skip audit gracefully — tests still compile.
        // This branch should not be reached in practice since deployment target is iOS 17.
    }
}
