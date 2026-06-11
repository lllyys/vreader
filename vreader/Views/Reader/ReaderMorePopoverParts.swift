// Purpose: Feature #60 WI-6c / Feature #56 WI-8 — supporting parts
// for the reader More-menu popover: the inline toggle switch rendered
// in the toggle rows (Auto-turn, Bilingual off/on), and the
// `ReaderMoreMenuActionObservers` modifier that bundles every
// More-menu notification observer for the host. Split out of
// `ReaderMorePopover.swift` to keep both files under the ~300-line
// guideline.
//
// @coordinates-with: ReaderMorePopover.swift, ReaderMoreMenuRow.swift,
//   ReaderThemeV2.swift, ReaderContainerView+Sheets.swift,
//   ReaderNotifications.swift

#if canImport(UIKit)
import SwiftUI

// MARK: - Inline toggle switch

/// Small iOS-style toggle rendered in the Auto-turn row, matching
/// `vreader-more.jsx`'s `ToggleSwitch` (34×20 track, green `#3a6a5a`
/// when on). Presentational only — the row's tap posts the toggle
/// notification; the host flips the backing setting and the new
/// `isOn` flows back in.
struct ReaderMoreToggle: View {
    let isOn: Bool
    let theme: ReaderThemeV2

    var body: some View {
        Capsule()
            .fill(trackColor)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .accessibilityHidden(true)
    }

    private var trackColor: Color {
        isOn
            ? Color(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255)
            : (theme.isDark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.12))
    }
}

// MARK: - More-menu action observers

/// Feature #60 WI-6c / Feature #56 WI-8: bundles every More-menu
/// notification observer into a single modifier, mirroring
/// `ReaderToolbarActionObservers` (WI-6b). `ReaderContainerView`
/// applies it as one `.modifier(...)` rather than chained
/// `.onReceive`s — its `body` is already near the Swift type-checker's
/// expression-complexity ceiling.
///
/// Each observer maps its notification back to the `ReaderMoreMenuRow`
/// that posted it via `ReaderMoreMenuRow(notification:)` (the inverse
/// of `.notification`) and hands the row to a single
/// `(ReaderMoreMenuRow) -> Void` callback, so the host has one action
/// funnel for the entire row set. WI-8 adds the bilingual +
/// re-translate-chapter observers so the new rows route through the
/// same funnel as the legacy five.
struct ReaderMoreMenuActionObservers: ViewModifier {
    let onAction: (ReaderMoreMenuRow) -> Void

    func body(content: Content) -> some View {
        // SwiftUI `.onReceive` needs one publisher per concrete name —
        // a dynamic set can't be observed — but each routes through the
        // inverse initializer so the row resolution is single-sourced
        // and round-trip-tested.
        content
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreReadAloud), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreToggleAutoTurn), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreBilingual), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreTranslationSettings), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreReTranslateChapter), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreBookDetails), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreShareBook), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreExportAnnotations), perform: dispatch)
    }

    /// Resolves the posting row from the notification name and fires
    /// the action funnel. An unrecognised name (no matching row) is
    /// ignored.
    private func dispatch(_ notification: Notification) {
        guard let row = ReaderMoreMenuRow(notification: notification.name) else { return }
        onAction(row)
    }
}

extension View {
    /// Attaches the More-menu action observers (Feature #60 WI-6c /
    /// Feature #56 WI-8). See `ReaderMoreMenuActionObservers`.
    func readerMoreMenuActionObservers(
        onAction: @escaping (ReaderMoreMenuRow) -> Void
    ) -> some View {
        modifier(ReaderMoreMenuActionObservers(onAction: onAction))
    }
}
#endif
