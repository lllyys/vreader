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

    /// Converter format version. Bump whenever a change alters the produced EPUB
    /// bytes. Recorded (best-effort) in `ImportProvenance` so a future improvement
    /// is distinguishable; re-conversion is a local re-import operation (WI-4b).
    static let version = 1

    /// Fallback EPUB title when the source has no embedded title. A FIXED string
    /// (not the filename) so the output stays a deterministic function of the
    /// source CONTENT, not its path.
    static let fallbackTitle = "Untitled"

    /// Convert the Kindle file at `mobiPath` (AZW3/MOBI/KF8/PRC) into EPUB bytes:
    /// decode via libmobi → lay out a self-describing EPUB → package as a Stored
    /// OCF zip. CPU- and memory-bound for a multi-megabyte book, so call off the
    /// main actor.
    ///
    /// **Title-neutral (WI-4a):** the EPUB's embedded title/author come from the
    /// SOURCE file's own metadata (`mobi_meta_get_*`), never from a caller, so
    /// the bytes — and thus the resulting fingerprint — are a deterministic
    /// function of the source. This is what lets the converted EPUB be a
    /// self-consistent first-class EPUB (identity = its own blob).
    ///
    /// Peak memory note (Codex WI-2c Low): the pipeline is fully in-memory —
    /// decoded parts, assembled `Data` blobs, and the zip archive coexist, so an
    /// image-heavy book sees ~2-3× its size in peak RAM. Acceptable for the
    /// current fixture range (≤~18 MB).
    ///
    /// - Throws: `MobiDecodeError` (load/parse/corrupt/noMarkup) or
    ///   `MobiEPUBError` (assembly) or `ZIPWriterError` (packaging).
    static func convert(mobiPath: String) throws -> Data {
        let book = try Libmobi.decodeBook(atPath: mobiPath)
        let title = book.metadata.title ?? fallbackTitle
        let files = try MobiEPUBAssembler.assemble(
            parts: book.parts, title: title, author: book.metadata.author)
        return try package(files: files)
    }

    /// Convert + write the EPUB to a uniquely-named file under `destinationDir`,
    /// returning the file URL. The importer's existing hash/sandbox pipeline is
    /// file-based, so it needs a URL. Off-main-safe.
    ///
    /// Error boundary (WI-4 design decision #8): a SEMANTIC conversion failure
    /// (`MobiDecodeError`/`MobiEPUBError`) propagates from `convert` so the
    /// caller can fall back to native import. A filesystem WRITE failure is a
    /// REAL error (not a fallback); a partial file is cleaned up before throwing.
    static func convertToFile(mobiPath: String, destinationDir: URL) throws -> URL {
        let data = try convert(mobiPath: mobiPath)   // semantic failures throw here
        let dest = destinationDir.appendingPathComponent("kindle-converted-\(UUID().uuidString).epub")
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return dest
    }

    /// Package already-assembled EPUB file entries into an OCF zip. Entry order
    /// is preserved, so the `mimetype` entry (first from `assemble`) lands first
    /// in the archive, as the OCF spec requires.
    ///
    /// OCF requires the `mimetype` entry be Stored (uncompressed). `ZIPWriter`
    /// stores every entry, so this holds today; the invariant is CI-gated by
    /// `MobiEPUBConverterTests.mimetypeRawHeaderIsStored`, which reads the raw
    /// local-file-header compression-method field — if `ZIPWriter` ever starts
    /// deflating, that test fails before this can ship a non-compliant EPUB
    /// (Codex Gate-4 Medium).
    static func package(files: [EPUBFile]) throws -> Data {
        let entries = files.map { ZIPWriter.Entry(name: $0.path, data: $0.data) }
        return try ZIPWriter.createArchive(entries: entries)
    }
}
