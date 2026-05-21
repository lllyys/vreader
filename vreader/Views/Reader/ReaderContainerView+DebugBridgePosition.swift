// Purpose: DEBUG-only helper that turns a live reader `Locator` into the
// position string surfaced by `DebugSnapshot.position` (Bug #257). Mirrors the
// `vreader-debug://open?position=` URL grammar per format so a round-trip
// (seek via `open?position=N` → read back via `snapshot`) is symmetric for the
// fully-wired formats (TXT / MD). Compiled out of Release via `#if DEBUG`.
//
// @coordinates-with ReaderContainerView.swift (the `.readerPositionDidChange`
//   observer writes `debugProbe?.livePositionString`),
//   DebugPositionResolver.swift (the inverse direction — string → DebugPosition),
//   RealDebugBridgeContext+Snapshot.swift (the consumer of `currentPositionString`).

#if DEBUG

import Foundation

extension ReaderContainerView {

    /// Map a live `Locator` to the DebugSnapshot position string, matching the
    /// `open?position=` grammar per format:
    /// - TXT / MD → the UTF-16 character offset as a decimal string.
    /// - PDF → the 1-based page number (the locator carries the 0-based PDFKit
    ///   index, so we add 1 to invert `DebugPosition.pdfPage`'s mapping).
    /// - EPUB / AZW3 → the CFI string when present.
    ///
    /// Returns nil when the locator carries no field the snapshot can express
    /// (so the field stays in the snapshot's `partial` array rather than
    /// reporting a misleading value).
    static func debugPositionString(for locator: Locator) -> String? {
        if let offset = locator.charOffsetUTF16 {
            return String(offset)
        }
        if let page = locator.page {
            // Locator.page is the 0-based PDFKit index; the URL grammar is
            // 1-based, so report page + 1 for round-trip symmetry.
            return String(page + 1)
        }
        if let cfi = locator.cfi, !cfi.isEmpty {
            return cfi
        }
        return nil
    }
}

#endif
