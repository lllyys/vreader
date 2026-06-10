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
    @State private var exportURL: URL?
    @State private var isShowingShare = false

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
            }
            .sheet(isPresented: $isShowingShare) {
                if let exportURL {
                    ShareActivityView(activityItems: [exportURL]).ignoresSafeArea()
                }
            }
            .accessibilityIdentifier("diagnosticsLogView")
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.hasLoaded && !viewModel.isLoading && !viewModel.allEntries.isEmpty {
                Button(action: presentShare) {
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
                        ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                            let rowID = identity(for: entry)
                            DiagnosticsLogRow(
                                theme: theme,
                                entry: entry,
                                isExpanded: viewModel.expandedEntryID == rowID,
                                onTap: { toggle(rowID) },
                                onCopy: { copy(entry) }
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

    /// A stable row identity = the entry's index in the unfiltered loaded list.
    private func identity(for entry: DiagnosticsLogEntry) -> Int {
        viewModel.allEntries.firstIndex(of: entry) ?? -1
    }

    private func toggle(_ id: Int) {
        viewModel.expandedEntryID = viewModel.expandedEntryID == id ? nil : id
    }

    private func copy(_ entry: DiagnosticsLogEntry) {
        UIPasteboard.general.string = DiagnosticsRedactor.redact(entry.message)
    }

    private func presentShare() {
        let text = viewModel.exportText()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(viewModel.exportFileName(now: Date()))
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            exportURL = url
            isShowingShare = true
        } catch {
            // A failed temp-file write simply doesn't present the sheet — no
            // partial/corrupt share. (Diagnostics export is best-effort.)
        }
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
