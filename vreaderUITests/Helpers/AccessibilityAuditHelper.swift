// Purpose: Wrapper around XCUIApplication.performAccessibilityAudit() (iOS 17+).
// Provides a test-friendly function that fails the test on any violation.
//
// Key decisions:
// - Guards with #available(iOS 17.0, *) for compilation on older targets.
// - Calls XCTFail on each violation for clear test failure messages.
// - Supports excluding specific audit types when known false positives exist.
// - `ignoringKeyboardElements` skips issues whose offending element lives
//   inside the system software keyboard (e.g. `TUIPredictionViewCell`,
//   "missing useful accessibility information") — those are Apple
//   keyboard-internal gaps, not app-fixable. Screens that auto-focus a
//   text field raise the keyboard, so its predictive-text bar lands in
//   the whole-app audit scope; this flag keeps the audit honest for the
//   app's own UI without being held hostage to system keyboard chrome.

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
///   - ignoringKeyboardElements: When `true`, issues whose offending
///     element lies in the system software keyboard's chrome (keys or the
///     QuickType / predictive-text bar) are ignored. Use on screens that
///     auto-focus a text field, where the raised keyboard would otherwise
///     contaminate the whole-app audit with Apple keyboard-internal gaps.
///   - file: Source file for failure attribution.
///   - line: Source line for failure attribution.
func auditCurrentScreen(
    app: XCUIApplication,
    excluding: XCUIAccessibilityAuditType = [],
    ignoringKeyboardElements: Bool = false,
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
        // The system software keyboard's frame — issues whose offending
        // element falls in the keyboard's vertical band are Apple
        // keyboard-internal gaps, not app-fixable. Resolved once so the
        // per-issue handler is cheap. The band test (rather than strict
        // containment) is required because the QuickType / predictive-
        // text bar (`TUIPredictionViewCell`) sits flush *above* the
        // keys, just outside `app.keyboards`' own frame.
        let keyboardFrame: CGRect? = ignoringKeyboardElements
            ? (app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame : nil)
            : nil
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(exclusions)) { issue in
                // Return false to treat the issue as a failure.
                // Return true to ignore it.
                if let keyboardFrame, let elementFrame = issue.element?.frame,
                   !elementFrame.isEmpty,
                   isSystemKeyboardChrome(elementFrame, keyboardFrame: keyboardFrame) {
                    return true
                }
                return false
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

/// True when `elementFrame` belongs to the system software keyboard's
/// chrome — the keys themselves or the QuickType / predictive-text bar
/// flush above them.
///
/// `app.keyboards.firstMatch.frame` covers only the key area; the
/// predictive-text bar (`TUIPredictionViewCell`) renders in its own
/// strip directly above. Strict containment therefore misses it. This
/// uses a vertical-band test: the element is keyboard chrome when its
/// bottom edge is at or below the keyboard's top edge (so the element
/// is inside the keyboard, or in the strip touching its top) and it
/// stays within the keyboard's horizontal span. App UI on a focused
/// search/text screen sits well above the keyboard, so it is never
/// matched.
private func isSystemKeyboardChrome(_ elementFrame: CGRect, keyboardFrame: CGRect) -> Bool {
    // Direct containment — keys, glyphs, accessory cells inside the keyboard.
    if keyboardFrame.contains(elementFrame) { return true }
    // QuickType strip: bottom edge at/below the keyboard top, within its
    // horizontal span, and not extending above a plausible strip height.
    let predictiveBarMaxHeight: CGFloat = 60
    let touchesKeyboardTop = elementFrame.maxY >= keyboardFrame.minY
        && elementFrame.maxY <= keyboardFrame.maxY
    let withinKeyboardColumns = elementFrame.minX >= keyboardFrame.minX
        && elementFrame.maxX <= keyboardFrame.maxX
    let withinStripHeight = elementFrame.minY >= keyboardFrame.minY - predictiveBarMaxHeight
    return touchesKeyboardTop && withinKeyboardColumns && withinStripHeight
}
