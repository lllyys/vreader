// Purpose: Feature #62 WI-4 — pins `HighlightsSheet`'s composition.
//
// `HighlightsSheet` is the review half of the annotations-panel split —
// the All / Highlights / Notes / Bookmarks filter chips over a unified
// card stream (`HighlightCardV3` + `StandaloneNoteCard`). It wraps
// `ReaderSheetChrome` with `title: "Annotations"` and a single designed
// Share/export button in the trailing slot (the #860 `HighlightsSheetV3`
// design — no import affordance; that is deferred to needs-design #963).
//
// The contracts these tests guard: chrome title is exactly "Annotations";
// the trailing slot has exactly one (export) button, no import button;
// the filter chip set equals `HighlightsSheetFilter.allCases`; per-filter
// count badges come from `AnnotationStreamBuilder`; `initialFilter` seeds
// the active filter; the All stream interleaves both card kinds; empty
// states carry the filter-specific copy.
//
// @coordinates-with: HighlightsSheet.swift, HighlightsSheet+Export.swift,
//   HighlightAnnotationCard.swift, AnnotationStreamBuilder.swift,
//   AnnotationsEmptyStateView.swift, ReaderSheetChrome.swift

import Testing
import SwiftUI
import SwiftData
@testable import vreader

@Suite("Feature #62 — HighlightsSheet")
@MainActor
struct HighlightsSheetTests {

    // MARK: - Fixtures

    private func inMemoryContainer() -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func makeSheet(
        modelContainer: ModelContainer? = nil,
        theme: ReaderThemeV2 = .paper,
        initialFilter: HighlightsSheetFilter = .all,
        onNavigate: @escaping (Locator) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) -> HighlightsSheet {
        HighlightsSheet(
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            modelContainer: modelContainer ?? inMemoryContainer(),
            theme: theme,
            initialFilter: initialFilter,
            onNavigate: onNavigate,
            onDismiss: onDismiss
        )
    }

    /// Seeds a Book + a mixed set of highlights / annotations through the
    /// real persistence boundary, returns the book key + container.
    private func seedMixed() async throws -> (key: String, container: ModelContainer) {
        let container = inMemoryContainer()
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!
        // 2 highlights — one carries a note.
        _ = try await persistence.addHighlight(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch0.xhtml", progression: 0.1)!,
            selectedText: "passage one", color: "yellow", note: nil,
            toBookWithKey: key
        )
        _ = try await persistence.addHighlight(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch1.xhtml", progression: 0.2)!,
            selectedText: "passage two", color: "pink", note: "an annotated highlight",
            toBookWithKey: key
        )
        // 1 standalone annotation.
        _ = try await persistence.addAnnotation(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch2.xhtml", progression: 0.3)!,
            content: "a standalone note",
            toBookWithKey: key
        )
        return (key, container)
    }

    // MARK: - Builds + chrome

