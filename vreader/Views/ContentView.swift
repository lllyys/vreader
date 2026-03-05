import SwiftUI

struct ContentView: View {
    let viewModel: LibraryViewModel

    var body: some View {
        LibraryView(viewModel: viewModel)
            .accessibilityIdentifier("libraryView")
    }
}
