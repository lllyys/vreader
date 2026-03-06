import SwiftUI
import SwiftData

@main
struct VReaderApp: App {
    private let modelContainer: ModelContainer?
    private let initError: String?
    /// Cached content view to avoid recreating the ViewModel on every `body` evaluation.
    private let contentView: ContentView?

    init() {
        do {
            let schema = Schema(SchemaV1.models)
            let config = ModelConfiguration()
            let container = try ModelContainer(
                for: schema,
                migrationPlan: VReaderMigrationPlan.self,
                configurations: [config]
            )
            self.modelContainer = container
            self.initError = nil
            self.contentView = ContentView(
                viewModel: LibraryViewModel(
                    persistence: PersistenceActor(modelContainer: container)
                )
            )
        } catch {
            self.modelContainer = nil
            // Sanitize: don't expose raw file paths or internal details to the user.
            self.initError = Self.sanitizedErrorMessage(error)
            self.contentView = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer, let contentView {
                contentView
                    .modelContainer(modelContainer)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("Unable to Open Library")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(initError ?? "An unexpected error occurred.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Unable to open library. \(initError ?? "An unexpected error occurred.")")
            }
        }
    }

    /// Returns a user-safe error message without exposing internal paths or details.
    private static func sanitizedErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.domain {
        case "NSCocoaErrorDomain" where nsError.code == 134_110:
            return "The library database could not be opened. It may need to be reset."
        default:
            return "The library could not be initialized. Please try restarting the app."
        }
    }
}
