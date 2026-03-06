import SwiftUI

struct ContentView: View {
    let viewModel: LibraryViewModel
    var syncMonitor: SyncStatusMonitor?

    var body: some View {
        LibraryView(viewModel: viewModel, syncMonitor: syncMonitor)
            .accessibilityIdentifier("libraryView")
    }
}
