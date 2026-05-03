# Phase C Implementation Plan (Forward)

**Date**: 2026-03-17
**Status**: FORWARD — 4 WIs planned
**Scope**: Library organization — collections, annotation export/import, OPDS

---

## WI-C01: #34 Collections / Tags / Series

**Problem**: Users with large libraries (100+ books) need organization beyond flat list. Collections (user-created folders), tags (labels), and series (ordered book groups) enable this.

**Files to create/modify**:
- Create: `vreader/Models/Collection.swift` — SwiftData @Model (separate entity with name, createdAt, books relationship)
- Create: `vreader/Services/PersistenceActor+Collections.swift`
- Create: `vreaderTests/Models/CollectionTests.swift`
- Create: `vreaderTests/Services/PersistenceActor+CollectionsTests.swift`
- Modify: `vreader/Models/Book.swift` — add inline fields: `tags: [String]`, `seriesName: String?`, `seriesIndex: Int?`
- Modify: `vreader/Views/Library/LibraryView.swift` — add collection filter sidebar
- Modify: `vreader/Services/PersistenceActor+Library.swift` — collection queries

**Model approach (inline, no separate entities for tags/series)**:
- **Tags**: Stored as `[String]` directly on Book. No separate BookTag entity. Simple, searchable via predicates.
- **Series**: Stored as `seriesName: String?` and `seriesIndex: Int?` directly on Book. No separate Series entity. Series grouping is a query over books sharing the same seriesName.
- **Collection**: Remains a separate @Model with a many-to-many relationship to Book (user-created folders need their own identity, creation date, and ordering).

**Tests FIRST**:
- `testCreateCollection_savesAndRetrievals`
- `testDeleteCollection_removesButKeepsBooks`
- `testRenameCollection_updatesAllReferences`
- `testAddBookToCollection_bidirectionalLink`
- `testRemoveBookFromCollection_preservesBook`
- `testBookInMultipleCollections_allowed`
- `testEmptyCollectionName_rejected`
- `testDuplicateCollectionName_rejected`
- `testCollectionSort_byName`
- `testBookTags_addRemoveQuery`
- `testTagSearch_filtersByTag`
- `testSeries_orderedBySeriesIndex`
- `testSeries_gapInIndex_handled`
- `testSeries_sameName_differentBooks`
- `testDeleteBook_removesFromCollections`

**Implementation approach**:
1. Collection as @Model with name, createdAt, books relationship (separate entity)
2. Tags stored as `[String]` on Book model (inline, no separate entity)
3. Series modeled as `(seriesName: String?, seriesIndex: Int?)` on Book (inline, no separate entity)
4. PersistenceActor+Collections handles CRUD
5. LibraryView gets a sidebar section for collections/tags filtering
6. "All Books" remains default, collections are optional filters

**Edge cases**: Empty collection name, duplicate names, book in 0 collections, deleting a book that's in collections, Unicode collection names, very long names (truncation).

**Acceptance criteria**: Users can create/rename/delete collections. Books can be added to multiple collections. Tag filtering works. Series groups books in order. Existing library behavior unchanged for users who don't use collections.

**Dependencies**: None.

**Cross-phase note**: C01 data (collections, tags, series) must be included in Phase E backup/sync scope. E01 (WebDAV) and E02 (iCloud) archive contents must cover these fields. See E01 backup scope for the full list.

**Effort**: M

---

## WI-C02: #35 Export Annotations (Markdown/JSON/PDF)

**Problem**: Users need to export highlights and notes for use outside VReader — sharing, backup, academic citation, integration with other tools.

**Files to create/modify**:
- Create: `vreader/Services/Export/AnnotationExporter.swift`
- Create: `vreader/Services/Export/MarkdownExportFormatter.swift`
- Create: `vreader/Services/Export/JSONExportFormatter.swift`
- Create: `vreader/Services/Export/PDFExportFormatter.swift`
- Create: `vreaderTests/Services/Export/AnnotationExporterTests.swift`
- Create: `vreaderTests/Services/Export/MarkdownExportFormatterTests.swift`
- Create: `vreaderTests/Services/Export/JSONExportFormatterTests.swift`
- Modify: `vreader/Views/Reader/AnnotationsPanelView.swift` — add export button

