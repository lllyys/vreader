// Purpose: SwiftUI Environment injection for the live
// `WebDAVNetworkPolicy`. Lets `LibraryView` (for Wi-Fi-aware enqueue)
// and `WebDAVSettingsView` (for the toggle UI in WI-6 part 3) reach
// the policy without threading the reference through every parent.
//
// Feature #47 WI-6 part 2.
//
// @coordinates-with: VReaderApp.swift, WebDAVNetworkPolicy.swift,
//   WebDAVSettingsView.swift, LibraryView.swift

import SwiftUI

private struct WebDAVNetworkPolicyKey: EnvironmentKey {
    static let defaultValue: WebDAVNetworkPolicy? = nil
}

extension EnvironmentValues {
    /// The live WebDAVNetworkPolicy for this app launch. Nil in
    /// previews and tests that don't inject one — consumers should
    /// treat it as optional.
    var webDAVNetworkPolicy: WebDAVNetworkPolicy? {
        get { self[WebDAVNetworkPolicyKey.self] }
        set { self[WebDAVNetworkPolicyKey.self] = newValue }
    }
}
