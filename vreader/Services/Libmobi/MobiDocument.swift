// Purpose: Feature #42 Phase 2 WI-2a — the DECODE half of Kindle convert-on-
// import. Loads + reconstructs an AZW3/MOBI/KF8/PRC file through the vendored
// libmobi C library and extracts its parts (XHTML markup, CSS/SVG flow, binary
// resources like images and fonts) as Swift value types. The EPUB-assembly half
// (OPF generation + zip packaging) is WI-2b; BookImporter integration is WI-4.
//
// libmobi exposes no EPUB writer, so the part extraction here is the foundation
// the assembler builds on: mobi_init → mobi_load_filename → mobi_init_rawml →
// mobi_parse_rawml (which internally reconstructs KF7/KF8), then walk the three
// MOBIPart linked lists (markup / flow / resources) off the parsed MOBIRawml.
//
// @coordinates-with: Libmobi.swift, Libmobi-Bridging-Header.h,
//   vreader/Services/Libmobi/BUILD-RECIPE.md,
//   dev-docs/plans/20260528-feature-42-readium-libmobi-reader-engine.md

import Foundation

/// One reconstructed part of a parsed Kindle book.
struct MobiPart: Equatable, Sendable {
    /// Which of libmobi's three linked lists the part came from.
    enum Section: Equatable, Sendable { case markup, flow, resource }

    let section: Section
    /// libmobi's unique id for the part — drives cross-references (e.g. an
    /// `<img>` in markup points at a resource by this id), so the assembler
    /// (WI-2b) needs it to rewrite hrefs.
    let uid: Int
    /// File extension libmobi assigns the part's type (`"html"`, `"css"`,
    /// `"jpg"`, …); empty when the type has no mapping.
    let fileExtension: String
    /// The part's raw bytes — decoded XHTML/CSS text or binary resource data.
    let data: Data
}

/// Errors from the libmobi decode path. The associated `Int32` is libmobi's own
/// `MOBI_RET` code (e.g. encrypted/DRM books fail at parse), surfaced to the
/// importer (WI-4) so it can tell the user *why* a Kindle file couldn't open.
enum MobiDecodeError: Error, Equatable {
    case initFailed
    case loadFailed(Int32)
    case parseFailed(Int32)
    case noMarkup            // parsed, but produced zero markup parts
    case corrupt(String)     // malformed part chain (cycle, or size>0 w/ null data)
}

/// The Kindle book's own embedded display metadata (Feature #42 P2-WI-4a). All
/// fields are deterministic functions of the source file (read via libmobi's
/// `mobi_meta_get_*`), so embedding them in the converted EPUB keeps the EPUB
/// byte-deterministic (the converter is title-neutral w.r.t. callers).
struct MobiMetadata: Equatable, Sendable {
    let title: String?
    let author: String?
}

/// A fully-decoded Kindle book: its reconstructed parts plus its own embedded
/// metadata. The converter embeds the metadata into the EPUB so the result is
/// self-describing (round-3 audit: restore must recover title/author/cover from
/// the blob itself).
struct MobiBook: Sendable {
    let parts: [MobiPart]
    let metadata: MobiMetadata
}

extension Libmobi {

    /// Defensive ceiling on the number of parts in a single section. A real
    /// book has at most a few thousand parts across all sections; a count this
    /// high can only come from a cyclic/corrupt `MOBIPart.next` chain, which we
    /// reject (`.corrupt`) rather than loop on until OOM (Codex Gate-4 M1).
    static let maxPartsPerSection = 100_000

    /// Load + fully reconstruct the Kindle file at `path` (AZW3/MOBI/KF8/PRC),
    /// returning its parts. Pure C interop with no shared mutable state, so it
    /// is safe to call off the main actor — callers SHOULD, since parsing a
    /// multi-megabyte book is CPU-bound. Every libmobi allocation is freed
    /// before return (via `defer`), including on the throwing paths.
    ///
    /// - Throws: `MobiDecodeError` on init/load/parse failure or a corrupt part
    ///   chain. A DRM-encrypted book typically loads but fails at
    ///   `mobi_parse_rawml` with a libmobi error code → `.parseFailed`.
    static func decodeParts(atPath path: String) throws -> [MobiPart] {
        try decodeBook(atPath: path).parts
    }

