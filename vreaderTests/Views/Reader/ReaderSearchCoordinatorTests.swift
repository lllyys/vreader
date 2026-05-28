// Purpose: Tests for ReaderSearchCoordinator's Bug #264 fix — the stale
// persistent-FTS-row handling. A `search_metadata` row with an empty
// `segment_base_offsets` column (older schema / interrupted index / a stale
// row a DEBUG reset left behind) made `setup`'s restore branch a silent no-op,
// so the book never became searchable (`service.isIndexed()` stayed false and
// the indexed-search wait timed out). The fix: (1) a pure decision helper that
// flags such a row for re-index, and (2) `wipeSearchIndex(at:)` so the DEBUG
// reset wipes the persistent FTS store for a true clean slate.
//
// Both members under test are `nonisolated static`, so this suite needs no
// MainActor hop and constructs no live coordinator (which would touch the real
// Application Support path).
//
// @coordinates-with: ReaderSearchCoordinator.swift,
//   RealDebugBridgeContext.swift (reset wipe), GH #1141 (Bug #264)

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSearchCoordinator — Bug #264 stale-FTS-row handling")
struct ReaderSearchCoordinatorBug264Tests {

    // MARK: - formatRequiresSegmentOffsets
    //
    // This is the format dimension that decides how `setup` treats a persisted
    // index row with NO restorable segment offsets: TXT/MD persist offsets, so
    // a missing offsets column means a STALE row → re-index; EPUB/PDF never
    // persist offsets (they locate by href/page), so a nil-offsets row is the
    // NORMAL reopen state → mark indexed in memory, never re-index. Getting
    // this wrong would re-index every EPUB/PDF book on every open.

    @Test("TXT requires segment offsets")
    func txtRequiresOffsets() {
        #expect(ReaderSearchCoordinator.formatRequiresSegmentOffsets("txt") == true)
    }

    @Test("MD requires segment offsets")
    func mdRequiresOffsets() {
        #expect(ReaderSearchCoordinator.formatRequiresSegmentOffsets("md") == true)
    }

    @Test("EPUB does NOT persist segment offsets (nil-offsets row is normal)")
    func epubDoesNotRequireOffsets() {
        #expect(ReaderSearchCoordinator.formatRequiresSegmentOffsets("epub") == false)
    }

    @Test("PDF does NOT persist segment offsets")
    func pdfDoesNotRequireOffsets() {
        #expect(ReaderSearchCoordinator.formatRequiresSegmentOffsets("pdf") == false)
    }

    @Test("unknown / future format defaults to not requiring offsets")
    func unknownFormatDefaultsFalse() {
        #expect(ReaderSearchCoordinator.formatRequiresSegmentOffsets("azw3") == false)
    }

    // MARK: - wipeSearchIndex(at:)

    @Test("wipeSearchIndex removes the directory and is idempotent")
    func wipeRemovesDirectoryIdempotently() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vreader-bug264-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbFile = dir.appendingPathComponent("search.sqlite3")
        try Data("stale".utf8).write(to: dbFile)
        #expect(FileManager.default.fileExists(atPath: dbFile.path))

        ReaderSearchCoordinator.wipeSearchIndex(at: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path) == false)

        // Idempotent — a second wipe on the absent directory does not throw.
        ReaderSearchCoordinator.wipeSearchIndex(at: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path) == false)
    }
}
