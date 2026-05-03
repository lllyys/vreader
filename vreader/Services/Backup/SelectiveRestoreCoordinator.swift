// Purpose: Orchestrator for the selective-restore flow (#47 WI-4b).
// Given the manifest of a backup and the user's selected fingerprint
// keys, this coordinator:
//
//   1. Pre-plants every UNSELECTED entry as a `.remoteOnly` row in
//      persistence so it shows up in the library immediately. The
//      lazy-download coordinator (#47 WI-3) will fetch the bytes on
//      first tap.
//   2. Materializes (downloads + verifies + imports) every SELECTED
//      entry via the existing `BookFileMaterializer`. Each successful
//      import lands as a `.local` row.
//   3. Runs metadata restore via the existing `BackupDataRestoring`
//      path so reading positions, annotations, collections, etc.
//      reattach to BOTH `.local` and `.remoteOnly` rows by
//      fingerprintKey.
//
// Phases report progress 0...1 with a fixed weighting (0.10 / 0.75 /
// 0.15). The coordinator does NOT fetch the manifest itself —
// `RemoteBookCatalog.loadEntries(fromBackupZIP:)` does that, and the
// caller (BackupViewModel / WebDAVProvider.restoreSelectively) hands
// the decoded list in.
//
// @coordinates-with: BookFileMaterializer.swift,
//   PersistenceActor+RemoteOnly.swift, RemoteBookCatalog.swift,
//   WebDAVProvider.swift (BackupDataRestoring),
//   BackupSectionDTOs.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "SelectiveRestoreCoordinator")

/// Bytes carried by `restoreSelectively`'s metadata-restore phase.
/// Each section is optional because older backups may omit some
/// sections (e.g. `replacementRules` was added later).
struct SelectiveRestoreMetadataSections: Sendable {
    var annotations: Data?
    var positions: Data?
    var settings: Data?
    var collections: Data?
    var bookSources: Data?
    var perBookSettings: Data?
    var replacementRules: Data?

    init(
        annotations: Data? = nil,
        positions: Data? = nil,
        settings: Data? = nil,
        collections: Data? = nil,
        bookSources: Data? = nil,
        perBookSettings: Data? = nil,
        replacementRules: Data? = nil
    ) {
        self.annotations = annotations
        self.positions = positions
        self.settings = settings
        self.collections = collections
        self.bookSources = bookSources
        self.perBookSettings = perBookSettings
        self.replacementRules = replacementRules
    }
}

/// Per-coordinator outcome. Aggregates per-entry materialize results
/// + the count of pre-planted remote-only rows so callers can show a
/// summary ("2 imported · 3 marked for download").
struct SelectiveRestoreSummary: Sendable {
    let materialized: [MaterializeResult]
    let remoteOnlyPreplantedKeys: [String]

    var localCount: Int { materialized.filter { $0.isSuccess }.count }
    var remoteOnlyCount: Int { remoteOnlyPreplantedKeys.count }
}

struct SelectiveRestoreCoordinator: Sendable {

    private let materializer: BookFileMaterializer
    private let persistence: PersistenceActor
    private let dataRestorer: any BackupDataRestoring

    init(
        materializer: BookFileMaterializer,
        persistence: PersistenceActor,
        dataRestorer: any BackupDataRestoring
    ) {
        self.materializer = materializer
        self.persistence = persistence
        self.dataRestorer = dataRestorer
    }

