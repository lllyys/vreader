// Purpose: Main settings sheet presented from the library toolbar.
// Re-skinned for feature #60 visual-identity v2 (WI-10): the design's
// `Sheet` chrome (`ReaderSheetChrome`) with a centred "Settings" title
// and a Done trailing slot, a paper surface, and the four design
// section groups (Cloud & Sync / AI / Reading / About).
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
// - The `Form` keeps every existing `NavigationLink` destination; only
//   the section grouping is re-labelled to the design's four groups
//   and the `Form`'s own background is hidden so the paper surface
//   shows through.
// - AISettingsViewModel created once and owned by this view.
// - About section shows app version from Bundle.
//
// @coordinates-with: LibraryView.swift, ReaderSheetChrome.swift,
//   SheetSectionContract.swift, AISettingsSection.swift,
//   AISettingsViewModel.swift, ReplacementRulesView.swift,
//   BookSourceListView.swift, WebDAVSettingsView.swift,
//   HTTPTTSSettingsView.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import SwiftUI

/// App settings screen presented as a sheet (feature #60 WI-10 re-skin).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AISettingsViewModel()

    /// The design theme for this sheet — the Library is not
    /// theme-switchable, so it uses the `.paper` light palette per the
    /// design `SettingsSheet` default.
    private let theme: ReaderThemeV2 = .paper

    /// The section labels this view declares *directly*, in render
    /// order — exposed for the WI-10 composition test. The design
    /// `SettingsSheet` shows four groups; this sheet renders the
    /// Cloud & Sync / Reading / About groups itself and delegates the
    /// "AI" group to the established feature-#50 `AISettingsSection`
    /// composite (which internally sub-divides into AI Assistant /
    /// Providers / Data & Privacy — re-shaping that component is out of
    /// WI-10 scope). The test asserts these are exactly the three
    /// directly-declared groups, between the AI-section delegate.
    var sectionsForTesting: [String] {
        ["Cloud & Sync", "Reading", "About"]
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
    }

    // MARK: - Settings body

    /// An inner `NavigationStack` so the row `NavigationLink`s still
    /// push. Its root nav bar is hidden — the `ReaderSheetChrome` title
    /// bar replaces it — but pushed detail screens keep their own nav
    /// bar so the back button works.
    private var settingsStack: some View {
        NavigationStack {
            Form {
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
                Label("WebDAV Backup", systemImage: "externaldrive.badge.icloud")
            }
            .accessibilityIdentifier("settingsWebDAV")

            NavigationLink {
                BookSourceListView()
            } label: {
                Label("Book Sources", systemImage: "globe")
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
                Label("Replacement Rules", systemImage: "character.textbox")
            }
            .accessibilityIdentifier("settingsReplacementRules")

            NavigationLink {
                HTTPTTSSettingsView()
            } label: {
                Label("HTTP TTS", systemImage: "speaker.wave.2")
            }
            .accessibilityIdentifier("settingsHTTPTTS")
        }
    }

    // MARK: - About (design `SettingsSheet` group 4)

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.appVersion)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Private

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