**Tests FIRST**:
- `testMarkdownExport_includesBookTitle`
- `testMarkdownExport_highlightsGroupedByChapter`
- `testMarkdownExport_notesIncluded`
- `testMarkdownExport_bookmarksIncluded`
- `testMarkdownExport_emptyAnnotations_producesMinimalOutput`
- `testJSONExport_validJSON`
- `testJSONExport_roundTrippable` (can be imported back)
- `testJSONExport_includesAllFields`
- `testJSONExport_dateFormat_ISO8601`
- `testPDFExport_generatesValidPDF`
- `testPDFExport_multiplePages_paginatesCorrectly`
- `testPDFExport_includesHighlightColor`
- `testExportFormat_enum_codable`
- `testExport_unicodeContent_preserved`
- `testExport_CJKText_correct`
- `testExport_longNote_notTruncated`

**Implementation approach**:
1. AnnotationExporter protocol with `export(annotations:format:) -> Data`
2. Three formatters: Markdown (.md), JSON (.json), PDF (.pdf via UIGraphicsPDFRenderer)
3. Markdown format: `# Book Title\n\n## Chapter 1\n\n> highlight text\n\n*Note: user note*\n`
4. JSON format: Array of `ExportedAnnotation` objects with ISO 8601 dates
5. PDF: Multi-page layout via UIGraphicsPDFRenderer. Each chapter starts a new page. Content that exceeds a single page paginates automatically (track remaining height, begin new page when exceeded). Page numbers in footer.
6. Export via UIActivityViewController (share sheet)

**Edge cases**: Book with 0 annotations (empty export), annotations without chapter (ungrouped section), very long highlight text (500+ chars), notes with markdown syntax, CJK text in PDF rendering.

**Acceptance criteria**: All three formats produce valid output. Markdown is human-readable. JSON can be re-imported (C03). PDF renders correctly. Share sheet works.

**Dependencies**: None.

**Effort**: M

---

## WI-C03: #35 Import Annotations

**Problem**: Users need to import annotations from VReader JSON exports (e.g., restoring from backup, migrating devices without iCloud).

**Scope (MVP)**: VReader JSON import only. This consumes the JSON format defined in C02. No third-party reader import in MVP.

**Stretch goal**: Kindle annotation import (My Clippings.txt parser) — deferred to a future WI.

**Files to create/modify**:
- Create: `vreader/Services/Import/AnnotationImporter.swift`
- Create: `vreader/Services/Import/VReaderAnnotationParser.swift`
- Create: `vreaderTests/Services/Import/AnnotationImporterTests.swift`
- Create: `vreaderTests/Services/Import/VReaderAnnotationParserTests.swift`
- Modify: `vreader/Views/Reader/AnnotationsPanelView.swift` — add import button

**Tests FIRST**:
- `testImportVReaderJSON_createsHighlights`
- `testImportVReaderJSON_createsBookmarks`
- `testImportVReaderJSON_createsNotes`
- `testImportVReaderJSON_duplicateId_skips`
- `testImportVReaderJSON_missingBook_createsOrphan`
- `testImportVReaderJSON_malformedJSON_returnsError`
- `testImportVReaderJSON_emptyArray_noOp`
- `testImportVReaderJSON_futureFields_ignored`
- `testImportVReaderJSON_datesParsed_ISO8601`
- `testImportProgress_reportsCorrectly`

**Implementation approach**:
1. VReaderAnnotationParser consumes JSON format defined in C02
2. Import deduplicates by annotation ID (UUID) — skip if exists
3. Import resolves book by fingerprintKey — creates orphan bucket if book not in library
4. Uses PersistenceActor for writes (transactional)
5. Progress callback during import
6. File picker via UIDocumentPickerViewController

