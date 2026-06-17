// Purpose: Backup-only fetch/upsert helpers for entities that don't have a
// dedicated PersistenceActor extension elsewhere (BookSource, ContentReplacementRule),
// plus BackupBookProjection — a Sendable value-type view of Book for the
// library manifest (feature #46).
//
// These methods exist to keep the BackupDataCollector / BackupDataRestorer
// off raw ModelContext while preserving actor isolation.
//
// @coordinates-with: BackupDataCollector.swift, BackupDataRestorer.swift,
//   BookSource.swift, ContentReplacementRule.swift, Book.swift

import Foundation
import SwiftData

// MARK: - Library Manifest Projection (feature #46 WI-0a)

/// Sendable value-type projection of Book exposing the raw fingerprint fields
/// needed by BackupDataCollector.collectLibraryManifest. Avoids leaking
/// SwiftData @Model instances across the actor boundary.
///
/// `originalExtension` is non-optional in the projection: legacy rows missing
/// the field are coalesced to the canonical extension for their format
/// (e.g. all .azw3-formatted books default to "azw3").
struct BackupBookProjection: Sendable, Equatable {
    let fingerprintKey: String
    let format: String           // canonical BookFormat.rawValue
    let sha256: String
    let byteCount: Int64
    let originalExtension: String
    let title: String?
    let author: String?
    let addedAt: Date
    let lastOpenedAt: Date?
    /// Feature #47 WI-2: file-presence state for selective-restore /
    /// lazy-download UI. Defaults to `.local` for V5-era rows that pre-date
    /// SchemaV6 (the migration writes `"local"`).
    let fileState: BookFileState
    /// Server-side blob path when known (feature #47). Nil for `.local` rows
    /// that have never been uploaded; populated for `.remoteOnly` rows.
    let blobPath: String?
    /// Feature #108: converted-Kindle cross-platform canonical identity
    /// (`azw3:{sha256_of_source}:{bytes}`). Nil for native / non-Kindle / pre-#108
    /// books. Carried in the manifest so cross-device + Android restore can dedup
    /// on the source identity.
    var sourceCanonicalKey: String? = nil
}

extension PersistenceActor {

    // MARK: - Library Manifest

