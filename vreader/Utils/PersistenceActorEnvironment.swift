// Purpose: SwiftUI Environment injection for the live PersistenceActor.
// Lets settings sub-screens reach the persistence layer without threading the
// reference through every parent view.
//
// @coordinates-with: VReaderApp.swift, WebDAVSettingsView.swift

import SwiftUI

private struct PersistenceActorKey: EnvironmentKey {
    static let defaultValue: PersistenceActor? = nil
}

extension EnvironmentValues {
    /// The live PersistenceActor for this app launch. Nil in previews and tests
    /// that don't inject one — consumers should treat it as optional.
    var persistenceActor: PersistenceActor? {
        get { self[PersistenceActorKey.self] }
        set { self[PersistenceActorKey.self] = newValue }
    }
}