    @Test("Builds for every theme")
    func buildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            _ = makeSheet(theme: theme).body
        }
    }

    @Test("Chrome title is exactly 'Annotations'")
    func chromeTitleIsAnnotations() {
        #expect(makeSheet().sheetChromeTitleForTesting == "Annotations")
        // Must equal the #60 design contract.
        #expect(makeSheet().sheetChromeTitleForTesting == ReaderSheetKind.annotations.designTitle)
    }

    // MARK: - Trailing slot — export only, no import (needs-design #963)

    @Test("The trailing slot has exactly one (export) button — no import button")
    func trailingSlotIsExportOnly() {
        let sheet = makeSheet()
        #expect(sheet.trailingButtonCountForTesting == 1)
        #expect(sheet.hasExportButtonForTesting)
        #expect(sheet.hasImportButtonForTesting == false)
    }

    // MARK: - Filter chips

    @Test("The filter chip set equals HighlightsSheetFilter.allCases in design order")
    func filterChipsMatchAllCases() {
        #expect(makeSheet().filterChipsForTesting == HighlightsSheetFilter.allCases)
    }

    @Test("initialFilter seeds the active filter")
    func initialFilterSeedsActiveFilter() {
        #expect(makeSheet(initialFilter: .all).activeFilterForTesting == .all)
        #expect(makeSheet(initialFilter: .highlights).activeFilterForTesting == .highlights)
        #expect(makeSheet(initialFilter: .notes).activeFilterForTesting == .notes)
        #expect(makeSheet(initialFilter: .bookmarks).activeFilterForTesting == .bookmarks)
    }

    // MARK: - Count badges

    @Test("Per-filter count badges come from AnnotationStreamBuilder")
    func countBadgesFromStreamBuilder() async throws {
        let seed = try await seedMixed()
        let sheet = HighlightsSheet(
            bookFingerprintKey: seed.key, modelContainer: seed.container,
            theme: .paper, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
        let counts = await sheet.loadCountsForTesting()
        // 2 highlights + 1 standalone; 1 highlight is annotated.
        #expect(counts[.all] == 3)
        #expect(counts[.highlights] == 2)
        #expect(counts[.notes] == 2)    // 1 standalone + 1 annotated highlight
        #expect(counts[.bookmarks] == 0)
    }

    @Test("Zero counts render as 0 for every chip")
    func zeroCountsRenderZero() async {
        let sheet = makeSheet()
        let counts = await sheet.loadCountsForTesting()
        for filter in HighlightsSheetFilter.allCases {
            #expect(counts[filter] == 0)
        }
    }

    // MARK: - Unified card stream

    @Test("The All filter stream interleaves highlight cards and standalone-note cards")
    func allStreamInterleavesBothCardKinds() async throws {
        let seed = try await seedMixed()
        let sheet = HighlightsSheet(
            bookFingerprintKey: seed.key, modelContainer: seed.container,
            theme: .paper, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
        let stream = await sheet.loadStreamForTesting(filter: .all)
        #expect(stream.count == 3)
        let hasHighlight = stream.contains { if case .highlight = $0 { return true } else { return false } }
        let hasStandalone = stream.contains { if case .standalone = $0 { return true } else { return false } }
        #expect(hasHighlight)
        #expect(hasStandalone)
    }

    @Test("The Notes filter shows standalone notes + annotated highlights")
    func notesStreamShowsBothNoteKinds() async throws {
        let seed = try await seedMixed()
        let sheet = HighlightsSheet(
            bookFingerprintKey: seed.key, modelContainer: seed.container,
            theme: .paper, initialFilter: .notes,
            onNavigate: { _ in }, onDismiss: {}
        )
        let stream = await sheet.loadStreamForTesting(filter: .notes)
        // 1 standalone + 1 annotated highlight = 2.
        #expect(stream.count == 2)
    }

    @Test("The Highlights filter shows only highlight items")
    func highlightsStreamShowsOnlyHighlights() async throws {
        let seed = try await seedMixed()
        let sheet = HighlightsSheet(
            bookFingerprintKey: seed.key, modelContainer: seed.container,
            theme: .paper, initialFilter: .highlights,
            onNavigate: { _ in }, onDismiss: {}
        )
        let stream = await sheet.loadStreamForTesting(filter: .highlights)
        #expect(stream.count == 2)
        for item in stream {
            if case .highlight = item {} else {
                Issue.record("Highlights stream yielded a non-highlight item")
            }
        }
    }

    // MARK: - Empty states

    @Test("Empty All filter shows the empty state with the standalone-note hint copy")
    func emptyAllShowsEmptyState() async {
        let sheet = makeSheet(initialFilter: .all)
        let stream = await sheet.loadStreamForTesting(filter: .all)
        #expect(stream.isEmpty)
        #expect(sheet.emptyTitleForTesting(.all) == "No highlights or notes yet")
    }

    @Test("Empty Bookmarks filter shows the 'No bookmarks yet' empty state")
    func emptyBookmarksShowsEmptyState() async {
        // The Bookmarks chip is empty by design — the real bookmark
        // surface is TOCSheet's Bookmarks tab (round-1 finding 3).
        let sheet = makeSheet(initialFilter: .bookmarks)
        let stream = await sheet.loadStreamForTesting(filter: .bookmarks)
        #expect(stream.isEmpty)
        #expect(sheet.emptyTitleForTesting(.bookmarks) == "No bookmarks yet")
    }

    @Test("Each filter's empty state has a distinct title")
    func eachFilterEmptyTitleDistinct() {
        let sheet = makeSheet()
        let titles = HighlightsSheetFilter.allCases.map { sheet.emptyTitleForTesting($0) }
        #expect(Set(titles).count == HighlightsSheetFilter.allCases.count)
    }

    // MARK: - Card meta label (chapter · p. N)

    @Test("metaLabel resolves the chapter from tocEntries for a page-based locator")
    func metaLabelResolvesChapter() {
        let pdfFP = wi9PDFFingerprint
        let entries = [
            TOCEntry(title: "Prologue", level: 0, locator: makePDFLocator(fingerprint: pdfFP, page: 0)),
            TOCEntry(title: "Act Two", level: 0, locator: makePDFLocator(fingerprint: pdfFP, page: 10)),
        ]
        let sheet = HighlightsSheet(
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            modelContainer: inMemoryContainer(),
            tocEntries: entries, theme: .paper, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
        // A locator on page 12 is inside "Act Two"; display page 13.
        let label = sheet.metaLabel(for: makePDFLocator(fingerprint: pdfFP, page: 12))
        #expect(label.contains("Act Two"))
        #expect(label.contains("p. 13"))
    }

    @Test("metaLabel degrades to empty when no TOC and no page")
    func metaLabelDegradesWithoutTOC() {
        // EPUB locator (no page) + no TOC → empty meta, matching the
        // design's graceful fallback.
        let sheet = makeSheet()   // tocEntries default empty
        let label = sheet.metaLabel(
            for: makeEPUBLocator(href: "ch1.xhtml", progression: 0.3)
        )
        #expect(label.isEmpty)
    }

    // MARK: - Edges

    @Test("Builds with a large highlight set")
    func buildsWithLargeSet() async throws {
        let container = inMemoryContainer()
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!
        for i in 0..<200 {
            _ = try await persistence.addHighlight(
                locator: LocatorFactory.epub(fingerprint: fp, href: "ch\(i).xhtml", progression: 0.5)!,
                selectedText: "passage \(i)", color: "yellow", note: nil,
                toBookWithKey: key
            )
        }
        let sheet = HighlightsSheet(
            bookFingerprintKey: key, modelContainer: container,
            theme: .paper, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
        let counts = await sheet.loadCountsForTesting()
        #expect(counts[.all] == 200)
        _ = sheet.body
    }

    // MARK: - Import engine retained (UI deferred to needs-design #963)

    @Test("The retained import path actually drives AnnotationImporter.importJSON")
    func retainedImportEngineStillReachable() async throws {
        // HighlightsSheet ships NO import UI (round-2 finding 2 / #963),
        // but importAnnotationsFrom is retained so AnnotationImporter
        // stays covered. Prove the engine is genuinely reached: build a
        // valid export JSON, write it to a temp file, import it, and
        // assert the imported records actually landed in persistence.
        let container = inMemoryContainer()
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!

        // A valid annotation export payload — one highlight, one note.
        let exportPayload = AnnotationExporter.buildPayload(
            highlights: [
                HighlightRecord(
                    highlightId: UUID(),
                    locator: LocatorFactory.epub(fingerprint: fp, href: "ch0.xhtml", progression: 0.1)!,
                    anchor: nil, profileKey: "p", selectedText: "imported passage",
                    color: "yellow", note: nil, createdAt: Date(), updatedAt: Date()
                ),
            ],
            bookmarks: [],
            notes: [
                AnnotationRecord(
                    annotationId: UUID(),
                    locator: LocatorFactory.epub(fingerprint: fp, href: "ch1.xhtml", progression: 0.2)!,
                    profileKey: "p", content: "imported note",
                    createdAt: Date(), updatedAt: Date()
                ),
            ],
            bookTitle: key,
            bookAuthor: nil
        )
        let data = try AnnotationExporter.export(payload: exportPayload, format: .json)
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("f62-import-fixture-\(UUID()).json")
        try data.write(to: fixtureURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let sheet = HighlightsSheet(
            bookFingerprintKey: key, modelContainer: container,
            theme: .paper, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
        let status = await sheet.importForTesting(url: fixtureURL)
        // The status reports a successful import — the engine ran.
        #expect(status.contains("Imported"))

        // And the records actually landed in persistence — definitive
        // proof importJSON executed, not just that the method returned.
        let highlights = try await persistence.fetchHighlights(forBookWithKey: key)
        let notes = try await persistence.fetchAnnotations(forBookWithKey: key)
        #expect(highlights.count == 1)
        #expect(notes.count == 1)
    }

    @Test("Builds with CJK highlight text and note")
    func buildsWithCJKContent() async throws {
        let container = inMemoryContainer()
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!
        _ = try await persistence.addHighlight(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch0.xhtml", progression: 0.1)!,
            selectedText: "一段中文高亮", color: "green", note: "中文笔记",
            toBookWithKey: key
        )
        let sheet = HighlightsSheet(
            bookFingerprintKey: key, modelContainer: container,
            theme: .dark, initialFilter: .all,
            onNavigate: { _ in }, onDismiss: {}
        )
        let counts = await sheet.loadCountsForTesting()
        #expect(counts[.highlights] == 1)
        #expect(counts[.notes] == 1)
        _ = sheet.body
    }
}
