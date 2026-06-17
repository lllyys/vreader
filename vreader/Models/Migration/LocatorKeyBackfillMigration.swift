// Purpose: feature #109 — one-shot launch backfill that recomputes the persisted
// derived locator keys (Highlight/Bookmark/AnnotationNote `profileKey`,
// ReadingPosition `locatorHash`) under the new NFC canonicalization of
// `Locator.canonicalJSON` (bug #356), and repairs preexisting invalid
// (non-finite) locators.
//
// Why a launch backfill and NOT a SwiftData MigrationStage:
//   The transform changes NO entity shape. A would-be V-next schema has
//   IDENTICAL entity hashes to the current one, and SwiftData keys migration
//   on those hashes — its matcher cannot tell the two apart, so a
//   `MigrationStage.custom` between them NEVER fires (verified empirically:
//   the non-finite repair never ran on reopen). A pure data transform with no
//   schema delta must run OUTSIDE the migration plan.
//
// Why synchronous + gated + before store/UI construction (mirrors
// `ReadingModeMigration`): at launch no reader is open and no PersistenceActor /
// DebugBridge / UI is constructed yet, so a fresh `ModelContext` owns the store
// race-free — the same rationale `ReadingModeMigration` documents for its
// lock-less per-book files. A UserDefaults version flag gates it to run exactly
// once per install; it is idempotent if it ever re-runs (`recomputeKey` is
// deterministic and the repair is a no-op on finite locators). On error the flag
// is left UNSET so the next launch retries.
//
// MEMORY: each entity type is recomputed in ONE fetch + ONE save. Unlike the
// original (rejected) SwiftData migration-stage design, this backfill runs AFTER
// the store is already open, so it cannot block store-open even if it failed —
// the round-1 "fail before the store opens" risk does not exist here. A personal
// reader's annotation corpus is domain-bounded (hundreds, not millions), so a
// single pass is memory-safe. Offset paging was deliberately NOT used: the only
// stable sort columns (`createdAt`/`updatedAt`) are non-unique, the model UUIDs
// are not `Comparable` for a `SortDescriptor` tiebreaker, and offset paging over a
// non-unique order can skip or double-process rows on timestamp ties. A single
// fetch is a stable snapshot — skip-safe by construction.
//
// @coordinates-with: Locator.swift (canonicalJSON NFC + repairedForCanonicalization),
//   {Highlight,Bookmark,AnnotationNote,ReadingPosition}.swift (recomputeKey),
//   VReaderApp.swift (the synchronous launch call site),
//   dev-docs/plans/20260617-feature-109-nfc-canonical-locator-migration.md

import Foundation
import SwiftData
import os

enum LocatorKeyBackfillMigration {
    /// UserDefaults gate. Bump the suffix if canonicalization changes again so a
    /// fresh recompute runs.
    static let completionFlagKey = "vreader.migration.locatorKeyNFC.v1"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "LocatorKeyBackfill"
    )

    /// Recompute (+ repair) every derived locator key once. Synchronous and
    /// idempotent; a no-op when the gate flag is already set.
    ///
    /// - Important: callers MUST NOT invoke this for an in-memory store — the gate
    ///   flag lives in shared `UserDefaults` and an ephemeral in-memory launch
    ///   (UI tests) would set it without touching the real on-disk library,
    ///   starving a later real backfill. `VReaderApp` guards on the store kind.
    static func run(container: ModelContainer, defaults: UserDefaults) {
        guard defaults.bool(forKey: completionFlagKey) == false else { return }
        let context = ModelContext(container)
        do {
            try recomputeAll(Highlight.self, in: context) { $0.recomputeKey() }
            try recomputeAll(Bookmark.self, in: context) { $0.recomputeKey() }
            try recomputeAll(AnnotationNote.self, in: context) { $0.recomputeKey() }
            try recomputeAll(ReadingPosition.self, in: context) { $0.recomputeKey() }
            defaults.set(true, forKey: completionFlagKey)
        } catch {
            // Leave the flag UNSET so the next launch retries (idempotent).
            logger.error("Locator-key backfill failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Recompute keys for one entity type in a single fetch + save. A single
    /// fetch is a stable snapshot (skip-safe by construction); see the file
    /// header for why offset paging is unsafe here and why one pass is
    /// memory-safe for this app's domain-bounded corpus.
    private static func recomputeAll<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext,
        _ recompute: (T) -> Void
    ) throws {
        let rows = try context.fetch(FetchDescriptor<T>())
        guard !rows.isEmpty else { return }
        for row in rows { recompute(row) }
        try context.save()
    }
}
