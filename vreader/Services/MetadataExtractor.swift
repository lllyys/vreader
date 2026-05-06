// Purpose: Protocol and concrete implementations for book metadata extraction.
// EPUBMetadataExtractor reads OPF metadata (title, author) and extracts cover
// image bytes from the EPUB ZIP archive. AZW3MetadataExtractor delegates cover
// extraction to MOBICoverExtractor (native PDB/MOBI header parsing).
// Other formats use filename-based stubs.
//
// Key decisions:
// - Protocol-based design allows easy testing with mocks.
// - extractCoverImage has a default nil implementation (opt-in per format).
// - EPUBMetadataExtractor is stateless: each method opens the ZIP independently.
// - Cover extraction is fast (<50ms) — lightweight OPF-only parse + single entry read.
//
// @coordinates-with: BookImporter.swift, EPUBParser.swift, ZIPReader.swift,
//   CustomCoverStore.swift, MOBICoverExtractor.swift

import Foundation
import UIKit

/// Maximum title length in characters (shared across all extractors).
private let maxTitleLength = 255

/// Extracted metadata from a book file.
struct BookMetadata: Sendable, Equatable {
    /// Book title (required).
    let title: String

    /// Author name (optional).
    let author: String?

    /// Relative path to extracted cover image (optional).
    let coverImagePath: String?

    /// Creates metadata using filename-derived title (shared default behavior).
    static func fromFilename(_ fileURL: URL, author: String? = nil, coverImagePath: String? = nil) -> BookMetadata {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against dot-prefixed names with no real extension (e.g., ".txt"
        // is treated by URL as a hidden file, not "stem.ext"). If pathExtension
        // is empty and the name starts with ".", there is no meaningful stem.
        let hasNoStem = trimmed.isEmpty
            || (fileURL.pathExtension.isEmpty && trimmed.hasPrefix("."))
        let title = hasNoStem ? "Untitled" : String(trimmed.prefix(maxTitleLength))
        return BookMetadata(title: title, author: author, coverImagePath: coverImagePath)
    }
}

/// Protocol for extracting metadata from book files.
protocol MetadataExtractor: Sendable {
    /// Extracts metadata from the file at the given URL.
    ///
    /// - Parameter fileURL: Path to the imported file in sandbox.
    /// - Returns: Extracted metadata.
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata

    /// Extracts the cover image from the file at the given URL, if available.
    /// Default implementation returns nil (no cover). Formats that support embedded
    /// covers (EPUB, AZW3) override this.
    ///
    /// - Parameter fileURL: Path to the book file.
    /// - Returns: The cover image, or nil if unavailable or not decodable.
    func extractCoverImage(from fileURL: URL) async -> UIImage?
}

extension MetadataExtractor {
    func extractCoverImage(from fileURL: URL) async -> UIImage? { nil }
}

/// Extracts metadata for TXT files. Title from filename, no author, no cover.
struct TXTMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}

