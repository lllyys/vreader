// Purpose: Extension adding LibraryPersisting conformance to PersistenceActor.
// Provides library-specific queries: fetch all books with stats, delete book.
//
// @coordinates-with: PersistenceActor.swift, LibraryPersisting.swift, LibraryBookItem.swift

import Foundation
import SwiftData

extension PersistenceActor: LibraryPersisting {

    /// Fetches all books with their associated reading stats for library display.
    func fetchAllLibraryBooks() async throws -> [LibraryBookItem] {
        let context = ModelContext(modelContainer)

        let bookDescriptor = FetchDescriptor<Book>()
        let books = try context.fetch(bookDescriptor)

        // Fetch all reading stats in one query for efficiency.
        // If duplicates exist (data integrity issue), keep the first entry
        // for deterministic results.
        let statsDescriptor = FetchDescriptor<ReadingStats>()
        let allStats = try context.fetch(statsDescriptor)
        var statsByKey: [String: ReadingStats] = [:]
        for stat in allStats where statsByKey[stat.bookFingerprintKey] == nil {
            statsByKey[stat.bookFingerprintKey] = stat
        }

        return books.map { book in
            let stats = statsByKey[book.fingerprintKey]
            return LibraryBookItem(
                fingerprintKey: book.fingerprintKey,
                title: book.title,
                author: book.author,
                coverImagePath: book.coverImagePath,
                format: book.format,
                addedAt: book.addedAt,
                lastOpenedAt: book.lastOpenedAt,
                isFavorite: book.isFavorite,
                totalReadingSeconds: stats?.totalReadingSeconds ?? 0,
                lastReadAt: stats?.lastReadAt,
                averagePagesPerHour: stats?.averagePagesPerHour,
                averageWordsPerMinute: stats?.averageWordsPerMinute
            )
        }
    }

    /// Deletes a book and all associated data.
    /// SwiftData cascade delete rules handle related entities
    /// (readingPosition, bookmarks, highlights, annotations).
    /// ReadingStats and ReadingSessions are deleted explicitly since they
    /// use fingerprintKey reference rather than a SwiftData relationship.
    func deleteBook(fingerprintKey: String) async throws {
        let context = ModelContext(modelContainer)

        // Delete reading sessions for this book
        let sessionPredicate = #Predicate<ReadingSession> {
            $0.bookFingerprintKey == fingerprintKey
        }
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>(
            predicate: sessionPredicate
        ))
        for session in sessions {
            context.delete(session)
        }

        // Delete reading stats for this book
        let statsPredicate = #Predicate<ReadingStats> {
            $0.bookFingerprintKey == fingerprintKey
        }
        let stats = try context.fetch(FetchDescriptor<ReadingStats>(
            predicate: statsPredicate
        ))
        for stat in stats {
            context.delete(stat)
        }

        // Delete the book itself (cascade handles related entities)
        let bookPredicate = #Predicate<Book> { $0.fingerprintKey == fingerprintKey }
        var descriptor = FetchDescriptor<Book>(predicate: bookPredicate)
        descriptor.fetchLimit = 1

        if let book = try context.fetch(descriptor).first {
            context.delete(book)
        }

        try context.save()
    }
}
