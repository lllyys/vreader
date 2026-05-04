// Purpose: SwiftUI Environment injection for the live
// `LazyDownloadCoordinator`. Lets `LibraryView` (and the future
// `BookDownloadSheet` in WI-6 part 3) reach the coordinator without
// threading the reference through every parent view.
//
// Feature #47 WI-6 part 2.
//
// @coordinates-with: VReaderApp.swift, LibraryView.swift,
//   LazyDownloadCoordinator.swift

import SwiftUI

private struct LazyDownloadCoordinatorKey: EnvironmentKey {
    static let defaultValue: LazyDownloadCoordinator? = nil
}

extension EnvironmentValues {
    /// The live LazyDownloadCoordinator for this app launch. Nil in
    /// previews and tests that don't inject one — consumers should
    /// treat it as optional.
    var lazyDownloadCoordinator: LazyDownloadCoordinator? {
        get { self[LazyDownloadCoordinatorKey.self] }
        set { self[LazyDownloadCoordinatorKey.self] = newValue }
    }
}