/// Extracts metadata and cover image from EPUB files.
/// Opens the EPUB as a ZIP, parses container.xml -> OPF for metadata/cover href,
/// then extracts the cover image entry. Stateless: each method opens the ZIP
/// independently for simplicity and thread safety.
struct EPUBMetadataExtractor: MetadataExtractor {

    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        guard let (metadata, _) = try? await Self.parseEPUBMetadata(from: fileURL) else {
            return .fromFilename(fileURL)
        }
        return BookMetadata(
            title: String(metadata.title.prefix(maxTitleLength)),
            author: metadata.author,
            coverImagePath: nil
        )
    }

    func extractCoverImage(from fileURL: URL) async -> UIImage? {
        guard let (metadata, opfDirPath) = try? await Self.parseEPUBMetadata(from: fileURL),
              let coverHref = metadata.coverImageHref,
              let zip = try? ZIPReader(fileURL: fileURL) else {
            return nil
        }

        // Bug #122: some EPUBs declare cover hrefs that don't resolve
        // spec-compliantly (publisher mistakes — e.g., href="OEBPS/cover.jpg"
        // for an OPF at OEBPS/content.opf joins to "OEBPS/OEBPS/cover.jpg"
        // which doesn't exist). Try a cascade of candidate paths and
        // return the first one whose bytes decode as a valid UIImage.
        let entries = await zip.listEntries()
        let candidates = Self.coverPathCandidates(
            coverHref: coverHref,
            opfDirPath: opfDirPath,
            entries: entries
        )
        for candidate in candidates {
            if let entry = await zip.entry(forPath: candidate),
               let imageData = try? await zip.extractData(for: entry),
               let image = UIImage(data: imageData) {
                return image
            }
        }
        return nil
    }

    // MARK: - Private

    /// Parses container.xml and OPF from an EPUB ZIP archive.
    /// Returns the parsed EPUBMetadata and the OPF directory path within the archive.
    private static func parseEPUBMetadata(from fileURL: URL) async throws -> (EPUBMetadata, String) {
        let zip = try ZIPReader(fileURL: fileURL)

        // Extract container.xml data
        guard let containerEntry = await zip.entry(forPath: "META-INF/container.xml") else {
            throw EPUBParserError.invalidFormat("No META-INF/container.xml")
        }
        let containerData = try await zip.extractData(for: containerEntry)
        let opfRelPath = try EPUBParser.parseContainerXML(containerData)

        // Extract and parse OPF
        guard let opfEntry = await zip.entry(forPath: opfRelPath) else {
            throw EPUBParserError.invalidFormat("OPF not found at \(opfRelPath)")
        }
        let opfData = try await zip.extractData(for: opfEntry)
        let result = try EPUBParser.parseOPF(opfData)

        let opfDirPath = (opfRelPath as NSString).deletingLastPathComponent
        return (result.metadata, opfDirPath)
    }

    /// Resolves a cover image href relative to the OPF directory within the archive.
    /// Handles ../ path components and produces a clean archive path.
    ///
    /// Examples:
    /// - opfDirPath="OEBPS", coverHref="Images/cover.jpg" -> "OEBPS/Images/cover.jpg"
    /// - opfDirPath="OEBPS", coverHref="../cover.jpg" -> "cover.jpg"
    /// - opfDirPath="", coverHref="cover.jpg" -> "cover.jpg"
    static func resolveArchivePath(coverHref: String, opfDirPath: String) -> String {
        guard !opfDirPath.isEmpty else { return coverHref }

        let combined = "\(opfDirPath)/\(coverHref)"
        let parts = combined.components(separatedBy: "/")

        var resolved: [String] = []
        for part in parts {
            if part == ".." {
                if !resolved.isEmpty { resolved.removeLast() }
            } else if part != "." && !part.isEmpty {
                resolved.append(part)
            }
        }

        return resolved.joined(separator: "/")
    }

    /// Builds the ordered list of archive paths to try for cover-image
    /// extraction. The caller probes them in order; the first one whose
    /// bytes decode as a valid `UIImage` is returned to the user.
    ///
    /// Order (bug #122):
    /// 1. Spec-compliant resolved path (`resolveArchivePath`).
    /// 2. Bare-basename match: any image-extension entry whose basename
    ///    equals `coverHref`'s basename, case-insensitive. Catches the
    ///    common publisher mistake of declaring `href="OEBPS/cover.jpg"`
    ///    against an OPF at `OEBPS/content.opf` when the real cover is
    ///    at `OEBPS/Images/cover.jpg`. Multiple matches are ranked: any
    ///    entry inside the OPF directory tree comes before entries
    ///    outside it. Within a rank tier, archive order is preserved.
    /// 3. Archive-root canonical cover: `cover.{jpg,jpeg,png,gif}` at
    ///    the archive root, case-insensitive. Last resort when neither
    ///    the OPF declaration nor the basename pattern resolves.
    ///
    /// The list is de-duplicated while preserving first-seen order so
    /// the caller probes each entry at most once.
    static func coverPathCandidates(
        coverHref: String,
        opfDirPath: String,
        entries: [ZIPEntry]
    ) -> [String] {
        var candidates: [String] = []
        var seen: Set<String> = []
        func add(_ path: String) {
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            candidates.append(path)
        }

        // 1. Spec-compliant resolved path.
        add(Self.resolveArchivePath(coverHref: coverHref, opfDirPath: opfDirPath))

        // 2. Bare-basename match (image extensions only).
        // Real-world EPUBs almost always have one cover.jpg per book, but if a
        // packager left a thumbnail or backup file with the same basename we
        // prefer the one that sits inside the OPF directory tree — that is
        // the location a publisher would actually associate with the book.
        let coverBasename = (coverHref as NSString).lastPathComponent.lowercased()
        if !coverBasename.isEmpty {
            // Normalize the OPF-dir prefix once (with trailing slash) so we
            // can do a single hasPrefix check. Empty opfDirPath means the OPF
            // sits at the archive root, so every entry counts as inside.
            let opfPrefix = opfDirPath.isEmpty ? "" : "\(opfDirPath)/"
            var insideOPF: [String] = []
            var outsideOPF: [String] = []
            for entry in entries where !entry.isDirectory {
                let path = entry.path
                guard Self.hasImageExtension(path) else { continue }
                guard (path as NSString).lastPathComponent.lowercased() == coverBasename else { continue }
                if opfPrefix.isEmpty || path.hasPrefix(opfPrefix) {
                    insideOPF.append(path)
                } else {
                    outsideOPF.append(path)
                }
            }
            for path in insideOPF { add(path) }
            for path in outsideOPF { add(path) }
        }

        // 3. Archive-root canonical cover.
        let canonicalCoverNames: Set<String> = ["cover.jpg", "cover.jpeg", "cover.png", "cover.gif"]
        for entry in entries where !entry.isDirectory {
            let path = entry.path
            // Root-level only — must not contain a "/" separator. Match the
            // basename case-insensitively.
            guard !path.contains("/") else { continue }
            if canonicalCoverNames.contains(path.lowercased()) {
                add(path)
            }
        }

        return candidates
    }

    /// True when `path` ends with an image-file extension we accept for
    /// covers. Case-insensitive.
    private static func hasImageExtension(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".png")
            || lower.hasSuffix(".gif")
            || lower.hasSuffix(".webp")
    }
}

