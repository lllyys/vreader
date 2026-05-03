// Purpose: SwiftUI Environment injection for the live BookImporter so feature
// #46's WebDAVSettingsView can pass it to WebDAVProviderFactory without
// threading the reference through every parent view.
//
// @coordinates-with: VReaderApp.swift, WebDAVSettingsView.swift,
//   PersistenceActorEnvironment.swift, BookImporting.swift

import SwiftUI

private struct BookImporterKey: EnvironmentKey {
    static let defaultValue: (any BookImporting)? = nil
}

extension EnvironmentValues {
    /// The live BookImporter for this app launch. Nil in previews and tests
    /// that don't inject one — consumers should treat it as optional. When
    /// nil, feature #46's materializing restore falls back to v1-format
    /// behavior (metadata-only, books skipped).
    var bookImporter: (any BookImporting)? {
        get { self[BookImporterKey.self] }
        set { self[BookImporterKey.self] = newValue }
    }
}
