// Purpose: Feature #60 WI-6b — bundles the four bottom-chrome toolbar
// notification observers into a single modifier. `ReaderContainerView`
// applies it as one `.modifier(...)` rather than four chained
// `.onReceive`s — its `body` is already near the Swift type-checker's
// expression-complexity ceiling, and four more chain links tipped it
// over ("unable to type-check in reasonable time"). Split out of
// ReaderBottomChrome.swift for the ~300-line file budget (feature #101
// Gate-4 r1).
//
// @coordinates-with: ReaderBottomChrome.swift, ReaderNotifications.swift,
//   ReaderContainerView.swift

import SwiftUI

/// Feature #60 WI-6b: the four bottom-chrome toolbar notification
/// observers as one modifier. See the file header for why this is not
/// four chained `.onReceive`s at the call site.
struct ReaderToolbarActionObservers: ViewModifier {
    let onContents: () -> Void
    let onNotes: () -> Void
    let onDisplay: () -> Void
    let onAI: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenContents)) { _ in
                onContents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenNotes)) { _ in
                onNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenDisplay)) { _ in
                onDisplay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenAI)) { _ in
                onAI()
            }
    }
}

extension View {
    /// Attaches the four bottom-chrome toolbar observers (Feature #60
    /// WI-6b). See `ReaderToolbarActionObservers`.
    func readerToolbarActionObservers(
        onContents: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onDisplay: @escaping () -> Void,
        onAI: @escaping () -> Void
    ) -> some View {
        modifier(ReaderToolbarActionObservers(
            onContents: onContents,
            onNotes: onNotes,
            onDisplay: onDisplay,
            onAI: onAI
        ))
    }
}
