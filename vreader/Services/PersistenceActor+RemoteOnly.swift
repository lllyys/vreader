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

    /// Atomically promotes a `.remoteOnly` / `.downloading` row to `.local`
    /// AND clears `blobPath` in a single `ModelContext.save()`.
    ///
    /// Bug #118: `LazyDownloadFinalizer` previously called
    /// `setBookFileState(.local)` and `setBlobPath(nil)` in sequence; if
    /// the first save committed and the second failed, the row sat at
    /// `fileState=.local, blobPath=<old remote path>` — neither remoteOnly
    /// nor cleanly local. Reconcile-at-launch only scans `.downloading`
    /// rows so a half-promoted `.local` row was invisible to recovery.
    /// Doing both writes in one save makes the transition all-or-nothing.
    func promoteToLocalClearBlob(fingerprintKey key: String) async throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let book = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound(key)
        }
        book.fileState = BookFileState.local.rawValue
        book.blobPath = nil
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
    /// persisted. Returns the fingerprintKeys that actually landed
    /// (in input order) so callers can react to partial success — bug
    /// #119: `SelectiveRestoreCoordinator` needs the inserted set to
    /// post `.bookFileStateDidChange` per row that actually exists, not
    /// per row it intended to insert.
    ///
    /// On throw, the inserted keys up to the failing record are wrapped
    /// in `PersistenceError.partialBulkInsert(insertedKeys:underlying:)`
    /// so the caller can still notify for what landed.
    @discardableResult
    func insertRemoteOnlyBookRecords(_ records: [BookRecord]) async throws -> [String] {
        guard !records.isEmpty else { return [] }
        // Bug #119 follow-up (Codex round 3, TOCTOU): do the
        // fetch-or-create-or-skip dance inline using a single
        // synchronous `ModelContext` block per record, instead of
        // awaiting `findBook` then `insertBook`. The two-call form had
        // an await gap where another actor message could insert the
        // same fingerprintKey as `.local` between the find (returns
        // nil) and the insert (deduped to existing). The notification
        // would then fire `state=remoteOnly` for a row that's actually
        // `.local`. SwiftData's `fetch` + `insert` + `save` are
        // synchronous within the actor's body, so collapsing into one
        // block closes the window.
        let context = ModelContext(modelContainer)
        var insertedKeys: [String] = []
        for record in records {
            let key = record.fingerprintKey
            // Inline the canonical-key consistency check that `insertBook`
            // used to enforce. Catches feeding-a-mismatched-record bugs
            // that the previous findBook-then-insertBook path caught at
            // the insert layer.
            if record.fingerprintKey != record.fingerprint.canonicalKey {
                throw PersistenceError.partialBulkInsert(
                    insertedKeys: insertedKeys,
                    underlyingDescription: "Fingerprint key mismatch"
                )
            }
            do {
                let predicate = #Predicate<Book> { $0.fingerprintKey == key }
                var descriptor = FetchDescriptor<Book>(predicate: predicate)
                descriptor.fetchLimit = 1
                let existing = try context.fetch(descriptor)
                if !existing.isEmpty {
                    // Row already exists locally (any state). Don't
                    // downgrade — and don't claim we inserted it.
                    continue
                }
                let book = Book(
                    fingerprint: record.fingerprint,
                    title: record.title,
                    author: record.author,
                    coverImagePath: record.coverImagePath,
                    provenance: record.provenance,
                    addedAt: record.addedAt,
                    originalExtension: record.originalExtension
                )
                book.detectedEncoding = record.detectedEncoding
                book.lastOpenedAt = record.lastOpenedAt
                book.fileState = BookFileState.remoteOnly.rawValue
                book.blobPath = record.blobPath
                context.insert(book)
                try context.save()
                insertedKeys.append(key)
            } catch {
                throw PersistenceError.partialBulkInsert(
                    insertedKeys: insertedKeys,
                    underlyingDescription: "\(error)"
                )
            }
        }
        return insertedKeys
    }
}
