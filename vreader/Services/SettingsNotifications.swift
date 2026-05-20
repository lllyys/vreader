// Purpose: Feature #67 WI-4 — Settings-sheet cross-component notification
// names. Holds `openReadingStatsRequested`, the Stats hand-off
// `SettingsView` posts when the user taps the profile card's Stats pill.
//
// Lives outside `ReaderNotifications.swift` because that file is
// documented as reader-bridge/container coordination only; the Settings
// → dashboard hand-off is an app-shell-level signal, not a reader
// signal. Following the established `vreader.<scope>.<event>`
// namespacing convention (`docs/architecture.md` Notification Bus).
//
// @coordinates-with: SettingsView.swift, SettingsProfileCard.swift,
//   ReadingDashboardView.swift,
//   `docs/architecture.md` Notification Bus table

import Foundation

extension Notification.Name {

    /// Posted by `SettingsView` when the user taps the profile-card's
    /// Stats pill. The Settings sheet is itself the natural observer
    /// (it presents `ReadingDashboardView` as an in-sheet sheet), but
    /// the notification is the documented cross-component hand-off
    /// (no `userInfo` payload — the observer just presents its surface).
    static let openReadingStatsRequested = Notification.Name(
        "vreader.settings.openReadingStatsRequested"
    )
}
