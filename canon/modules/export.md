---
title: Module — export
updated: 2026-07-10
status: verified
---

# Module — export

## Purpose

Exports a book's annotations (highlights, bookmarks, standalone notes) as a shareable file in two formats — round-trippable JSON and human-readable Markdown — reached from the reader's `HighlightsSheet` Share button (feature #35, rehosted by feature #62 WI-4). A small, pure, formatter-per-format subsystem; feature #130's M-SHAKEDOWN batch used its formatters as a lane canary.

## Key files and types

- `vreader/Services/Export/AnnotationExporter.swift` (108 lines) — `enum ExportFormat: String, Codable, Sendable, CaseIterable { markdown, json }`; `protocol ExportFormatter: Sendable { func format(_ payload: AnnotationExportPayload) throws -> Data }`; `enum AnnotationExporter` with `static func buildPayload(highlights: [HighlightRecord], bookmarks: [BookmarkRecord], notes: [AnnotationRecord], bookTitle: String, bookAuthor: String?, chapterMap: [String: String] = [:]) -> AnnotationExportPayload` (maps each record's `locator.href` through `chapterMap` for chapter grouping) and `static func export(payload:format:) throws -> Data` dispatching to the concrete formatter.
- `vreader/Models/ExportedAnnotation.swift` — the DTOs: `enum ExportedAnnotationType { highlight, bookmark, note }`; `struct ExportedAnnotation: Codable, Sendable, Equatable` (id, type, chapter?, selectedText?, note?, color?, title?, createdAt, updatedAt); `struct AnnotationExportPayload` (bookTitle, bookAuthor?, exportedAt, annotations).
- `vreader/Services/Export/JSONExportFormatter.swift` (22 lines) — `struct JSONExportFormatter: ExportFormatter`: `JSONEncoder` with `.iso8601` dates and `[.prettyPrinted, .sortedKeys]` (deterministic, round-trippable output).
- `vreader/Services/Export/MarkdownExportFormatter.swift` (95 lines) — `struct MarkdownExportFormatter: ExportFormatter`: `# Title` / `*by Author*`, groups by chapter (`Dictionary(grouping:)` on `chapter ?? ""`), empty-chapter bucket renders as `## Ungrouped` and sorts LAST (custom key comparator); highlights render as `> text` blockquotes with `*Note: …*`, bookmarks as `- label`; empty payload emits `*No annotations.*`. Declares `enum ExportError { encodingFailed, invalidFormat }`.
- `vreader/Views/Reader/Annotations/HighlightsSheet+Export.swift` — the UI flow (feature #62 WI-4, moved byte-for-byte from the deleted `AnnotationsPanelView` of feature #35): `exportAnnotations() async` fetches highlights/bookmarks/notes from `PersistenceActor` (per-collection error tolerance — a failed fetch is skipped and reported as "Exported with warnings: skipped …"), builds the payload with `bookTitle: bookFingerprintKey`, exports as `.json`, writes `annotations-export.json` to the temp directory atomically, then presents the share sheet. The reverse path `importAnnotationsFrom(url:)` is RETAINED but UI-unreachable (the committed #860 design has no import affordance — deferral tracked as needs-design #963; a DEBUG `importForTesting(url:)` hook keeps `AnnotationImporter` exercised).

## Dependencies

Internal: `HighlightRecord` / `BookmarkRecord` / `AnnotationRecord` value DTOs and `PersistenceActor` fetches ([[Module — annotations and highlights]], [[Module — persistence and data model]]); `Locator.href` for chapter mapping ([[Module — locator]]); `ShareActivityView`/share-sheet plumbing in the reader. The import counterpart lives in `vreader/Services/Import/AnnotationImporter.swift` + `VReaderAnnotationParser.swift` ([[Module — import pipeline]]). External: Foundation only — no third-party formatter code.

## Data flow

HighlightsSheet Share button → `exportAnnotations()` → three `PersistenceActor` fetches (keyed by `bookFingerprintKey`) → `AnnotationExporter.buildPayload` flattens the three record types into one `[ExportedAnnotation]` (highlights carry selectedText/note/color; bookmarks carry title; notes carry content in the `note` field) → `AnnotationExporter.export(payload:format:)` → `Data` → temp file → system share sheet. The JSON output decodes back to the same payload (`.iso8601` both ways), which is what `AnnotationImporter.importJSON(data:bookFingerprintKey:)` consumes on the retained import path.

## Edge cases and invariants

- Deterministic output: sorted JSON keys; Markdown chapter sort places the ungrouped bucket last.
- Empty payload is valid (Markdown emits `*No annotations.*`; JSON emits an empty `annotations` array).
- Annotations without a chapter mapping (nil `href` or unmapped href) group under "Ungrouped" — chapter is optional by design.
- Partial fetch failure does not abort the export; the user gets the surviving categories plus a warning message (error channel renamed from the panel's shared `importMessage` — bug #130 in `docs/bugs.md`, distinct from feature #130).
- `Sendable` throughout — formatters and DTOs cross actor boundaries safely; formatting itself is pure (no I/O inside `format`).

## History

Feature #35 (Export / import annotations, VERIFIED 2026-05-13 — 47-test data-layer slice + `Feature35AnnotationsExportVerificationTests`); feature #62 WI-4 (export flow rehosted into `HighlightsSheet`; import UI deferred to needs-design #963 per Gate-2 round-2 finding 2, noted on GH #801); feature #130 M-SHAKEDOWN Lane B (PR #1895, commit `72a20293`) added direct-payload test coverage (`MarkdownExportFormatterTests`/`JSONExportFormatterTests`) to the existing `vreaderTests/Services/Export/AnnotationExporterTests.swift`, extending beyond the exporter-mediated `JSONExportTests.swift`/`MarkdownExportTests.swift` suites (feature #35) that already share `ExportTestFixtures.swift` — an intentionally small bash/Swift lane used to shake down the rule-55 dispatch harness ([[Decision — six-gate workflow and lane dispatch]]).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]. Artifacts consulted: vreader/Services/Export/AnnotationExporter.swift, vreader/Services/Export/JSONExportFormatter.swift, vreader/Services/Export/MarkdownExportFormatter.swift, vreader/Models/ExportedAnnotation.swift, vreader/Views/Reader/Annotations/HighlightsSheet+Export.swift, vreaderTests/Services/Export/ExportTestFixtures.swift, docs/features.md

**Verified.** 2026-07-11 — checked against: vreader/Services/Export/AnnotationExporter.swift, vreader/Services/Export/JSONExportFormatter.swift, vreader/Services/Export/MarkdownExportFormatter.swift, vreader/Models/ExportedAnnotation.swift, vreader/Views/Reader/Annotations/HighlightsSheet+Export.swift, vreader/Views/Library/ShareSheet.swift, vreader/Services/Import/AnnotationImporter.swift, vreader/Services/Import/VReaderAnnotationParser.swift, vreader/Services/HighlightRecord.swift, vreader/Services/BookmarkRecord.swift, vreader/Services/AnnotationRecord.swift, vreader/Models/Locator.swift, vreaderTests/Services/Export/AnnotationExporterTests.swift, vreaderTests/Services/Export/JSONExportTests.swift, vreaderTests/Services/Export/MarkdownExportTests.swift, vreaderTests/Services/Export/ExportTestFixtures.swift, vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift, docs/features.md, docs/bugs.md, dev-docs/plans/20260708-feature-130-agent-lane-harness.md, canon/modules/annotations-highlights.md, canon/modules/persistence-data-model.md, canon/modules/locator.md, canon/modules/import-pipeline.md, canon/decisions/six-gate-lane-dispatch.md
