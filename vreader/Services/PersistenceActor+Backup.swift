// Purpose: Backup-only fetch/upsert helpers for entities that don't have a
// dedicated PersistenceActor extension elsewhere (BookSource, ContentReplacementRule).
//
// These methods exist to keep the BackupDataCollector / BackupDataRestorer
// off raw ModelContext while preserving actor isolation.
//
// @coordinates-with: BackupDataCollector.swift, BackupDataRestorer.swift,
//   BookSource.swift, ContentReplacementRule.swift

import Foundation
import SwiftData

extension PersistenceActor {

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
    func restoreBackupAnnotations(_ envelope: BackupAnnotationsEnvelope) async throws {
        let context = ModelContext(modelContainer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Pre-fetch existing rows so we can upsert keyed by backed-up UUID.
        let existingHighlights = try context.fetch(FetchDescriptor<Highlight>())
        var highlightById: [UUID: Highlight] = [:]
        for h in existingHighlights { highlightById[h.highlightId] = h }
        let existingBookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        var bookmarkById: [UUID: Bookmark] = [:]
        for b in existingBookmarks { bookmarkById[b.bookmarkId] = b }
        let existingNotes = try context.fetch(FetchDescriptor<AnnotationNote>())
        var noteById: [UUID: AnnotationNote] = [:]
        for n in existingNotes { noteById[n.annotationId] = n }

        for h in envelope.highlights {
            guard let book = try fetchBook(context: context, key: h.bookFingerprintKey) else { continue }
            guard let locator = decodeLocator(from: h.locatorJSON, expectedKey: h.bookFingerprintKey, decoder: decoder)
            else { continue }
            if let existing = highlightById[h.highlightId] {
                existing.color = h.color
                existing.note = h.note
                existing.updatedAt = h.updatedAt
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
        }

        for b in envelope.bookmarks {
            guard let book = try fetchBook(context: context, key: b.bookFingerprintKey) else { continue }
            guard let locator = decodeLocator(from: b.locatorJSON, expectedKey: b.bookFingerprintKey, decoder: decoder)
            else { continue }
            if let existing = bookmarkById[b.bookmarkId] {
                existing.title = b.title
                existing.updatedAt = b.updatedAt
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
        }

        for n in envelope.notes {
            guard let book = try fetchBook(context: context, key: n.bookFingerprintKey) else { continue }
            guard let locator = decodeLocator(from: n.locatorJSON, expectedKey: n.bookFingerprintKey, decoder: decoder)
            else { continue }
            if let existing = noteById[n.annotationId] {
                existing.content = n.content
                existing.updatedAt = n.updatedAt
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
        }

        try context.save()
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
        return locator
    }
}