    /// Load + fully reconstruct the Kindle file at `path`, returning its parts
    /// AND its embedded display metadata (title / author). The metadata is read
    /// from the loaded `MOBIData` (`mobi_meta_get_*`) before rawml parsing.
    /// Same C-interop / freeing / off-main contract as `decodeParts`.
    static func decodeBook(atPath path: String) throws -> MobiBook {
        guard let m = mobi_init() else { throw MobiDecodeError.initFailed }
        defer { mobi_free(m) }

        let loadRet = path.withCString { mobi_load_filename(m, $0) }
        guard loadRet == MOBI_SUCCESS else {
            throw MobiDecodeError.loadFailed(Int32(loadRet.rawValue))
        }

        // Metadata from the source file's own headers — deterministic.
        let metadata = MobiMetadata(
            title: copyMetaString(mobi_meta_get_title(m)),
            author: copyMetaString(mobi_meta_get_author(m))
        )

        guard let rawml = mobi_init_rawml(m) else { throw MobiDecodeError.initFailed }
        defer { mobi_free_rawml(rawml) }

        let parseRet = mobi_parse_rawml(rawml, m)
        guard parseRet == MOBI_SUCCESS else {
            throw MobiDecodeError.parseFailed(Int32(parseRet.rawValue))
        }

        var parts: [MobiPart] = []
        try appendChain(rawml.pointee.markup, section: .markup, into: &parts)
        try appendChain(rawml.pointee.flow, section: .flow, into: &parts)
        try appendChain(rawml.pointee.resources, section: .resource, into: &parts)

        guard parts.contains(where: { $0.section == .markup }) else {
            throw MobiDecodeError.noMarkup
        }
        return MobiBook(parts: parts, metadata: metadata)
    }

    /// Copy a libmobi-allocated metadata C string into a Swift `String` and free
    /// it (libmobi's `mobi_meta_get_*` return malloc'd strings the caller owns).
    /// Returns nil for a null pointer or an empty string.
    private static func copyMetaString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr else { return nil }
        defer { free(ptr) }
        let s = String(cString: ptr)
        return s.isEmpty ? nil : s
    }

    /// Walk a libmobi part linked list, copying each node's bytes into a value.
    /// `MOBIPart.data` is owned by the `MOBIRawml` (freed by `mobi_free_rawml`),
    /// so we copy into a Swift `Data` rather than alias the C buffer.
    ///
    /// `internal` (not `private`) so the synthetic-chain tests can exercise the
    /// defensive paths deterministically without a real libmobi parse.
    ///
    /// - Throws: `.corrupt` if the chain exceeds `maxPartsPerSection` (cyclic /
    ///   corrupt `next`), or if a part declares a positive `size` but a null
    ///   `data` pointer (Codex Gate-4 M1/M2).
    static func appendChain(
        _ head: UnsafeMutablePointer<MOBIPart>?,
        section: MobiPart.Section,
        into parts: inout [MobiPart]
    ) throws {
        var node = head
        var count = 0
        while let p = node {
            count += 1
            guard count <= maxPartsPerSection else {
                throw MobiDecodeError.corrupt(
                    "\(section) chain exceeded \(maxPartsPerSection) parts (cyclic or corrupt next)")
            }
            let part = p.pointee
            let data: Data
            if part.size == 0 {
                data = Data()                       // legitimately-empty part
            } else if let raw = part.data {
                data = Data(bytes: raw, count: part.size)
            } else {
                throw MobiDecodeError.corrupt(
                    "\(section) part uid \(part.uid) declares size \(part.size) but data is null")
            }
            parts.append(MobiPart(
                section: section,
                uid: Int(part.uid),
                fileExtension: fileExtension(for: part.type),
                data: data
            ))
            node = part.next
        }
    }

    /// Map a libmobi `MOBIFiletype` to its file extension. Explicit switch (not
    /// `mobi_get_filemeta_by_type`) so the mapping is visible + avoids the
    /// `extension` Swift-keyword collision on `MOBIFileMeta`'s field.
    private static func fileExtension(for type: MOBIFiletype) -> String {
        switch type {
        case T_HTML: return "html"
        case T_CSS:  return "css"
        case T_SVG:  return "svg"
        case T_OPF:  return "opf"
        case T_NCX:  return "ncx"
        case T_JPG:  return "jpg"
        case T_GIF:  return "gif"
        case T_PNG:  return "png"
        case T_BMP:  return "bmp"
        case T_OTF:  return "otf"
        case T_TTF:  return "ttf"
        case T_MP3:  return "mp3"
        case T_MPG:  return "mpg"
        case T_PDF:  return "pdf"
        default:     return ""
        }
    }
}
