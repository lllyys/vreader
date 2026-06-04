// Purpose: Feature #91 WI-6b — the persistent-index SAFETY GATE for
// search_other_books, plus the backend seam the tool depends on. This is where
// the Gate-2-flagged index-coverage risk lives: a library book is searchable
// from its PERSISTED FTS index ONLY when its index is present AND not stale.
//
// Why this gate exists (verified against SearchService.search + the index store):
// - `SearchService.search` queries the FTS store DIRECTLY — it does not require
//   the book to be marked indexed in memory. So FTS content alone yields correct
//   snippets.
// - BUT the hit→locator resolver DROPS a result whose locator can't be resolved
//   (compactMap on nil). TXT/MD store FTS positions as SEGMENT-relative; without
//   the restored segment base offsets the locator resolves to nil and the result
//   silently vanishes — the book would look empty. EPUB/PDF resolve without
//   offsets. So TXT/MD must have non-nil, non-stale offsets (restored before the
//   search), or be EXCLUDED.
// - A persisted index built by an older decode pipeline (`requiresReindex`) can
//   mis-align offsets → EXCLUDE (never serve a mis-resolved result).
//
// This mirrors the FULL guard set `ReaderSearchCoordinator.setup` applies
// (isBookIndexed AND not requiresReindex AND non-nil TXT/MD offsets). The gate is
// a PURE function of the index state, so every case is unit-testable without the
// live store. NO on-demand (re)indexing — excluded books are reported by count so
// the model knows coverage is partial.
//
// @coordinates-with: SearchOtherBooksTool.swift (consumer), SearchService.swift
//   (search + restoreSegmentOffsets), SearchIndexStore.swift (the guard reads),
//   ReaderSearchCoordinator.swift (the canonical guard set this mirrors),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6b)

import Foundation

/// Why a library book is NOT searchable from its persisted index.
enum LibrarySearchExclusion: String, Sendable, Equatable {
    /// No persistent index row — never indexed (import no longer auto-indexes).
    case notIndexed
    /// TXT/MD index built by an older decode pipeline — offsets may mis-align.
    case requiresReindex
    /// TXT/MD indexed but the segment base offsets are missing — a stale row
    /// (interrupted index / older schema) whose results would silently drop.
    case staleOffsets
}

/// The result of gating one book: searchable (with optional TXT/MD offsets to
/// restore before searching) or excluded with a reason.
enum LibrarySearchEligibility: Sendable, Equatable {
    case searchable(restoreOffsets: [Int: Int]?)
    case excluded(LibrarySearchExclusion)
}

/// A book's persistent-index state — the inputs the gate decides on. The
/// production backend reads these off `SearchIndexStore`; tests build them inline.
struct LibraryIndexState: Sendable, Equatable {
    let isIndexed: Bool
    let requiresReindex: Bool
    let segmentOffsets: [Int: Int]?
}

/// The pure persistent-index safety gate (the WI-6b risk core).
enum LibraryBookSearchGate {

    /// TXT/MD store FTS positions as segment-relative, so they need restored base
    /// offsets for the hit→locator resolver; EPUB/PDF do not. Mirrors
    /// `ReaderSearchCoordinator.formatRequiresSegmentOffsets` (kept local to avoid
    /// a Services→Views dependency; the format set rarely changes).
    static func requiresSegmentOffsets(_ format: String) -> Bool {
        format == "txt" || format == "md"
    }

    /// Decide whether `format`'s book is safely searchable from its persisted
    /// index given its `state`. Pure — no I/O, exhaustively testable.
    static func evaluate(format: String, state: LibraryIndexState) -> LibrarySearchEligibility {
        guard state.isIndexed else { return .excluded(.notIndexed) }
        guard requiresSegmentOffsets(format) else {
            // EPUB/PDF (and any non-offset format): FTS content resolves without
            // offsets.
            return .searchable(restoreOffsets: nil)
        }
        // TXT/MD: must not be stale, and must carry restorable offsets.
        if state.requiresReindex { return .excluded(.requiresReindex) }
        guard let offsets = state.segmentOffsets else { return .excluded(.staleOffsets) }
        return .searchable(restoreOffsets: offsets)
    }
}

/// The library-search backend `search_other_books` depends on: list books,
/// inspect each book's persistent-index state, restore TXT/MD offsets so locators
/// resolve, and run a per-book FTS search. The production adapter (wired in WI-8)
/// wraps the live `LibraryPersisting` + `SearchIndexStore` + `SearchService`;
/// tests use a stub. All-async so an `actor` stub conforms cleanly.
protocol LibrarySearchBackend: Sendable {
    func libraryBooks() async throws -> [LibraryBookItem]
    func indexState(fingerprintKey: String) async -> LibraryIndexState
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async
    func search(query: String, fingerprint: DocumentFingerprint, limit: Int) async throws -> SearchResultPage
}
