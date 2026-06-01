// Purpose: Feature #42 Phase 2 WI-2c — the end-to-end MOBI→EPUB converter. Ties
// the decode (WI-2a) and assembly (WI-2b) halves together and packages the
// result into an actual `.epub` byte stream (a Stored-method OCF zip), ready to
// write to disk and import through the Readium engine (WI-4).
//
//   decode (libmobi)  →  assemble (EPUB layout)  →  package (OCF zip)
//
// The packaging reuses `ZIPWriter` — generic, write-only, in-memory ZIP infra
// (it writes every entry Stored/uncompressed, which is valid EPUB OCF and
// satisfies the "mimetype must be stored" requirement; `assemble` emits the
// mimetype first, and ZIPWriter preserves entry order, so it lands first).
//
// @coordinates-with: MobiDocument.swift, MobiEPUBAssembler.swift,
//   vreader/Services/Backup/ZIPWriter.swift,
//   vreader/Services/Libmobi/BUILD-RECIPE.md

import Foundation

enum MobiEPUBConverter {

    /// Convert the Kindle file at `mobiPath` (AZW3/MOBI/KF8/PRC) into EPUB bytes:
    /// decode via libmobi → lay out the EPUB → package as a Stored OCF zip.
    /// CPU- and memory-bound for a multi-megabyte book, so call off the main
    /// actor.
    ///
    /// - Throws: `MobiDecodeError` (load/parse/corrupt/noMarkup) or
    ///   `MobiEPUBError` (assembly) or `ZIPWriterError` (packaging).
    static func convert(mobiPath: String, title: String) throws -> Data {
        let parts = try Libmobi.decodeParts(atPath: mobiPath)
        let files = try MobiEPUBAssembler.assemble(parts: parts, title: title)
        return try package(files: files)
    }

    /// Package already-assembled EPUB file entries into an OCF zip. Entry order
    /// is preserved, so the `mimetype` entry (first from `assemble`) lands first
    /// in the archive, as the OCF spec requires.
    static func package(files: [EPUBFile]) throws -> Data {
        let entries = files.map { ZIPWriter.Entry(name: $0.path, data: $0.data) }
        return try ZIPWriter.createArchive(entries: entries)
    }
}
