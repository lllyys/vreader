// Purpose: Main settings sheet presented from the library toolbar.
// Re-skinned for feature #60 visual-identity v2 (WI-10): the design's
// `Sheet` chrome (`ReaderSheetChrome`) with a centred "Settings" title
// and a Done trailing slot, a paper surface, and the four design
// section groups (Cloud & Sync / AI / Reading / About).
//
// Feature #67 WI-4: mounts the design's profile-header card
// (`SettingsProfileCard`) as the first `Form` row, restyles the
// Cloud & Sync / Reading / About rows to the design's colored-icon
// `SettingsIconRow` (`SettingsRowPalette` data), and wires the Stats
// pill to post `Notification.Name.openReadingStatsRequested` —
// which the view itself observes to present `ReadingDashboardView`.
//
// Key decisions:
// - Presented as a sheet from the gear icon in the LibraryView nav bar.
// - The Library is not theme-switchable, so the sheet uses the `.paper`
//   theme — matching the design `SettingsSheet`'s `THEMES.paper`
//   default.
// - An inner `NavigationStack` is kept (with its root nav bar hidden)
//   so the row `NavigationLink`s still push their detail screens; the
//   `ReaderSheetChrome` title bar sits above it. Pushed detail screens
//   show their own nav bar for the back button.
// - The `Form` keeps every existing `NavigationLink` destination; the
//   AI group is the feature-#50 `AISettingsSection` composite (its
//   restyle ships in feature #67 WI-5).
// - The profile card is rendered as the FIRST row of the `Form`,
//   inside its own header-less `Section` with `.listRowBackground(.clear)`,
//   explicit insets, and a hidden separator — so it renders as the
//   design's free-standing 14pt-radius card above the grouped sections
//   while staying inside the single `Form` scroll region (no fixed
//   header / no `ScrollView` rewrite).
// - The header card's two numbers (`bookCount`, `monthReadingSeconds`)
//   come from `SettingsHeaderViewModel` (`@State`), loaded in a `.task`
//   from the optional `\.persistenceActor` Environment.
// - Stats hand-off: the card's `onOpenStats` posts a notification; the
//   view's own observer toggles `isShowingStats` and presents
//   `ReadingDashboardView` over a freshly-built
//   `ReadingDashboardViewModel(aggregator: ReadingStatsAggregator(...))`.
//   Posting + observing the same notification keeps the architecture-bus
//   contract intact while satisfying the design's "Settings → Stats"
//   entry-point.
// - AISettingsViewModel created once and owned by this view.
// - About section shows app version from Bundle.
//
// @coordinates-with: LibraryView.swift, ReaderSheetChrome.swift,
//   SheetSectionContract.swift, AISettingsSection.swift,
//   AISettingsViewModel.swift, ReplacementRulesView.swift,
//   BookSourceListView.swift, WebDAVSettingsView.swift,
//   HTTPTTSSettingsView.swift, SettingsProfileCard.swift,
//   SettingsHeaderViewModel.swift, SettingsRowStyle.swift,
//   SettingsRowPalette.swift, SettingsNotifications.swift,
//   ReadingDashboardView.swift, ReadingDashboardViewModel.swift,
//   ReadingStatsAggregator.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import SwiftUI
import SwiftData

