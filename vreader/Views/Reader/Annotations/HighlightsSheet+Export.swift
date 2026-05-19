// Purpose: Feature #62 WI-4 — `HighlightsSheet`'s annotation export
// flow, plus the RETAINED-but-UI-deferred import flow.
//
// The export flow moves byte-for-byte from `AnnotationsPanelView`
// (feature #35 — `AnnotationExporter`, `ShareActivityView`, the
// `PersistenceActor` fetch methods are unchanged; only the host sheet
// changed). It is reached from `HighlightsSheet`'s designed Share
// button.
//
// **Import-deferral (Gate-2 round-2 finding 2 / needs-design #963)**:
// the committed #860 design has NO import affordance, so `HighlightsSheet`
// ships no `.fileImporter` UI and no import button. The
// `importAnnotationsFrom(url:)` method is RETAINED here as `private`,
// reachable-once-#963-lands code so the `AnnotationImporter` engine
// stays compiled + exercised by `AnnotationImporterTests` and #963's
// follow-up has it ready to wire. It is intentional, tracked dead code
// — NOT a silent drop (the #62 row + GH #801 note the deferral).
//
// @coordinates-with: HighlightsSheet.swift, AnnotationExporter.swift,
//   AnnotationImporter.swift, ShareActivityView.swift

import SwiftUI
import UniformTypeIdentifiers

extension HighlightsSheet {

    // MARK: - Export (feature #35 — moved verbatim from AnnotationsPanelView)

    /// Builds the annotation export JSON (highlights + bookmarks +
    /// standalone notes) and presents the system share sheet. Every step
    /// propagates errors so failures surface via the `exportMessage`
    /// alert (bug #130 — the same error-status channel, renamed from the
    /// panel's shared import/export `importMessage`).
    func exportAnnotations() async {
        let persistence = PersistenceActor(modelContainer: modelContainer)

        var fetchErrors: [String] = []
        let highlights: [HighlightRecord]
        do {
            highlights = try await persistence.fetchHighlights(forBookWithKey: bookFingerprintKey)
        } catch {
            fetchErrors.append("highlights")
            highlights = []
        }
        let bookmarks: [BookmarkRecord]
        do {
            bookmarks = try await persistence.fetchBookmarks(forBookWithKey: bookFingerprintKey)
        } catch {
            fetchErrors.append("bookmarks")
            bookmarks = []
        }
        let notes: [AnnotationRecord]
        do {
            notes = try await persistence.fetchAnnotations(forBookWithKey: bookFingerprintKey)
        } catch {
            fetchErrors.append("notes")
            notes = []
        }

        let payload = AnnotationExporter.buildPayload(
            highlights: highlights,
            bookmarks: bookmarks,
            notes: notes,
            bookTitle: bookFingerprintKey,
            bookAuthor: nil
        )

        let data: Data
        do {
            data = try AnnotationExporter.export(payload: payload, format: .json)
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("annotations-export.json")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            exportMessage = "Export failed: could not write temp file (\(error.localizedDescription))."
            return
        }

        exportedFileURL = tempURL
        if !fetchErrors.isEmpty {
            exportMessage = "Exported with warnings: skipped \(fetchErrors.joined(separator: ", ")) (fetch failed)."
        }
        isShowingExportShare = true
    }

    // MARK: - Import (UI deferred to needs-design #963)

    /// Imports an annotation `.json` file through the `AnnotationImporter`
    /// engine. **RETAINED but currently UNREACHABLE from the UI** — the
    /// committed #860 design has no import affordance, so `HighlightsSheet`
    /// ships no `.fileImporter` and no import button (Gate-2 round-2
    /// finding 2). This method keeps the importer engine compiled +
    /// exercised; needs-design #963 will wire it to a designed
    /// affordance. Intentional tracked dead code, kept `internal` (not
    /// `private`) so the DEBUG hook below — and #963's follow-up — can
    /// reach it without a dead-private-method warning.
    @MainActor
    func importAnnotationsFrom(url: URL) async -> String {
        guard url.startAccessingSecurityScopedResource() else {
            return "Could not access the file."
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            return "Could not read file."
        }

        let persistence = PersistenceActor(modelContainer: modelContainer)
        let importer = AnnotationImporter(
            highlightStore: persistence,
            bookmarkStore: persistence,
            annotationStore: persistence
        )

        do {
            let result = try await importer.importJSON(
                data: data,
                bookFingerprintKey: bookFingerprintKey
            )
            if result.importedCount > 0 {
                NotificationCenter.default.post(name: .readerHighlightsDidImport, object: nil)
            }
            return "Imported \(result.importedCount), skipped \(result.skippedCount)."
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Testing hooks

#if DEBUG
extension HighlightsSheet {
    /// Exercises the RETAINED-but-UI-deferred `importAnnotationsFrom`
    /// path so the `AnnotationImporter` engine stays covered while no
    /// import UI ships (needs-design #963). Returns the status string.
    func importForTesting(url: URL) async -> String {
        await importAnnotationsFrom(url: url)
    }
}
#endif
