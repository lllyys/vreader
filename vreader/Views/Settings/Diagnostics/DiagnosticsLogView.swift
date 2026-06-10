// Purpose: Feature #96 WI-2 — the Diagnostics log viewer pushed from
// Settings → Support → Diagnostics (design `DiagLogViewer`). A nav bar with a
// trailing share trigger, the level + category chip filters, a day-grouped
// newest-first monospace log list, and a pinned capture-status footer. Covers
// the design's default / loading / empty / filtered-empty / share states.
//
// Binds to the WI-1 `DiagnosticsLogStore` (via `DiagnosticsLogViewModel`):
// capture is always-on in Release, so the footer states "Capturing" rather than
// offering a toggle. Export shares the store's REDACTED text as a `.txt` file
// through the established `ShareActivityView` (feature #35 pattern).
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
// + `design-notes/diagnostics-log-viewer.md`.
//
// @coordinates-with: DiagnosticsLogViewModel.swift, DiagnosticsFilterChips.swift,
//   DiagnosticsLogRow.swift, ShareSheet.swift, SettingsView.swift

import SwiftUI

struct DiagnosticsLogView: View {
    @State private var viewModel: DiagnosticsLogViewModel
    /// The redacted export file (`vreader-log-<date>.txt`), prepared off-main
    /// and regenerated when a filter changes so the shared file always matches
    /// what's on screen. `nil` until the first prepare completes.
    @State private var exportURL: URL?

    private let theme: ReaderThemeV2

    init(
        theme: ReaderThemeV2 = .paper,
        viewModel: DiagnosticsLogViewModel = DiagnosticsLogViewModel()
    ) {
        self.theme = theme
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .background(Color(theme.sheetSurfaceColor).ignoresSafeArea())
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { trailingToolbar }
            .task {
                if !viewModel.hasLoaded { await viewModel.load() }
                await prepareExport()
            }
            .onChange(of: viewModel.levelFilter) { Task { await prepareExport() } }
            .onChange(of: viewModel.categoryFilter) { Task { await prepareExport() } }
            .accessibilityIdentifier("diagnosticsLogView")
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // Native `ShareLink` — presents the system share sheet correctly even
            // from this depth (sheet → NavigationStack push). An embedded
            // `UIActivityViewController` renders blank from three presentation
            // levels deep; `ShareLink` does not. Shown once a redacted file is
            // ready and there's something to share.
            if viewModel.hasLoaded, !viewModel.isLoading,
               !viewModel.allEntries.isEmpty, let exportURL {
                ShareLink(item: exportURL) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color(theme.accentColor))
                }
                .accessibilityIdentifier("diagnosticsShareButton")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading || !viewModel.hasLoaded {
            loadingState
        } else if viewModel.allEntries.isEmpty {
            DiagnosticsEmptyState(theme: theme, filtered: false) {}
        } else {
            VStack(spacing: 0) {
                DiagnosticsFilterBar(viewModel: viewModel, theme: theme)
                if viewModel.filteredEntries.isEmpty {
                    DiagnosticsEmptyState(theme: theme, filtered: true) {
                        viewModel.levelFilter = .all
                        viewModel.categoryFilter = nil
                    }
                } else {
                    logList
                }
                footer
            }
        }
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.daySections(now: Date())) { section in
                    Section {
                        ForEach(section.entries) { item in
                            DiagnosticsLogRow(
                                theme: theme,
                                entry: item.entry,
                                isExpanded: viewModel.expandedEntryID == item.id,
                                onTap: { toggle(item.id) },
                                onCopy: { copy(item.entry) }
                            )
                            Divider().overlay(Color(theme.ruleColor))
                        }
                    } header: {
                        dayHeader(section.header)
                    }
                }
            }
        }
    }

    private func dayHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color(theme.subColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(Color(theme.sheetSurfaceColor))
    }

    private var footer: some View {
        HStack {
            Text(viewModel.footerScope)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(theme.subColor))
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(diagnosticsHex: 0x4a9a6a))
                    .frame(width: 6, height: 6)
                Text("Capturing")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(theme.ruleColor)).frame(height: 0.5)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color(theme.accentColor))
            VStack(spacing: 4) {
                Text("Reading log store…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Text("OSLogStore · com.vreader.app")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(theme.subColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggle(_ id: Int) {
        viewModel.expandedEntryID = viewModel.expandedEntryID == id ? nil : id
    }

    private func copy(_ entry: DiagnosticsLogEntry) {
        UIPasteboard.general.string = DiagnosticsRedactor.redact(entry.message)
    }

    /// Builds the redacted, filter-narrowed export and writes it to a temp
    /// `.txt` OFF the main actor (large logs shouldn't hitch the UI), then
    /// publishes the URL for `ShareLink`. Regenerated on appear + on each filter
    /// change so the shared file always matches what's on screen. A write
    /// failure simply leaves the share affordance hidden (best-effort export).
    private func prepareExport() async {
        let text = viewModel.exportText()
        let fileName = viewModel.exportFileName(now: Date())
        if let url = await Self.writeExport(text, fileName: fileName) {
            exportURL = url
        }
    }

    /// Writes the export text to a temp file off-main. `nonisolated` so the
    /// blocking encode + write run off the `@MainActor`. Returns `nil` on
    /// failure (the share affordance then stays hidden).
    private nonisolated static func writeExport(
        _ text: String, fileName: String
    ) async -> URL? {
        await Task.detached(priority: .utility) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            return (try? Data(text.utf8).write(to: url, options: .atomic)) != nil ? url : nil
        }.value
    }
}

/// The default + filtered empty states (design `DiagEmpty`).
struct DiagnosticsEmptyState: View {
    let theme: ReaderThemeV2
    let filtered: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(filtered
                        ? Color(theme.inkColor).opacity(theme.isDark ? 0.06 : 0.05)
                        : Color(diagnosticsHex: 0x5b6770))
                    .frame(width: 54, height: 54)
                Image(systemName: filtered ? "line.3.horizontal.decrease" : "waveform.path.ecg")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(filtered ? Color(theme.subColor) : .white)
            }
            .padding(.bottom, 16)

            Text(filtered ? "No matching entries" : "No log entries yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(theme.inkColor))
            Text(filtered
                ? "Nothing matches the active filters in this session."
                : "VReader records errors and key events as you read. Entries appear here automatically — nothing to turn on.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            if filtered {
                Button(action: onClearFilters) {
                    Text("Clear filters")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(theme.accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(theme.accentColor).opacity(0.1)))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .accessibilityIdentifier("diagnosticsClearFilters")
            }
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
