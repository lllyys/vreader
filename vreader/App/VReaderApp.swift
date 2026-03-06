import SwiftUI
import SwiftData

@main
struct VReaderApp: App {
    private let modelContainer: ModelContainer?
    private let initError: String?
    /// Cached content view to avoid recreating the ViewModel on every `body` evaluation.
    private let contentView: ContentView?

    #if DEBUG
    /// Parsed launch argument overrides for UI testing.
    private let testConfig: TestLaunchConfig
    #endif

    init() {
        #if DEBUG
        let config = TestLaunchConfig.parse(ProcessInfo.processInfo.arguments)
        self.testConfig = config

        // --seed-corrupt-db: simulate database init failure for error screen tests
        if config.seedCorruptDB {
            self.modelContainer = nil
            self.initError = "The library database could not be opened. It may need to be reset."
            self.contentView = nil
            return
        }
        #endif

        do {
            let schema = Schema(SchemaV1.models)

            #if DEBUG
            // Use in-memory store for UI testing to ensure clean state
            let modelConfig: ModelConfiguration
            if config.isUITesting {
                modelConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                modelConfig = ModelConfiguration()
            }
            #else
            let modelConfig = ModelConfiguration()
            #endif

            let container = try ModelContainer(
                for: schema,
                migrationPlan: VReaderMigrationPlan.self,
                configurations: [modelConfig]
            )
            self.modelContainer = container
            self.initError = nil

            #if DEBUG
            // Seed test data synchronously before creating the ViewModel to avoid race
            // with LibraryView.loadBooks(). In-memory store is fast enough for sync seeding.
            // Uses Task.detached to avoid deadlocking the main thread with semaphore.wait().
            if config.isUITesting {
                let persistence = PersistenceActor(modelContainer: container)
                let seedConfig = config
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    if seedConfig.seedEmpty {
                        await TestSeeder.clearAllBooks(persistence: persistence)
                    } else if seedConfig.seedBooks {
                        await TestSeeder.seedBooks(persistence: persistence)
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
            #endif

            #if DEBUG
            let syncMonitor: SyncStatusMonitor? = config.enableSync ? {
                let monitor = SyncStatusMonitor()
                monitor.update(status: .idle)
                return monitor
            }() : nil
            #else
            let syncMonitor: SyncStatusMonitor? = nil
            #endif

            self.contentView = ContentView(
                viewModel: LibraryViewModel(
                    persistence: PersistenceActor(modelContainer: container)
                ),
                syncMonitor: syncMonitor
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
                #if DEBUG
                contentView
                    .modelContainer(modelContainer)
                    .modifier(TestLaunchModifier(config: testConfig))
                #else
                contentView
                    .modelContainer(modelContainer)
                #endif
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

// MARK: - Test Launch Configuration (DEBUG only)

#if DEBUG

/// Parsed launch argument flags for UI testing.
/// Value type for safe storage in VReaderApp.
struct TestLaunchConfig: Sendable {
    let isUITesting: Bool
    let seedEmpty: Bool
    let seedBooks: Bool
    let seedCorruptDB: Bool
    let colorSchemeOverride: ColorScheme?
    let dynamicTypeOverride: DynamicTypeSize?
    let enableAI: Bool
    let enableSync: Bool
    let reduceMotion: Bool

    /// Parses launch arguments into a typed config.
    /// Unknown flags are silently ignored.
    static func parse(_ arguments: [String]) -> TestLaunchConfig {
        let args = Set(arguments)

        let colorScheme: ColorScheme?
        if args.contains("--force-dark") {
            colorScheme = .dark
        } else if args.contains("--force-light") {
            colorScheme = .light
        } else {
            colorScheme = nil
        }

        let dynamicType: DynamicTypeSize?
        if args.contains("--dynamic-type-XS") {
            dynamicType = .xSmall
        } else if args.contains("--dynamic-type-XXXL") {
            dynamicType = .xxxLarge
        } else if args.contains("--dynamic-type-AX5") {
            dynamicType = .accessibility5
        } else {
            dynamicType = nil
        }

        return TestLaunchConfig(
            isUITesting: args.contains("--uitesting"),
            seedEmpty: args.contains("--seed-empty"),
            seedBooks: args.contains("--seed-books"),
            seedCorruptDB: args.contains("--seed-corrupt-db"),
            colorSchemeOverride: colorScheme,
            dynamicTypeOverride: dynamicType,
            enableAI: args.contains("--enable-ai"),
            enableSync: args.contains("--enable-sync"),
            reduceMotion: args.contains("--reduce-motion")
        )
    }

    /// A no-op config for non-test launches.
    static let none = TestLaunchConfig(
        isUITesting: false,
        seedEmpty: false,
        seedBooks: false,
        seedCorruptDB: false,
        colorSchemeOverride: nil,
        dynamicTypeOverride: nil,
        enableAI: false,
        enableSync: false,
        reduceMotion: false
    )
}

/// Applies test launch overrides as SwiftUI modifiers.
struct TestLaunchModifier: ViewModifier {
    let config: TestLaunchConfig

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(config.colorSchemeOverride)
            .ifLet(config.dynamicTypeOverride) { view, size in
                view.dynamicTypeSize(size)
            }
            .transaction { transaction in
                if config.reduceMotion {
                    transaction.animation = nil
                }
            }
    }
}

/// Conditional modifier helper for optional values.
private extension View {
    @ViewBuilder
    func ifLet<T, Modified: View>(
        _ value: T?,
        @ViewBuilder transform: (Self, T) -> Modified
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

#endif
