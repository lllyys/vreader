// Purpose: Feature #96 WI-2 — the diagnostics viewer's view model. Owns the
// WI-1 `DiagnosticsLogStore`, the active level/category filter selection, and
// the expanded-row identity; derives the filtered + day-grouped entry list,
// the per-chip counts, and the redacted export payload the share sheet emits.
//
// Key decisions:
// - `@MainActor @Observable` (codebase ViewModel convention) — the store is
//   `@MainActor`, and the view binds the selection directly.
// - **Filtering lives here, not only in the store**, so the "Errors" chip can
//   include `.fault` (`DiagnosticsLevelFilter.matches`) — the store's single
//   `level:` predicate can't express a set.
// - **Counts are over ALL loaded entries** (category-independent), matching the
//   design's global level-chip counts.
// - **Export is the store's redacted text** narrowed to the active filter; the
//   filename carries the injected `now` so it tests deterministically.
//
// @coordinates-with: DiagnosticsLogStore.swift, DiagnosticsLevelStyle.swift,
//   DiagnosticsLogView.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`

import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsLogViewModel {

    private let store: DiagnosticsLogStore

    /// The active level-filter chip (design default: `All`).
    var levelFilter: DiagnosticsLevelFilter = .all {
        didSet { if oldValue != levelFilter { expandedEntryID = nil } }
    }

    /// The active category chip, `nil` == "All".
    var categoryFilter: String? {
        didSet { if oldValue != categoryFilter { expandedEntryID = nil } }
    }

    /// The currently-expanded row's identity (its index in the *unfiltered*
    /// loaded list), or `nil` when every row is collapsed.
    var expandedEntryID: Int?

    /// True while a load is in flight — drives the design's loading state.
    private(set) var isLoading = false

    init(store: DiagnosticsLogStore = DiagnosticsLogStore()) {
        self.store = store
    }

    /// Whether a load has completed at least once (empty-vs-unloaded).
    var hasLoaded: Bool { store.hasLoaded }

    /// Loads recent entries via the store. Toggles `isLoading` around the
    /// await so the viewer can show the spinner state.
    func load(since: Date? = nil) async {
        isLoading = true
        await store.load(since: since)
        isLoading = false
    }

    /// All loaded entries (oldest→newest as the store holds them).
    var allEntries: [DiagnosticsLogEntry] { store.entries }

    /// The distinct categories present, sorted — drives the category chip row.
    var categories: [String] { store.categories }

    /// Entries passing both active filters, in the store's order (oldest→newest).
    var filteredEntries: [DiagnosticsLogEntry] {
        store.entries.filter { entry in
            levelFilter.matches(entry.level)
                && (categoryFilter == nil
                    || categoryFilter!.isEmpty
                    || entry.category == categoryFilter)
        }
    }

    /// Whether any filter is narrowing the list (drives the filtered-empty
    /// state's "Clear filters" affordance vs the plain empty state).
    var isFiltering: Bool {
        levelFilter != .all || (categoryFilter != nil && !(categoryFilter ?? "").isEmpty)
    }

    /// The filtered entries tagged with a stable identity (their position in
    /// the filtered list). Identity is position-based, NOT `Equatable`-derived,
    /// so two value-equal entries expand independently. Stable within the
    /// current filter selection — changing a filter resets `expandedEntryID`.
    var identifiedEntries: [IdentifiedDiagnosticsEntry] {
        filteredEntries.enumerated().map { IdentifiedDiagnosticsEntry(id: $0.offset, entry: $0.element) }
    }

    /// The day-grouped, newest-first sections the list renders.
    func daySections(now: Date, calendar: Calendar = .current) -> [DiagnosticsDaySection] {
        DiagnosticsDayGrouper.sections(from: identifiedEntries, now: now, calendar: calendar)
    }

    /// Count of loaded entries matching a level filter (category-independent),
    /// for the chip badges.
    func count(for filter: DiagnosticsLevelFilter) -> Int {
        store.entries.filter { filter.matches($0.level) }.count
    }

    /// The redacted export text, narrowed to EXACTLY the active filter — built
    /// from `filteredEntries` so the "Errors" chip's `.fault` rows are included
    /// (the store's single `level:` predicate can't express that set).
    func exportText() -> String {
        store.exportText(entries: filteredEntries)
    }

    /// The export filename — `vreader-log-YYYY-MM-DD.txt` (design payload
    /// header). `now` injected for deterministic tests.
    func exportFileName(now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "vreader-log-\(formatter.string(from: now)).txt"
    }

    /// The footer's scope line. Default mirrors the design "N entries · …";
    /// filtered mirrors "Showing X of N · <active filter>". The capture-window
    /// label is single-sourced from `DiagnosticsLogStore.captureScopeLabel`
    /// (shared with the export header) — "this session", the accurate descriptor
    /// for the `.currentProcessIdentifier` window, superseding the design mock's
    /// "last 24 h" per WI-1's Gate-2 scope correction.
    var footerScope: String {
        let total = store.entries.count
        guard isFiltering else {
            return "\(total) entr\(total == 1 ? "y" : "ies") · \(DiagnosticsLogStore.captureScopeLabel)"
        }
        let shown = filteredEntries.count
        let suffix = activeFilterDescriptor.map { " · \($0)" } ?? ""
        return "Showing \(shown) of \(total)\(suffix)"
    }

    /// A short human label for the active filter, used in the filtered footer
    /// scope (design "Showing 12 of 487 · errors" / category context).
    private var activeFilterDescriptor: String? {
        let levelPart: String? = levelFilter == .all ? nil : levelFilter.label.lowercased()
        let categoryPart: String? = (categoryFilter?.isEmpty == false) ? categoryFilter : nil
        switch (levelPart, categoryPart) {
        case let (l?, c?): return "\(c) \(l)"
        case let (l?, nil): return l
        case let (nil, c?): return c
        case (nil, nil):   return nil
        }
    }
}