    /// Returns every Book as a BackupBookProjection, sorted by fingerprintKey
    /// for deterministic output across runs. Used by feature #46's
    /// BackupDataCollector to emit `library-manifest.json` without leaking
    /// @Model instances across the actor boundary.
    func fetchAllBooksForBackup() throws -> [BackupBookProjection] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.fingerprintKey)]
        )
        let books = try context.fetch(descriptor)
        return books.map { book in
            // Coalesce nil originalExtension (legacy V4 rows) to the canonical
            // extension for the format. Avoids forcing every consumer to
            // handle the optional separately.
            let canonicalExt = BookFormat(rawValue: book.format)?.fileExtensions.first ?? book.format
            return BackupBookProjection(
                fingerprintKey: book.fingerprintKey,
                format: book.format,
                sha256: book.fingerprint.contentSHA256,
                byteCount: book.fingerprint.fileByteCount,
                originalExtension: book.originalExtension ?? canonicalExt,
                title: book.title,
                author: book.author,
                addedAt: book.addedAt,
                lastOpenedAt: book.lastOpenedAt,
                fileState: BookFileState(rawValue: book.fileState) ?? .local,
                blobPath: book.blobPath,
                sourceCanonicalKey: book.sourceCanonicalKey
            )
        }
    }

    // MARK: - Book Sources

    /// Returns every BookSource as backup-friendly value records, sorted by customOrder.
    func fetchAllBackupBookSources() -> [BackupBookSource] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<BookSource>(
            sortBy: [SortDescriptor(\.customOrder)]
        )
        guard let sources = try? context.fetch(descriptor) else { return [] }
        return sources.map { src in
            BackupBookSource(
                sourceURL: src.sourceURL,
                sourceName: src.sourceName,
                sourceGroup: src.sourceGroup,
                sourceType: src.sourceType,
                enabled: src.enabled,
                searchURL: src.searchURL,
                header: src.header,
                ruleSearchData: src.ruleSearchData,
                ruleBookInfoData: src.ruleBookInfoData,
                ruleTocData: src.ruleTocData,
                ruleContentData: src.ruleContentData,
                compatibilityLevel: src.compatibilityLevel,
                lastUpdateTime: src.lastUpdateTime,
                customOrder: src.customOrder
            )
        }
    }

    /// Inserts or updates BookSources from a backup, keyed on sourceURL.
    /// Existing entries are updated in place; missing ones are created.
    func upsertBackupBookSources(_ sources: [BackupBookSource]) throws {
        let context = ModelContext(modelContainer)
        let existing = try context.fetch(FetchDescriptor<BookSource>())
        var byURL: [String: BookSource] = [:]
        for s in existing { byURL[s.sourceURL] = s }

        for incoming in sources {
            if let existing = byURL[incoming.sourceURL] {
                existing.sourceName = incoming.sourceName
                existing.sourceGroup = incoming.sourceGroup
                existing.sourceType = incoming.sourceType
                existing.enabled = incoming.enabled
                existing.searchURL = incoming.searchURL
                existing.header = incoming.header
                existing.ruleSearchData = incoming.ruleSearchData
                existing.ruleBookInfoData = incoming.ruleBookInfoData
                existing.ruleTocData = incoming.ruleTocData
                existing.ruleContentData = incoming.ruleContentData
                existing.compatibilityLevel = incoming.compatibilityLevel
                existing.lastUpdateTime = incoming.lastUpdateTime
                existing.customOrder = incoming.customOrder
            } else {
                let src = BookSource(
                    sourceURL: incoming.sourceURL,
                    sourceName: incoming.sourceName,
                    sourceGroup: incoming.sourceGroup,
                    sourceType: incoming.sourceType,
                    enabled: incoming.enabled,
                    searchURL: incoming.searchURL,
                    header: incoming.header,
                    customOrder: incoming.customOrder
                )
                src.ruleSearchData = incoming.ruleSearchData
                src.ruleBookInfoData = incoming.ruleBookInfoData
                src.ruleTocData = incoming.ruleTocData
                src.ruleContentData = incoming.ruleContentData
                src.compatibilityLevel = incoming.compatibilityLevel
                src.lastUpdateTime = incoming.lastUpdateTime
                context.insert(src)
            }
        }
        try context.save()
    }

    // MARK: - Replacement Rules

    /// Returns every ContentReplacementRule as backup-friendly value records.
    func fetchAllBackupReplacementRules() -> [BackupReplacementRule] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ContentReplacementRule>(
            sortBy: [SortDescriptor(\.order)]
        )
        guard let rules = try? context.fetch(descriptor) else { return [] }
        return rules.map { r in
            BackupReplacementRule(
                ruleId: r.ruleId,
                pattern: r.pattern,
                replacement: r.replacement,
                isRegex: r.isRegex,
                scopeKey: r.scopeKey,
                enabled: r.enabled,
                order: r.order,
                label: r.label,
                createdAt: r.createdAt
            )
        }
    }

    /// Inserts or updates replacement rules from a backup, keyed on ruleId.
    func upsertBackupReplacementRules(_ rules: [BackupReplacementRule]) throws {
        let context = ModelContext(modelContainer)
        let existing = try context.fetch(FetchDescriptor<ContentReplacementRule>())
        var byId: [UUID: ContentReplacementRule] = [:]
        for r in existing { byId[r.ruleId] = r }

        for incoming in rules {
            if let existing = byId[incoming.ruleId] {
                existing.pattern = incoming.pattern
                existing.replacement = incoming.replacement
                existing.isRegex = incoming.isRegex
                existing.scopeKey = incoming.scopeKey
                existing.enabled = incoming.enabled
                existing.order = incoming.order
                existing.label = incoming.label
            } else {
                let rule = ContentReplacementRule(
                    ruleId: incoming.ruleId,
                    pattern: incoming.pattern,
                    replacement: incoming.replacement,
                    isRegex: incoming.isRegex,
                    scopeKey: incoming.scopeKey,
                    enabled: incoming.enabled,
                    order: incoming.order,
                    label: incoming.label,
                    createdAt: incoming.createdAt
                )
                context.insert(rule)
            }
        }
        try context.save()
    }

    // MARK: - Restore Helpers (other sections)

    /// Restores reading positions for known books. Skips entries whose book is missing.
    func restoreBackupPositions(_ positions: [BackupPosition]) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for entry in positions {
            guard let data = entry.locatorJSON.data(using: .utf8),
                  let locator = try? decoder.decode(Locator.self, from: data),
                  locator.bookFingerprint.canonicalKey == entry.bookFingerprintKey
            else { continue }
            // Skip if book missing — savePosition fails loudly otherwise.
            guard try await findBook(byFingerprintKey: entry.bookFingerprintKey) != nil else {
                continue
            }
            try await savePosition(
                bookFingerprintKey: entry.bookFingerprintKey,
                locator: locator,
                deviceId: ""
            )
            if let last = entry.lastOpenedAt {
                try? await updateLastOpened(bookFingerprintKey: entry.bookFingerprintKey, date: last)
            }
        }
    }

    /// Restores collections by recreating each name and re-attaching books.
    /// Existing collections with the same name are left intact (no-op rename).
    func restoreBackupCollections(_ collections: [BackupCollection]) async throws {
        let context = ModelContext(modelContainer)
        let existing = try context.fetch(FetchDescriptor<BookCollection>())
        var byName: [String: BookCollection] = [:]
        for c in existing { byName[c.name] = c }

        for incoming in collections {
            let collection: BookCollection
            if let existing = byName[incoming.name] {
                collection = existing
            } else {
                collection = BookCollection(name: incoming.name, createdAt: incoming.createdAt)
                context.insert(collection)
            }
            // Attach books that exist locally and aren't already members.
            for key in incoming.bookFingerprintKeys {
                let predicate = #Predicate<Book> { $0.fingerprintKey == key }
                var bd = FetchDescriptor<Book>(predicate: predicate)
                bd.fetchLimit = 1
                guard let book = try context.fetch(bd).first else { continue }
                if !collection.books.contains(where: { $0.fingerprintKey == key }) {
                    collection.books.append(book)
                }
            }
        }
        try context.save()
    }

    /// Restores annotations (highlights/bookmarks/notes). Books that no longer
    /// exist are skipped. Preserves the original UUIDs and timestamps so a
    /// restored archive doesn't fork the sync identity of each annotation.
    /// Re-running a restore against the same target is idempotent.
    ///
    /// Dedupe order:
    /// 1. Match by backed-up UUID (sync-identity preservation).
    /// 2. Otherwise match by `(profileKey, anchorHash)` — same reader location.
    ///    This prevents a restored archive from re-introducing a duplicate at
    ///    the same anchor that was previously created locally with a different
    ///    UUID (e.g. via the live `addHighlight` path that mints fresh ids).
    /// 3. Otherwise insert a new row with the backed-up UUID/createdAt/updatedAt.
    ///
    /// In all matched cases every restorable field (locator, anchor, payload,
    /// timestamps, book attachment) is rewritten from the backup so a repaired
    /// archive can fix wrong local state.
    func restoreBackupAnnotations(_ envelope: BackupAnnotationsEnvelope) async throws {
        let context = ModelContext(modelContainer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let existingHighlights = try context.fetch(FetchDescriptor<Highlight>())
        var highlightById: [UUID: Highlight] = [:]
        var highlightByProfile: [String: Highlight] = [:]
        for h in existingHighlights {
            highlightById[h.highlightId] = h
            highlightByProfile[h.profileKey] = h
        }

        let existingBookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        var bookmarkById: [UUID: Bookmark] = [:]
        var bookmarkByProfile: [String: Bookmark] = [:]
        for b in existingBookmarks {
            bookmarkById[b.bookmarkId] = b
            bookmarkByProfile[b.profileKey] = b
        }

        let existingNotes = try context.fetch(FetchDescriptor<AnnotationNote>())
        var noteById: [UUID: AnnotationNote] = [:]
        for n in existingNotes { noteById[n.annotationId] = n }

        for h in envelope.highlights {
            guard let book = try fetchBook(context: context, key: h.bookFingerprintKey) else { continue }
            guard let locator = decodeLocator(from: h.locatorJSON, expectedKey: h.bookFingerprintKey, decoder: decoder)
            else { continue }
            let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
            if let existing = highlightById[h.highlightId] ?? highlightByProfile[profileKey] {
                let oldId = existing.highlightId
                let oldProfileKey = existing.profileKey
                applyHighlightUpdate(existing, from: h, locator: locator, book: book)
                // Adopt the backup's UUID on profile-key match so the row keeps
                // a single sync identity going forward. The old UUID isn't
                // unique-locked elsewhere — `existing` was the only carrier.
                if existing.highlightId != h.highlightId {
                    existing.highlightId = h.highlightId
                    highlightById.removeValue(forKey: oldId)
                }
                if oldProfileKey != existing.profileKey {
                    highlightByProfile.removeValue(forKey: oldProfileKey)
                }
                highlightById[h.highlightId] = existing
                highlightByProfile[existing.profileKey] = existing
                continue
            }
            let highlight = Highlight(
                highlightId: h.highlightId,
                locator: locator,
                selectedText: h.selectedText,
                color: h.color,
                note: h.note,
                anchor: nil,
                createdAt: h.createdAt
            )
            highlight.updatedAt = h.updatedAt
            highlight.book = book
            book.highlights.append(highlight)
            context.insert(highlight)
            highlightById[h.highlightId] = highlight
            highlightByProfile[profileKey] = highlight
        }

        for b in envelope.bookmarks {
            guard let book = try fetchBook(context: context, key: b.bookFingerprintKey) else { continue }
            guard let locator = decodeLocator(from: b.locatorJSON, expectedKey: b.bookFingerprintKey, decoder: decoder)
            else { continue }
            let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
            if let existing = bookmarkById[b.bookmarkId] ?? bookmarkByProfile[profileKey] {
                let oldId = existing.bookmarkId
                let oldProfileKey = existing.profileKey
                applyBookmarkUpdate(existing, from: b, locator: locator, book: book)
                if existing.bookmarkId != b.bookmarkId {
                    existing.bookmarkId = b.bookmarkId
                    bookmarkById.removeValue(forKey: oldId)
                }
                if oldProfileKey != existing.profileKey {
                    bookmarkByProfile.removeValue(forKey: oldProfileKey)
                }
                bookmarkById[b.bookmarkId] = existing
                bookmarkByProfile[existing.profileKey] = existing
                continue
            }
            let bookmark = Bookmark(
                bookmarkId: b.bookmarkId,
                locator: locator,
                title: b.title,
                createdAt: b.createdAt
            )
            bookmark.updatedAt = b.updatedAt
            bookmark.book = book
            book.bookmarks.append(bookmark)
            context.insert(bookmark)
            bookmarkById[b.bookmarkId] = bookmark
            bookmarkByProfile[profileKey] = bookmark
        }

        // Notes have no profileKey-based dedupe in the live path, so UUID is
        // the only identity. Same-content notes added later via the live API
        // get unique UUIDs and stay distinct.
        for n in envelope.notes {
            guard let book = try fetchBook(context: context, key: n.bookFingerprintKey) else { continue }
            guard let locator = decodeLocator(from: n.locatorJSON, expectedKey: n.bookFingerprintKey, decoder: decoder)
            else { continue }
            if let existing = noteById[n.annotationId] {
                applyNoteUpdate(existing, from: n, locator: locator, book: book)
                continue
            }
            let note = AnnotationNote(
                annotationId: n.annotationId,
                locator: locator,
                content: n.content,
                createdAt: n.createdAt
            )
            note.updatedAt = n.updatedAt
            note.book = book
            book.annotations.append(note)
            context.insert(note)
            noteById[n.annotationId] = note
        }

        try context.save()
    }

    private func applyHighlightUpdate(_ row: Highlight, from h: BackupHighlight, locator: Locator, book: Book) {
        row.updateLocator(locator)
        row.selectedText = h.selectedText
        row.color = h.color
        row.note = h.note
        row.createdAt = h.createdAt
        row.updatedAt = h.updatedAt
        if row.book?.fingerprintKey != book.fingerprintKey {
            row.book = book
        }
    }

    private func applyBookmarkUpdate(_ row: Bookmark, from b: BackupBookmark, locator: Locator, book: Book) {
        row.updateLocator(locator)
        row.title = b.title
        row.createdAt = b.createdAt
        row.updatedAt = b.updatedAt
        if row.book?.fingerprintKey != book.fingerprintKey {
            row.book = book
        }
    }

    private func applyNoteUpdate(_ row: AnnotationNote, from n: BackupNote, locator: Locator, book: Book) {
        row.updateLocator(locator)
        row.content = n.content
        row.createdAt = n.createdAt
        row.updatedAt = n.updatedAt
        if row.book?.fingerprintKey != book.fingerprintKey {
            row.book = book
        }
    }

    // MARK: - Private helpers

    private func fetchBook(context: ModelContext, key: String) throws -> Book? {
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func decodeLocator(
        from json: String, expectedKey: String, decoder: JSONDecoder
    ) -> Locator? {
        guard let data = json.data(using: .utf8),
              let locator = try? decoder.decode(Locator.self, from: data),
              locator.bookFingerprint.canonicalKey == expectedKey
        else { return nil }
        // #109 WI-2 / #356: a backup authored by a pre-fix build may carry a
        // non-finite (invalid) locator — repair it on the way in so restore never
        // re-introduces an invalid row.
        return locator.repairedForCanonicalization()
    }
}
