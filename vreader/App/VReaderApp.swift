import SwiftUI
import SwiftData

@main
@MainActor
struct VReaderApp: App {
    /// Captures `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
    /// so the lazy-download coordinator can invoke the handler when its
    /// background URLSession finishes delivering queued events.
    /// SwiftUI's App lifecycle doesn't expose this hook directly.
    /// Feature #47 WI-3b.
    @UIApplicationDelegateAdaptor(VReaderAppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer?
    private let initError: String?
    /// Cached content view to avoid recreating the ViewModel on every `body` evaluation.
    private let contentView: ContentView?
    /// App configuration resolved from build settings.
    private let appConfig: AppConfiguration
    /// Live PersistenceActor — exposed via SwiftUI Environment for sub-screens
    /// (e.g. WebDAVSettingsView) that need direct access without protocol wrapping.
    private let persistenceActor: PersistenceActor?

    /// Live BookImporter — exposed via SwiftUI Environment for feature #46's
    /// WebDAV materializing restore (`WebDAVSettingsView` passes it through to
    /// `WebDAVProviderFactory.make`). Nil if the SwiftData container failed
    /// to construct.
    private let bookImporterRef: (any BookImporting)?

    /// Live LazyDownloadCoordinator (#47) — exposed via SwiftUI Environment
    /// so library rows + the future BookDownloadSheet can call enqueue when
    /// the user taps a `.remoteOnly` row. Constructed alongside the
    /// persistence actor so it can run reattach + reconcile at boot.
    /// `@MainActor`-isolated; safe to read in any view body.
    @MainActor private let lazyDownloadCoordinator: LazyDownloadCoordinator?

    /// Live WebDAVNetworkPolicy (#47) — exposed via SwiftUI Environment so
    /// the WebDAV settings UI's Wi-Fi-only toggle round-trips through one
    /// shared instance and the lazy-download enqueue path consults the
    /// same policy state the user toggled.
    @MainActor private let webDAVNetworkPolicy: WebDAVNetworkPolicy?

    #if DEBUG
    /// Parsed launch argument overrides for UI testing.
    private let testConfig: TestLaunchConfig
    /// DebugBridge for the vreader-debug:// URL scheme. Set synchronously
    /// in `init()` so .onOpenURL can dispatch to it without a swap race.
    /// Optional because init can fail (corrupt DB path) before the bridge
    /// is built; in that case the URL handler no-ops.
    private let debugBridge: DebugBridge?
    #endif

    init() {
        let resolvedConfig = AppConfiguration()
        self.appConfig = resolvedConfig
        FeatureFlags.shared.configure(environment: resolvedConfig.environment)

        #if DEBUG
        let config = TestLaunchConfig.parse(ProcessInfo.processInfo.arguments)
        self.testConfig = config

        // --seed-corrupt-db: simulate database init failure for error screen tests
        if config.seedCorruptDB {
            self.modelContainer = nil
            self.initError = "The library database could not be opened. It may need to be reset."
            self.contentView = nil
            self.persistenceActor = nil
            self.bookImporterRef = nil
            self.lazyDownloadCoordinator = nil
            self.webDAVNetworkPolicy = nil
            self.debugBridge = nil
            return
        }
        #endif

        do {
            let schema = Schema(SchemaV6.models)

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
            // Seed test data before creating the ViewModel to avoid race with LibraryView.loadBooks().
            // Uses Task.detached + semaphore to block init until seeding completes.
            // Bounded timeout prevents indefinite hang if seeding fails.
            if config.isUITesting {
                let persistence = PersistenceActor(modelContainer: container)
                let seedConfig = config
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    if seedConfig.seedEmpty {
                        await TestSeeder.clearAllBooks(persistence: persistence)
                    } else if seedConfig.seedPositionTest {
                        await TestSeeder.seedPositionTest(persistence: persistence)
                    } else if seedConfig.seedBooks {
                        await TestSeeder.seedBooks(persistence: persistence)
                    }
                    semaphore.signal()
                }
                let waitResult = semaphore.wait(timeout: .now() + 5.0)
                if waitResult == .timedOut {
                    assertionFailure("Test seeding timed out after 5 seconds")
                }
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

            let persistence = PersistenceActor(modelContainer: container)
            let booksDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImportedBooks", isDirectory: true)
            let importer = BookImporter(
                persistence: persistence,
                sandboxBooksDirectory: booksDir
            )

            self.contentView = ContentView(
                viewModel: LibraryViewModel(
                    persistence: persistence,
                    importer: importer,
                    preferenceStore: UserDefaultsPreferenceStore()
                ),
                syncMonitor: syncMonitor
            )
            self.persistenceActor = persistence
            self.bookImporterRef = importer

            // Feature #47: construct the policy + lazy-download
            // coordinator alongside the persistence actor so reattach
            // + reconcile run at boot. MainActor.assumeIsolated is
            // safe because @MainActor on the App struct guarantees
            // init() runs on main.
            self.webDAVNetworkPolicy = MainActor.assumeIsolated {
                WebDAVNetworkPolicy()
            }
            // Hold the delegate locally so we can wire its weak
            // back-pointer to the coordinator after both are
            // constructed. URLSession retains the delegate, so
            // dropping our reference here is fine — the back-pointer
            // is what makes delegate events observable.
            let lazyDelegate = LazyDownloadDelegate()
            let backgroundSession = URLSessionBackgroundSession(
                identifier: "com.vreader.app.book-downloads",
                delegate: lazyDelegate
            )
            self.lazyDownloadCoordinator = MainActor.assumeIsolated {
                let coord = LazyDownloadCoordinator(
                    session: backgroundSession,
                    persistence: persistence
                )
                lazyDelegate.coordinator = coord
                return coord
            }

            #if DEBUG
            // Build the DebugBridge synchronously. The struct is
            // @MainActor-isolated, so init() runs on the main actor and
            // we can construct the @MainActor DebugBridge directly with
            // no isolation gymnastics.
            self.debugBridge = DebugBridge(
                context: RealDebugBridgeContext(
                    persistence: persistence,
                    importer: importer
                )
            )
            #endif
        } catch {
            self.modelContainer = nil
            // Sanitize: don't expose raw file paths or internal details to the user.
            self.initError = Self.sanitizedErrorMessage(error)
            self.contentView = nil
            self.persistenceActor = nil
            self.bookImporterRef = nil
            self.lazyDownloadCoordinator = nil
            self.webDAVNetworkPolicy = nil
            #if DEBUG
            self.debugBridge = nil
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer, let contentView {
                #if DEBUG
                contentView
                    .modelContainer(modelContainer)
                    .environment(\.persistenceActor, persistenceActor)
                    .environment(\.bookImporter, bookImporterRef)
                    .environment(\.lazyDownloadCoordinator, lazyDownloadCoordinator)
                    .environment(\.webDAVNetworkPolicy, webDAVNetworkPolicy)
                    .modifier(TestLaunchModifier(config: testConfig))
                    .onOpenURL { [debugBridge] url in
                        guard url.scheme == DebugCommand.scheme else { return }
                        guard let debugBridge else { return }
                        Task { @MainActor in
                            await debugBridge.handle(url)
                        }
                    }
                #else
                contentView
                    .modelContainer(modelContainer)
                    .environment(\.persistenceActor, persistenceActor)
                    .environment(\.bookImporter, bookImporterRef)
                    .environment(\.lazyDownloadCoordinator, lazyDownloadCoordinator)
                    .environment(\.webDAVNetworkPolicy, webDAVNetworkPolicy)
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
    let seedPositionTest: Bool
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
            seedPositionTest: args.contains("--seed-position-test"),
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
        seedPositionTest: false,
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