/// App settings screen presented as a sheet (feature #60 WI-10 re-skin,
/// feature #67 WI-4 profile card + row restyle).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.persistenceActor) private var persistenceActor
    @Environment(\.modelContext) var modelContext

    @State private var viewModel = AISettingsViewModel()
    @State private var headerViewModel = SettingsHeaderViewModel()

    /// The Stats-dashboard sheet's state machine — owns the
    /// `isShowing` flag and the current `ReadingDashboardViewModel`.
    /// Production opens supply `makeProductionStatsViewModel()` as
    /// the per-open builder; tests substitute a stub builder.
    @State var statsPresenter = SettingsStatsPresenter()

    /// The design theme for this sheet — the Library is not
    /// theme-switchable, so it uses the `.paper` light palette per the
    /// design `SettingsSheet` default.
    private let theme: ReaderThemeV2 = .paper

    /// The sheet's `.paper` theme — exposed to the
    /// `+StatsSheet.swift` extension so it can render the dashboard
    /// over the same surface without re-declaring the constant.
    var paperTheme: ReaderThemeV2 { theme }

    /// The section labels this view declares *directly*, in render
    /// order — exposed for the WI-10 composition test. The design
    /// `SettingsSheet` shows four groups; this sheet renders the
    /// Cloud & Sync / Reading / About groups itself and delegates the
    /// "AI" group to the established feature-#50 `AISettingsSection`
    /// composite.
    var sectionsForTesting: [String] {
        ["Cloud & Sync", "Reading", "About"]
    }

    /// The `SettingsRowPalette` spec keys for each row this view
    /// directly renders, in render order — exposed for the feature #67
    /// WI-4 composition test. The AI group's keys (WI-5) are owned by
    /// `AISettingsSection.rowPaletteKeysForTesting`.
    var rowPaletteKeysForTesting: [String] {
        [
            SettingsRowPalette.webDAVBackup.paletteKey,
            SettingsRowPalette.bookSources.paletteKey,
            SettingsRowPalette.replacementRules.paletteKey,
            SettingsRowPalette.httpTTS.paletteKey,
            SettingsRowPalette.helpFeedback.paletteKey,
            SettingsRowPalette.version.paletteKey
        ]
    }

    /// The mounted profile card — exposed for the WI-4 composition test.
    /// Constructed lazily off `headerViewModel`'s observable state so
    /// the test reads the same shape the body renders.
    var profileCardForTesting: SettingsProfileCard {
        SettingsProfileCard(
            theme: theme,
            bookCount: headerViewModel.bookCount,
            monthReadingSeconds: headerViewModel.monthReadingSeconds,
            onOpenStats: statsHandoffActionForTesting
        )
    }

    /// The closure wired to the profile card's `onOpenStats` — posts
    /// `Notification.Name.openReadingStatsRequested` (no `userInfo`).
    /// Exposed for the WI-4 `SettingsViewStatsHandoffTests`.
    var statsHandoffActionForTesting: () -> Void {
        {
            NotificationCenter.default.post(
                name: .openReadingStatsRequested,
                object: nil
            )
        }
    }

    var body: some View {
        ReaderSheetChrome(
            theme: theme,
            title: ReaderSheetKind.appSettings.designTitle,
            trailing: {
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(theme.accentColor))
                    .accessibilityIdentifier("settingsDoneButton")
            }
        ) {
            settingsStack
        }
        .accessibilityIdentifier("settingsView")
        .task {
            await headerViewModel.load(persistence: persistenceActor)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReadingStatsRequested)) { _ in
            statsPresenter.present(build: makeProductionStatsViewModel)
        }
        .sheet(
            isPresented: $statsPresenter.isShowing,
            onDismiss: {
                // Clear the VM on swipe-dismiss so the next open
                // allocates a fresh presenter. The Done button's
                // explicit `.dismiss()` path clears too, but `.sheet`'s
                // native swipe-down bypasses that closure — this
                // `onDismiss:` covers it.
                statsPresenter.handleSheetOnDismiss()
            }
        ) {
            statsSheetContent
        }
    }

    // MARK: - Settings body

    /// An inner `NavigationStack` so the row `NavigationLink`s still
    /// push. Its root nav bar is hidden — the `ReaderSheetChrome` title
    /// bar replaces it — but pushed detail screens keep their own nav
    /// bar so the back button works.
    private var settingsStack: some View {
        NavigationStack {
            Form {
                profileCardSection
                cloudAndSyncSection
                aiSection
                readingSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(theme.sheetSurfaceColor))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Profile card (feature #67 WI-4)

    /// The header-less section that renders the design's profile card
    /// as the first `Form` row. The card carries its own card
    /// background, so the list row background is hidden, the row
    /// separator is suppressed, and the row's insets are the design's
    /// 14pt edge.
    @ViewBuilder
    private var profileCardSection: some View {
        Section {
            SettingsProfileCard(
                theme: theme,
                bookCount: headerViewModel.bookCount,
                monthReadingSeconds: headerViewModel.monthReadingSeconds,
                onOpenStats: statsHandoffActionForTesting
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Cloud & Sync (design `SettingsSheet` group 1)

    /// Backup + content-source destinations — the design's "Cloud &
    /// Sync" group. (The design's OPDS-catalogs row routes through the
    /// Library nav bar, not this sheet, so it is not duplicated here.)
    @ViewBuilder
    private var cloudAndSyncSection: some View {
        Section("Cloud & Sync") {
            NavigationLink {
                WebDAVSettingsView()
            } label: {
                SettingsIconRow(
                    theme: theme,
                    icon: Image(systemName: SettingsRowPalette.webDAVBackup.symbolName),
                    iconBackground: SettingsRowPalette.webDAVBackup.background.color,
                    title: "WebDAV Backup",
                    showsChevron: false
                )
            }
            .accessibilityIdentifier("settingsWebDAV")

            NavigationLink {
                BookSourceListView()
            } label: {
                SettingsIconRow(
                    theme: theme,
                    icon: Image(systemName: SettingsRowPalette.bookSources.symbolName),
                    iconBackground: SettingsRowPalette.bookSources.background.color,
                    title: "Book Sources",
                    showsChevron: false
                )
            }
            .accessibilityIdentifier("settingsBookSources")
        }
    }

    // MARK: - AI (design `SettingsSheet` group 2)

    private var aiSection: some View {
        AISettingsSection(viewModel: viewModel)
    }

    // MARK: - Reading (design `SettingsSheet` group 3)

    /// Reading-feature destinations — the design's "Reading" group.
    @ViewBuilder
    private var readingSection: some View {
        Section("Reading") {
            NavigationLink {
                ReplacementRulesView()
            } label: {
                SettingsIconRow(
                    theme: theme,
                    icon: Image(systemName: SettingsRowPalette.replacementRules.symbolName),
                    iconBackground: SettingsRowPalette.replacementRules.background.color,
                    title: "Replacement Rules",
                    showsChevron: false
                )
            }
            .accessibilityIdentifier("settingsReplacementRules")

            NavigationLink {
                HTTPTTSSettingsView()
            } label: {
                SettingsIconRow(
                    theme: theme,
                    icon: Image(systemName: SettingsRowPalette.httpTTS.symbolName),
                    iconBackground: SettingsRowPalette.httpTTS.background.color,
                    title: "HTTP TTS",
                    showsChevron: false
                )
            }
            .accessibilityIdentifier("settingsHTTPTTS")
        }
    }

    // MARK: - About (design `SettingsSheet` group 4)

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            SettingsIconRow(
                theme: theme,
                icon: Image(systemName: SettingsRowPalette.helpFeedback.symbolName),
                iconBackground: SettingsRowPalette.helpFeedback.background.color,
                title: "Help & Feedback",
                showsChevron: false
            )
            .accessibilityIdentifier("settingsHelpFeedback")

            SettingsIconRow(
                theme: theme,
                icon: Image(systemName: SettingsRowPalette.version.symbolName),
                iconBackground: SettingsRowPalette.version.background.color,
                title: "Version",
                trailingValue: Self.appVersion,
                showsChevron: false
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settingsVersion")
        }
    }

    // MARK: - Private

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