/// Stub extractor for PDF files.
/// TODO(WI-7): Replace with PDFKit-based extractor that reads PDF document info
/// (title, author, page count). Remove this stub when WI-7 lands.
struct PDFMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}

/// Extractor for AZW3/MOBI files. Title from EXTH 503 (Updated title) +
/// author from EXTH 100, parsed natively from the MOBI binary. Falls back
/// to filename-derived title when EXTH is unavailable (truncated file,
/// missing EXTH header, or non-MOBI content). Cover image is extracted by
/// native MOBI header parsing (`MOBICoverExtractor`).
///
/// Bug #149 / GH #340 fix: pre-fix returned `.fromFilename(fileURL)`
/// unconditionally, so imported AZW3 books showed their filename as the
/// title even when EXTH metadata was present.
struct AZW3MetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        let exth = MOBIMetadataParser.extractTitleAndAuthor(from: fileURL)
        if exth.title != nil || exth.author != nil {
            // Use EXTH-extracted title when available; fall back to filename
            // for the title field if EXTH 503 was missing but EXTH 100 was
            // present (rare, but possible for files with only an author).
            let fallback = BookMetadata.fromFilename(fileURL)
            return BookMetadata(
                title: exth.title ?? fallback.title,
                author: exth.author,
                coverImagePath: nil
            )
        }
        // No EXTH 503 / 100 → keep historical filename-based fallback.
        return .fromFilename(fileURL)
    }

    func extractCoverImage(from fileURL: URL) async -> UIImage? {
        MOBICoverExtractor.extractCover(from: fileURL)
    }
}
