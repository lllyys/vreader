// Purpose: Dictionary lookup and word extraction for Define/Translate-on-Select.
// Provides system dictionary integration via UIReferenceLibraryViewController
// and word extraction from text selections.
//
// Key decisions:
// - enum namespace (no instances needed — all static).
// - extractWord splits on whitespace and returns the first non-empty token.
// - canLookUp wraps UIReferenceLibraryViewController.dictionaryHasDefinition.
// - Menu title constants for consistency across bridges.
// - The two UIKit-touching members (`canLookUp`, `viewController(for:)`) are
//   `@MainActor`: `UIReferenceLibraryViewController` is a `UIViewController`
//   subclass, and both constructing it and calling `dictionaryHasDefinition`
//   are main-thread-only UIKit APIs. Isolating them makes any off-main call a
//   compile error rather than a runtime crash — bug #221 was a flaky test-host
//   crash caused by `viewController(for:)` running on a background cooperative
//   thread under Swift Testing's parallel scheduler. `extractWord` and the
//   menu-title constants stay non-isolated — they touch no UIKit.
//
// @coordinates-with TXTBridgeShared.swift, ReaderNotifications.swift

#if canImport(UIKit)
import UIKit

/// Dictionary lookup utilities for Define/Translate on text selection.
enum DictionaryLookup {

    /// Menu title for the "Define" action in the edit menu.
    static let defineMenuTitle = "Define"

    /// Menu title for the "Translate" action in the edit menu.
    static let translateMenuTitle = "Translate"

    /// Check if the system dictionary can define a word.
    ///
    /// `@MainActor`: `UIReferenceLibraryViewController.dictionaryHasDefinition`
    /// is a UIKit main-thread-only API.
    ///
    /// - Parameter word: The word to look up.
    /// - Returns: `true` if a definition is available, `false` otherwise.
    @MainActor
    static func canLookUp(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        return UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word)
    }

    /// Create a system dictionary view controller for a word.
    ///
    /// `@MainActor`: constructs a `UIReferenceLibraryViewController`
    /// (`UIViewController` subclass) — UIKit view-controller initialisers must
    /// run on the main thread.
    ///
    /// - Parameter word: The word to define.
    /// - Returns: A `UIReferenceLibraryViewController` displaying the definition.
    @MainActor
    static func viewController(for word: String) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: word)
    }

    /// Extract a single word from selected text for dictionary lookup.
    ///
    /// Trims whitespace/newlines, then returns the first whitespace-delimited token.
    /// Returns `nil` if the selection is empty or whitespace-only.
    ///
    /// - Parameter selection: The selected text string.
    /// - Returns: The first word, or `nil` if no word can be extracted.
    static func extractWord(from selection: String) -> String? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Split on all whitespace characters (spaces, tabs, newlines)
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .first { !$0.isEmpty }
    }
}
#endif
