// Purpose: Pure-function policy for the AIProviderEditSheet kind picker.
// Decides whether a user-visible field should be replaced with the new
// kind's defaults when the kind selection changes. Lives outside the
// SwiftUI view so it can be unit-tested without spinning up a window
// scene.
//
// Feature #50 WI-6b round-2 audit fix [1]: the previous design used a
// transient `isApplyingKindDefaults` flag that depended on SwiftUI's
// `.onChange` callback dispatch ordering. That's brittle — if a future
// SwiftUI runtime delivers field `.onChange` callbacks asynchronously
// or after the kind handler's frame, the flag would already be false
// and the field would be wrongly marked user-edited.
//
// The replacement is purely value-based and order-insensitive: the
// policy compares the current field text against the OLD kind's
// default. Still equal => the user never touched it => replace with the
// new default. Different => the user typed something custom => leave
// it alone.
//
// @coordinates-with: AIProviderEditSheet.swift, ProviderKind.swift

import Foundation

/// Policy decisions for the AIProviderEditSheet's kind picker.
///
/// Round-3 audit note: edit-mode prefill is sticky. The original
/// requirement (preserved here) is that opening an existing profile in
/// the editor treats its current baseURL/model as user intent, even if
/// they happen to equal the defaults — because the user has already
/// "approved" those values once by saving them. Add-mode does not have
/// that signal, so the value-based comparison is the right heuristic
/// there.
enum KindResetPolicy {

    /// True iff the caller should replace the user-visible baseURL text
    /// with the new kind's default.
    /// - In edit mode (`inEditMode == true`): always false. Prefill is
    ///   sticky — the user already committed those values.
    /// - In add mode: true iff the current text still equals the old
    ///   kind's default (user hasn't typed anything custom yet).
    static func shouldReplaceBaseURL(
        current: String,
        oldKind: ProviderKind,
        inEditMode: Bool = false
    ) -> Bool {
        if inEditMode { return false }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == oldKind.defaultBaseURL.absoluteString
    }

    /// True iff the caller should replace the user-visible model text
    /// with the new kind's default. Same edit-mode rule as
    /// `shouldReplaceBaseURL`.
    static func shouldReplaceModel(
        current: String,
        oldKind: ProviderKind,
        inEditMode: Bool = false
    ) -> Bool {
        if inEditMode { return false }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == oldKind.defaultModel
    }
}