    /// Runs the three-phase selective restore. Caller is responsible
    /// for fetching the backup ZIP and decoding the manifest via
    /// `RemoteBookCatalog.loadEntries(fromBackupZIP:)` first.
    ///
    /// - Parameters:
    ///   - manifest: every entry in the backup's library manifest.
    ///   - selectedKeys: the subset the user chose to materialize
    ///     immediately. Keys not in this set are pre-planted as
    ///     `.remoteOnly` rows.
    ///   - metadataSections: bytes for each restore section
    ///     (annotations, positions, etc.). Sections present in the
    ///     backup ZIP but not in this struct are skipped.
    ///   - progress: 0.0 → 1.0 callback. Phase weights:
    ///     0.10 preplant, 0.75 materialize, 0.15 metadata restore.
    func restoreSelectively(
        manifest: [BackupLibraryEntry],
        selectedKeys: Set<String>,
        metadataSections: SelectiveRestoreMetadataSections,
        progress: @Sendable (Double) -> Void
    ) async throws -> SelectiveRestoreSummary {
        progress(0.0)

        // Phase 1 — preplant remote-only rows.
        let unselected = manifest.filter { !selectedKeys.contains($0.fingerprintKey) }
        let preplantedKeys = unselected.map(\.fingerprintKey)
        if !unselected.isEmpty {
            let records = unselected.map { Self.makeRemoteOnlyRecord(from: $0) }
            try await persistence.insertRemoteOnlyBookRecords(records)
        }
        progress(0.10)
        log.info(
            "preplanted \(unselected.count) remoteOnly row(s); \(selectedKeys.count) selected for materialization"
        )

        // Phase 2 — materialize selected entries.
        let selected = manifest.filter { selectedKeys.contains($0.fingerprintKey) }
        let materializeResults: [MaterializeResult]
        if selected.isEmpty {
            materializeResults = []
            progress(0.85)
        } else {
            materializeResults = await materializer.materialize(selected) { sub in
                // Map sub-progress 0..1 → 0.10..0.85.
                progress(0.10 + sub * 0.75)
            }
        }

        // Phase 3 — metadata restore. Sections present get applied;
        // missing sections are no-op'd. Reading positions land on the
        // entries we just inserted (local + remoteOnly) by fingerprintKey.
        try await applyMetadataSections(metadataSections)
        progress(1.0)

        return SelectiveRestoreSummary(
            materialized: materializeResults,
            remoteOnlyPreplantedKeys: preplantedKeys
        )
    }

    // MARK: - Phase 3 helper

    private func applyMetadataSections(_ sections: SelectiveRestoreMetadataSections) async throws {
        if let data = sections.annotations { try await dataRestorer.restoreAnnotations(from: data) }
        if let data = sections.positions { try await dataRestorer.restorePositions(from: data) }
        if let data = sections.settings { try await dataRestorer.restoreSettings(from: data) }
        if let data = sections.collections { try await dataRestorer.restoreCollections(from: data) }
        if let data = sections.bookSources { try await dataRestorer.restoreBookSources(from: data) }
        if let data = sections.perBookSettings { try await dataRestorer.restorePerBookSettings(from: data) }
        if let data = sections.replacementRules { try await dataRestorer.restoreReplacementRules(from: data) }
    }

    // MARK: - Manifest → BookRecord

    /// Maps a manifest entry into a `BookRecord` for the persistence
    /// layer. `fileState` is set to `.remoteOnly` (the bulk-insert
    /// coerces it anyway, but being explicit at the call site reads
    /// cleaner and matches the intent). `provenance.source = .restore`.
    static func makeRemoteOnlyRecord(from entry: BackupLibraryEntry) -> BookRecord {
        let format = BookFormat(rawValue: entry.format) ?? .epub
        let fp = DocumentFingerprint(
            contentSHA256: entry.sha256,
            fileByteCount: entry.byteCount,
            format: format
        )
        let provenance = ImportProvenance(
            source: .restore,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        return BookRecord(
            fingerprintKey: entry.fingerprintKey,
            title: entry.title ?? "Untitled",
            author: entry.author,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: provenance,
            detectedEncoding: nil,
            addedAt: entry.addedAt,
            originalExtension: entry.originalExtension,
            lastOpenedAt: entry.lastOpenedAt,
            fileState: .remoteOnly,
            blobPath: entry.blobPath
        )
    }
}