**Edge cases**: Import file from newer app version (unknown fields), import into library where book was deleted, duplicate IDs with different content (skip, don't overwrite), zero-byte file, corrupt JSON.

**Acceptance criteria**: VReader JSON round-trips (export then import produces identical annotations). Duplicates are skipped. Missing books handled gracefully. Error messages are user-friendly.

**Dependencies**: WI-C02 (JSON export format must be defined first).

**Effort**: M

---

## WI-C04: #36 OPDS Catalog Support

**Problem**: OPDS (Open Publication Distribution System) is a standard for browsing and downloading ebooks from catalog servers. Enables users to discover and import books from online libraries without manual file transfer.

**Files to create/modify**:
- Create: `vreader/Services/OPDS/OPDSClient.swift` — HTTP client for OPDS feeds
- Create: `vreader/Services/OPDS/OPDSParser.swift` — Atom XML feed parser
- Create: `vreader/Services/OPDS/OPDSCatalog.swift` — model (Feed, Entry, Link)
- Create: `vreader/Views/OPDS/OPDSBrowserView.swift` — catalog browser UI
- Create: `vreader/Views/OPDS/OPDSEntryView.swift` — book detail from catalog
- Create: `vreaderTests/Services/OPDS/OPDSParserTests.swift`
- Create: `vreaderTests/Services/OPDS/OPDSClientTests.swift`
- Modify: `vreader/Views/Library/LibraryView.swift` — add OPDS catalog button

**Tests FIRST**:
- `testParseNavigationFeed_extractsEntries`
- `testParseAcquisitionFeed_extractsDownloadLinks`
- `testParseSearchFeed_extractsSearchURL`
- `testParsePagination_extractsNextLink`
- `testParseEntry_extractsMetadata` (title, author, summary, cover)
- `testParseEntry_multipleFormats` (EPUB + PDF links)
- `testParseEntry_relativeAcquisitionURL_resolvedAgainstFeedBase`
- `testParseFeed_duplicateEntries_deduplicated`
- `testParseFeed_emptyFeed_returnsEmpty`
- `testParseFeed_invalidXML_returnsError`
- `testClient_fetchFeed_success`
- `testClient_fetchFeed_networkError`
- `testClient_downloadBook_savesToLibrary`
- `testClient_basicAuth_headerIncluded`
- `testOPDSURL_validation`
- `testCatalog_codableRoundTrip`

**Implementation approach**:
1. OPDS 1.2 spec: Atom XML feeds with `rel="http://opds-spec.org/..."` links
2. OPDSParser uses XMLParser (Foundation) — no external dependencies
3. Feed types: Navigation (browse categories), Acquisition (book listings), Search
4. OPDSCatalog stores saved catalog URLs in UserDefaults
5. Download triggers BookImporter.import() for acquired files
6. Support basic auth for private catalogs (store credentials in Keychain via KeychainService)

**Edge cases**: Catalogs with pagination (rel="next"), catalogs requiring auth, catalogs with unsupported formats (skip), slow catalogs (timeout), malformed XML, OPDS 2.0 (JSON) — detect and show error suggesting 1.2.

**Acceptance criteria**: Can add OPDS catalog URL, browse categories, search, download books. Downloaded books appear in library. Basic auth works. Pagination works.

**Dependencies**: None (parallel with C01, C02).

**Effort**: M

---

## Sprint Plan

**Sprint C1** (parallel): C01 (collections) + C02 (export) + C04 (OPDS) — 3 parallel.
**Sprint C2** (sequential after C02): C03 (import) — depends on C02 for format.

## Checkpoint Criteria

- Collections, tags, series all functional
- Annotations export to Markdown, JSON, PDF
- JSON import round-trips correctly
- OPDS catalog browsing and download works
- All existing tests pass

## Manual Testing

See `docs/manual-test-checklist.md` for phase-specific test items.
