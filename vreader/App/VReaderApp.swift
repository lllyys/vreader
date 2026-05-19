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

    /// Routes incoming `file://` URLs from iOS Share Sheet / "Open in vreader"
    /// to the BookImporter (Feature #59 WI-2). Nil if the SwiftData container
    /// failed to construct (the `bookImporterRef` we depend on is also nil in
    /// that case). `.onOpenURL` is wired in `body` below.
    @MainActor private let fileURLRouter: FileURLImportRouter?

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
            self.fileURLRouter = nil
            self.debugBridge = nil
            return
        }
        #endif

        do {
            let schema = Schema(SchemaV6.models)

            #if DEBUG
            // Use in-memory store for UI testing to ensure clean state
            // BETWEEN launches — except when the test deliberately
            // exercises terminate-then-relaunch persistence (`.positionTest`
            // for the first launch, `.keepExisting` for the second). Those
            // seeds need a disk-backed store so SwiftData rows survive
            // process termination. Bug #151 (GH #423): in-memory store dies
            // on `app.terminate()`, so the `.keepExisting` second launch
            // saw an empty library.
            //
            // Whitelisted by explicit seed flags rather than inferred by
            // exclusion so future seed enums default to in-memory (the
            // safer test-isolation default) rather than silently picking
            // up disk-backed cross-method state.
            let modelConfig: ModelConfiguration
            if config.isUITesting {
                let needsDiskBackedStore = config.seedPositionTest
                    || config.seedWarAndPeace
                    || config.seedMDTOC
                    || config.seedMDMultiPage
                    || config.seedEPUBFixture
                    || config.seedKeepExisting
                modelConfig = needsDiskBackedStore
                    ? ModelConfiguration()
                    : ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                modelConfig = ModelConfiguration()
            }
            #else
            let modelConfig = ModelConfiguration()
            #endif

            // Bug #186 / GH #633: build the container via the factory,
            // which skips `VReaderMigrationPlan` on a fresh install. There
            // is no store to migrate on first launch, and applying the plan
            // forces SwiftData to materialize SchemaV1–V5 on the main
            // thread here in `init()` — the multi-second first-launch
            // freeze. Existing installs still get the plan (their store
            // file already exists on disk).
            let container = try ModelContainerFactory.makeContainer(
                schema: schema,
                configuration: modelConfig
            )
            self.modelContainer = container
            self.initError = nil

            // Feature #54 WI-5: one-shot migration retiring the
            // Native/Unified reading mode — removes the
            // `readerReadingMode` UserDefaults key and strips the
            // `readingMode` field from per-book override JSON files.
            // Run SYNCHRONOUSLY here, before the DebugBridge / any
            // `ReaderSettingsStore` construction: the per-book JSON store
            // has no actor/lock, so a detached migration could race a
            // panel save or backup restore. At launch no reader is open
            // and no panel is mounted, so the migration owns the
            // per-book directory + UserDefaults. Idempotent.
            ReadingModeMigration.run(
                defaults: .standard,
                perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
            )

            #if DEBUG
            // Seed test data before creating the ViewModel to avoid race with LibraryView.loadBooks().
            // Uses Task.detached + semaphore to block init until seeding completes.
            // Bounded timeout prevents indefinite hang if seeding fails.
            if config.isUITesting {
                // Bug #152 (GH #426): clear UserDefaults state BEFORE
                // any production view reads it. `--reset-preferences`
                // is opt-in: tests that want a deterministic empty
                // state (e.g. OPDS empty-state) pass it; tests that
                // exercise saved-preference behavior leave it off.
                // Done synchronously on the calling thread because
                // `removeObject(forKey:)` doesn't need the persistence
                // actor and we want the wipe to happen before any
                // ViewModel reads the keys at view-init time.
                if config.seedResetPreferences {
                    TestSeeder.clearKnownPreferences()
                }

                // Feature #45 WI-4c: seed EPUB layout preference into
                // UserDefaults BEFORE any ReaderSettingsStore inits read
                // from it. Tests that need paged-mode reader use this
                // instead of driving the SwiftUI segmented Picker, which
                // doesn't transition state under XCUITest (iOS 26.5).
                // Done AFTER --reset-preferences so the layout override
                // isn't immediately wiped.
                if let layout = config.defaultEPUBLayout {
                    UserDefaults.standard.set(
                        layout.rawValue,
                        forKey: ReaderSettingsStore.epubLayoutKey
                    )
                }

                // Feature #45 WI-4e: swap AVSpeechSynthesizer for the
                // XCUITest mock at TTSService construction time. Real
                // AVSpeechSynthesizer doesn't transition to .speaking
                // under XCUITest headless on iPhone 17 Pro Sim. Write
                // unconditionally (both branches) so a prior launch's
                // value in the same process doesn't leak.
                TTSTestOverride.useMockSynthesizer = config.ttsTestMode

                let persistence = PersistenceActor(modelContainer: container)
                let seedConfig = config
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    if seedConfig.seedEmpty {
                        await TestSeeder.clearAllBooks(persistence: persistence)
                    } else if seedConfig.seedPositionTest {
                        await TestSeeder.seedPositionTest(persistence: persistence)
                    } else if seedConfig.seedWarAndPeace {
                        await TestSeeder.seedWarAndPeace(persistence: persistence)
                    } else if seedConfig.seedMDTOC {
                        await TestSeeder.seedMDWithTOC(persistence: persistence)
                    } else if seedConfig.seedMDMultiPage {
                        await TestSeeder.seedMDMultiPage(persistence: persistence)
                    } else if seedConfig.seedEPUBFixture {
                        await TestSeeder.seedMiniEPUB(persistence: persistence)
                    } else if seedConfig.seedTwoBooks {
                        await TestSeeder.seedTwoBooks(persistence: persistence)
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
            // Feature #59 WI-2: route incoming file:// URLs from iOS Share
            // Sheet / "Open in vreader" to the just-constructed importer.
            // The unknown-extension reporter is a no-op for now — a future
            // iteration can wire a toast or alert presenter here.
            self.fileURLRouter = FileURLImportRouter(bookImporter: importer)

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
            // Bug #115 (#47 WI-4b): wire LazyDownloadFinalizer into the
            // coordinator. Without this, didFinishDownload only records
            // the .completed outcome — the staged file never moves to
            // the canonical sandbox path and the Book row stays
            // .remoteOnly forever, so the library row never refreshes.
            let lazyFinalizer = LazyDownloadFinalizer(persistence: persistence)
            self.lazyDownloadCoordinator = MainActor.assumeIsolated {
                let coord = LazyDownloadCoordinator(
                    session: backgroundSession,
                    persistence: persistence,
                    finalizer: lazyFinalizer
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

            // Feature #52 WI-2: one-shot migration from pre-#52 flat-
            // keychain WebDAV credentials to the new
            // `WebDAVServerProfileStore`. After WI-5 the profile store
            // is the sole production credentials source (the legacy
            // `WebDAVProviderFactory.make(keychain:)` flat-keychain
            // path was removed), so this migration is what bridges
            // pre-#52 installs into the new world — without it,
            // existing users would see an empty profile list and
            // would need to re-enter credentials.
            //
            // Fire-and-forget — the migrator is idempotent on two
            // axes (marker key `com.vreader.webdav.profilesMigrated.v1`
            // OR non-empty store), so a re-run on the next launch is
            // harmless if this background Task hasn't completed
            // before the user opens settings.
            Task.detached(priority: .background) {
                do {
                    try await WebDAVProfileMigrator.migrateIfNeeded()
                } catch {
                    // Logged via the migrator's internal Logger.
                    // Next-launch retry handles transient failures.
                }
            }
        } catch {
            self.modelContainer = nil
            // Sanitize: don't expose raw file paths or internal details to the user.
            self.initError = Self.sanitizedErrorMessage(error)
            self.contentView = nil
            self.persistenceActor = nil
            self.bookImporterRef = nil
            self.lazyDownloadCoordinator = nil
            self.webDAVNetworkPolicy = nil
            self.fileURLRouter = nil
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
                    .onOpenURL { [debugBridge, fileURLRouter] url in
                        // Feature #59 WI-2: Debug-bridge scheme takes
                        // priority; file URLs fall through to the router.
                        if url.scheme == DebugCommand.scheme {
                            guard let debugBridge else { return }
                            Task { @MainActor in
                                await debugBridge.handle(url)
                            }
                            return
                        }
                        fileURLRouter?.dispatch(url)
                    }
                #else
                contentView
                    .modelContainer(modelContainer)
                    .environment(\.persistenceActor, persistenceActor)
                    .environment(\.bookImporter, bookImporterRef)
                    .environment(\.lazyDownloadCoordinator, lazyDownloadCoordinator)
                    .environment(\.webDAVNetworkPolicy, webDAVNetworkPolicy)
                    .onOpenURL { [fileURLRouter] url in
                        // Feature #59 WI-2: Release builds only handle
                        // file:// URLs. vreader-debug:// is not registered
                        // in Release per the CFBundleURLTypes injection
                        // guard in project.yml.
                        fileURLRouter?.dispatch(url)
                    }
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
    let seedWarAndPeace: Bool
    let seedMDTOC: Bool
    /// `--seed-md-multi-page` — seed a larger MD doc sized to span multiple
    /// pages at 18pt on iPhone 17 Pro Sim's reader viewport. Feature #45
    /// WI-5 fixture for Feature #31 (Auto page turning) live-advancement
    /// verification. Distinct from `seedMDTOC` (smaller, single-page size
    /// class). The "spans ≥2 pages at 18pt" contract is unit-tested via the
    /// real MD render + paginate pipeline; exact byte counts drift with
    /// fixture text edits and are not contractual.
    let seedMDMultiPage: Bool
    /// `--seed-two-books` — two TXT books with real backing files for
    /// Feature #37's per-book-settings isolation test. Bug #209 / GH #804.
    let seedTwoBooks: Bool
    /// `--seed-epub-fixture` — seed the bundled `mini-epub3.epub` as a
    /// single real, openable EPUB. Bug #214 / GH #834: the `.books` seed's
    /// EPUB fixtures are metadata-only (no backing file) and never open, so
    /// the EPUB reader bottom-chrome verification test needs its own
    /// real-file seed. Implies a disk-backed store (EPUB import + selective
    /// extraction touch the filesystem).
    let seedEPUBFixture: Bool
    let seedCorruptDB: Bool
    /// `--uitesting-no-seed` — skip seeding, expect the previous launch's
    /// SwiftData store to remain. Used for terminate-then-relaunch tests
    /// (e.g. `testPositionSurvivesAppRelaunch`) where data continuity
    /// across an `app.terminate()` is the assertion. Implies
    /// disk-backed `ModelConfiguration` (bug #151 / GH #423).
    let seedKeepExisting: Bool
    /// `--reset-preferences` — wipe every UserDefaults key in
    /// `TestSeeder.knownPreferenceKeys` before the seeding step. Bug
    /// #152 (GH #426): `--uitesting` only swaps the SwiftData store
    /// for in-memory, but UserDefaults survives across
    /// `XCUIApplication.launch()` cycles, so empty-state UI tests
    /// flake based on residual OPDS / theme / AI-consent / etc.
    /// state from prior simulator sessions. Opt-in so tests that
    /// WANT to inherit prior preferences (rare) keep working.
    let seedResetPreferences: Bool
    /// `--reader-default-layout=<paged|scroll>` — pre-seed the EPUB layout
    /// preference into `UserDefaults` before any reader view inits its
    /// `ReaderSettingsStore`. Feature #45 WI-4c: SwiftUI segmented
    /// `Picker(.segmented)` doesn't dispatch tap-to-segment under XCUITest
    /// (gh #576), so verification tests that need paged mode pass this
    /// flag instead of driving the picker. Invalid raw values fall through
    /// to nil (no UserDefaults write; production default applies).
    let defaultEPUBLayout: EPUBLayoutPreference?
    let colorSchemeOverride: ColorScheme?
    let dynamicTypeOverride: DynamicTypeSize?
    let enableAI: Bool
    let enableSync: Bool
    let reduceMotion: Bool
    /// `--tts-test-mode` — feature #45 WI-4e. Swap `AVSpeechSynthesizer`
    /// for `XCUITestMockSpeechSynthesizer` at `TTSService` construction
    /// time so XCUITest verification can observe `ttsState` / `ttsOffsetUTF16`
    /// without a real audio session (which fails to activate under
    /// XCUITest headless mode on iPhone 17 Pro Simulator).
    let ttsTestMode: Bool

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

        // Parse --reader-default-layout=<value>. Last occurrence wins.
        // Invalid raw values fall through to nil (no override).
        var defaultEPUBLayout: EPUBLayoutPreference? = nil
        for arg in arguments where arg.hasPrefix("--reader-default-layout=") {
            let value = String(arg.dropFirst("--reader-default-layout=".count))
            if let layout = EPUBLayoutPreference(rawValue: value) {
                defaultEPUBLayout = layout
            } else {
                defaultEPUBLayout = nil
            }
        }

        return TestLaunchConfig(
            isUITesting: args.contains("--uitesting"),
            seedEmpty: args.contains("--seed-empty"),
            seedBooks: args.contains("--seed-books"),
            seedPositionTest: args.contains("--seed-position-test"),
            seedWarAndPeace: args.contains("--seed-war-and-peace"),
            seedMDTOC: args.contains("--seed-md-toc"),
            seedMDMultiPage: args.contains("--seed-md-multi-page"),
            seedTwoBooks: args.contains("--seed-two-books"),
            seedEPUBFixture: args.contains("--seed-epub-fixture"),
            seedCorruptDB: args.contains("--seed-corrupt-db"),
            seedKeepExisting: args.contains("--uitesting-no-seed"),
            seedResetPreferences: args.contains("--reset-preferences"),
            defaultEPUBLayout: defaultEPUBLayout,
            colorSchemeOverride: colorScheme,
            dynamicTypeOverride: dynamicType,
            enableAI: args.contains("--enable-ai"),
            enableSync: args.contains("--enable-sync"),
            reduceMotion: args.contains("--reduce-motion"),
            ttsTestMode: args.contains("--tts-test-mode")
        )
    }

    /// A no-op config for non-test launches.
    static let none = TestLaunchConfig(
        isUITesting: false,
        seedEmpty: false,
        seedBooks: false,
        seedPositionTest: false,
        seedWarAndPeace: false,
        seedMDTOC: false,
        seedMDMultiPage: false,
        seedTwoBooks: false,
        seedEPUBFixture: false,
        seedCorruptDB: false,
        seedKeepExisting: false,
        seedResetPreferences: false,
        defaultEPUBLayout: nil,
        colorSchemeOverride: nil,
        dynamicTypeOverride: nil,
        enableAI: false,
        enableSync: false,
        reduceMotion: false,
        ttsTestMode: false
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
