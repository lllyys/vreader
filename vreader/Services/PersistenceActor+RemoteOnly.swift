// Purpose: Extension adding fileState/blobPath query + mutation helpers
// used by the lazy-download coordinator (#47 WI-3) and the selective
// restore flow (#47 WI-4). Lives next to PersistenceActor so it can read
// `modelContainer` directly without exposing it more widely.
//
// @coordinates-with: PersistenceActor.swift, Book.swift, BookFileState.swift,
//   LazyDownloadCoordinator.swift (future, WI-3b reattach),
//   SelectiveRestoreCoordinator.swift (future, WI-4b)

import Foundation
import SwiftData

extension PersistenceActor {

    /// Returns the fingerprint keys of all books currently in the given
    /// file-presence state. Used at coordinator init to find `.downloading`
    /// rows that crashed mid-flight (`reconcileDownloadingRowsAgainst`) and
    /// by selective-restore views to count outstanding remoteOnly books.
    func fingerprintKeys(withFileState state: BookFileState) async throws -> [String] {
        let context = ModelContext(modelContainer)
        let raw = state.rawValue
        let predicate = #Predicate<Book> { $0.fileState == raw }
        let descriptor = FetchDescriptor<Book>(predicate: predicate)
        return try context.fetch(descriptor).map { $0.fingerprintKey }
    }

    /// Updates the fileState for a single book. Used by the lazy-download
    /// coordinator on enqueue (`.remoteOnly` → `.downloading`),
    /// finalization (`.downloading` → `.local`), failure (`.downloading` →
    /// `.failed`), and reconciliation at launch.
    func setBookFileState(fingerprintKey key: String, newState: BookFileState) async throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let book = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound(key)
        }
        book.fileState = newState.rawValue
        try context.save()
    }

    /// Updates the blob path for a single book. Used by selective-restore
    /// when materializing remoteOnly rows from a backup manifest, and by
    /// the lazy-download finalizer when promoting `.downloading` → `.local`
    /// (which sets `blobPath` to nil — the bytes are now local).
    func setBlobPath(fingerprintKey key: String, blobPath: String?) async throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let book = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound(key)
        }
        book.blobPath = blobPath
        try context.save()
    }

    /// Bulk-inserts remoteOnly book records produced by the selective
    /// restore flow. Each record's `fileState` is forced to `.remoteOnly`
    /// regardless of what the caller passed — this method is the single
    /// entry point the catalog uses, so the invariant lives here.
    /// Idempotent: a record whose fingerprintKey already exists locally is
    /// left alone. We never downgrade an existing `.local` book to
    /// `.remoteOnly`.
    ///
    /// **Partial-success semantics**: each record is persisted in its own
    /// transaction (delegated to `insertBook`). If a later record throws —
    /// e.g. a fingerprintKey/canonical-key mismatch surfaced as
    /// `PersistenceError.invalidContent` — earlier records remain
    /// persisted. Callers that need all-or-nothing semantics must wrap
    /// this in their own validation pass before calling. This is acceptable
    /// for the selective-restore flow because the catalog validates the
    /// manifest before constructing records.
    func insertRemoteOnlyBookRecords(_ records: [BookRecord]) async throws {
        guard !records.isEmpty else { return }
        for record in records {
            let coerced = BookRecord(
                fingerprintKey: record.fingerprintKey,
                title: record.title,
                author: record.author,
                coverImagePath: record.coverImagePath,
                fingerprint: record.fingerprint,
                provenance: record.provenance,
                detectedEncoding: record.detectedEncoding,
                addedAt: record.addedAt,
                originalExtension: record.originalExtension,
                lastOpenedAt: record.lastOpenedAt,
                fileState: .remoteOnly,
                blobPath: record.blobPath
            )
            // insertBook is idempotent: returns existing local row unchanged
            // if the key collides. That preserves the don't-downgrade rule.
            _ = try await insertBook(coerced)
        }
    }
}
