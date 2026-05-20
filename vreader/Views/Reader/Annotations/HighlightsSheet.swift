// Purpose: Feature #62 WI-4 — the review half of the annotations-panel
// split: the All / Highlights / Notes / Bookmarks unified card stream.
//
// `HighlightsSheet` is the "revisit reading" sheet. It wraps the shared
// `ReaderSheetChrome` with `title: "Annotations"` and a single designed
// Share/export button in the trailing slot (the #860 `HighlightsSheetV3`
// design — see the import-deferral note below). A horizontally-scrolling
// filter-chip row with per-filter count badges sits over a unified card
// stream rendering `HighlightCardV3` / `StandaloneNoteCard` per
// `AnnotationStreamItem`.
//
// **Import-deferral (Gate-2 round-2 finding 2 / needs-design #963)**:
// the committed design has NO import affordance, so `HighlightsSheet`
// ships ONLY the designed export button. The `AnnotationImporter`
// engine + the import flow are RETAINED (compiled, tested) in
// `HighlightsSheet+Export.swift` as `private` reachable-once-#963-lands
// code — no `.fileImporter` UI, no import button. Import being briefly
// UI-unreachable is a tracked regression (#963), not a silent drop.
//
// The export flow lives in `HighlightsSheet+Export.swift`; the
// count/stream helpers + DEBUG hooks in `HighlightsSheet+Support.swift`.
//
// @coordinates-with: HighlightsSheet+Export.swift, HighlightsSheet+Support.swift,
//   HighlightAnnotationCard.swift, AnnotationStreamBuilder.swift,
//   AnnotationsEmptyStateView.swift, ReaderSheetChrome.swift,
//   HighlightListViewModel.swift, AnnotationListViewModel.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx`

import SwiftUI
import SwiftData

/// The review annotations sheet — All / Highlights / Notes / Bookmarks.
struct HighlightsSheet: View {
    let bookFingerprintKey: String
    let modelContainer: ModelContainer
    /// The book's TOC — used to resolve each card's chapter label.
    /// Empty for books that ship no TOC; the card meta then degrades to
    /// the page (or nothing) per the design's graceful fallback.
    let tocEntries: [TOCEntry]
    let theme: ReaderThemeV2
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    // `@State` kept `internal` so the `+Export` / `+Support` extensions
    // can read it (the `+Sheets.swift` cross-file pattern).
    @State var activeFilter: HighlightsSheetFilter
    @State var highlightVM: HighlightListViewModel?
    @State var annotationVM: AnnotationListViewModel?
    @State var didLoad = false
    // Export flow state — driven by `HighlightsSheet+Export.swift`.
    @State var isShowingExportShare = false
    @State var exportedFileURL: URL?
    @State var exportMessage: String?

    init(
        bookFingerprintKey: String,
        modelContainer: ModelContainer,
        tocEntries: [TOCEntry] = [],
        theme: ReaderThemeV2,
        initialFilter: HighlightsSheetFilter = .all,
        onNavigate: @escaping (Locator) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.modelContainer = modelContainer
        self.tocEntries = tocEntries
        self.theme = theme
        self.onNavigate = onNavigate
        self.onDismiss = onDismiss
        self._activeFilter = State(initialValue: initialFilter)
    }

    // MARK: - Body

    var body: some View {
        ReaderSheetChrome(
            theme: theme,
            title: "Annotations",
            onClose: onDismiss,
            trailing: { exportButton }
        ) {
            VStack(spacing: 0) {
                filterChipRow
                ScrollView {
                    streamBody
                }
            }
        }
        .task {
            guard highlightVM == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let hVM = HighlightListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence,
                totalTextLengthUTF16: nil
            )
            let aVM = AnnotationListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
            await hVM.loadHighlights()
            await aVM.loadAnnotations()
            highlightVM = hVM
            annotationVM = aVM
            didLoad = true
        }
        .sheet(isPresented: $isShowingExportShare) {
            if let url = exportedFileURL {
                ShareActivityView(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
        .alert(
            "Export",
            isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("highlightsSheet")
    }

    // MARK: - Export button (the sole trailing affordance)

    /// The designed Share/export button — `HighlightsSheetV3`'s trailing
    /// slot is exactly one Share button (round-2 finding 2). The import
    /// affordance is deferred to needs-design #963.
    ///
    /// The label is sized to a 44×44pt tap target via `.frame` +
    /// `.contentShape` — the designed 16pt icon stays visually
    /// unchanged, only the hit area meets the HIG / accessibility-audit
    /// minimum (the bare 16pt glyph is otherwise an undersized target).
    @ViewBuilder
    private var exportButton: some View {
        Button {
            Task { await exportAnnotations() }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(theme.accentColor))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Share annotations")
        .accessibilityIdentifier("annotationsExportButton")
    }

    // MARK: - Filter chips

    @ViewBuilder
    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HighlightsSheetFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func filterChip(_ filter: HighlightsSheetFilter) -> some View {
        let isActive = filter == activeFilter
        Button {
            activeFilter = filter
        } label: {
            HStack(spacing: 6) {
                Text(filter.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Text("\(filterCounts[filter] ?? 0)")
                    .font(.system(size: 10.5))
                    .opacity(0.7)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(
                            isActive
                                ? Color.black.opacity(theme.isDark ? 0.18 : 0.0)
                                : Color.clear
                        )
                    )
            }
            .foregroundStyle(chipForeground(isActive: isActive))
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(chipBackground(isActive: isActive))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("highlightsSheetFilter\(filter.rawValue)")
    }

    private func chipForeground(isActive: Bool) -> Color {
        if isActive {
            return theme.isDark
                ? Color(red: 0x1a / 255, green: 0x18 / 255, blue: 0x15 / 255)
                : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255)
        }
        return Color(theme.inkColor)
    }

    private func chipBackground(isActive: Bool) -> Color {
        if isActive { return Color(theme.inkColor) }
        return Color.primary.opacity(theme.isDark ? 0.06 : 0.04)
    }

    // MARK: - Card stream body

    @ViewBuilder
    private var streamBody: some View {
        let stream = currentStream
        if !stream.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(stream) { item in
                    card(for: item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        } else if didLoad {
            AnnotationsEmptyStateView(
                theme: theme,
                accessibilityIdentifier: emptyStateIdentifier,
                art: AnyView(EmptyHighlightsArt(theme: theme)),
                title: emptyTitle(activeFilter),
                body: emptyBody(activeFilter)
            )
        } else {
            Color.clear.frame(height: 1)
        }
    }

    @ViewBuilder
    private func card(for item: AnnotationStreamItem) -> some View {
        switch item {
        case .highlight(let record):
            HighlightCardV3(
                theme: theme,
                highlight: record,
                metaLabel: metaLabel(for: record.locator),
                onJump: { onNavigate($0); onDismiss() }
            )
            .accessibilityIdentifier("highlightCard-\(record.highlightId)")
        case .standalone(let record):
            StandaloneNoteCard(
                theme: theme,
                note: record,
                metaLabel: metaLabel(for: record.locator),
                onJump: { onNavigate($0); onDismiss() }
            )
            .accessibilityIdentifier("standaloneNoteCard-\(record.annotationId)")
        }
    }
}
