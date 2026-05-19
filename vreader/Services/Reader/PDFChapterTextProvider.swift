// Purpose: Feature #56 WI-2.5 — the PDF `ChapterTextProviding` adapter. The
// translation unit is a page range (plan Decision 2.5 / 2.7). This adapter is
// fully foundational and JS-free: it is the design-blocked PDF *render panel*
// that waits on WI-13, not this extractor — the extractor lands complete here.
//
// Key decisions:
// - A `Sendable` `struct` holding only value state: the PDF file URL and the
//   page-grouping size. `PDFDocument` is not `Sendable`, so it is opened
//   lazily inside each method rather than stored — keeping the adapter a
//   plain `struct`.
// - Units are zero-indexed page ranges `"start-end"` to match
//   `Locator.page`'s zero-indexed convention. With the default
//   `pagesPerUnit == 1`, each page is its own unit; a larger value groups
//   consecutive pages (the trailing unit may be short).
// - A missing / unreadable PDF yields `[]` units and `nil` resolutions rather
//   than throwing from `translationUnits()` — a book with zero units is a
//   valid empty-book case the coordinator handles.
//
// @coordinates-with: ChapterTextProviding.swift, PDFTextExtractor.swift,
//   Locator.swift

import Foundation
import PDFKit

/// Supplies per-page-range source text for an open PDF book.
struct PDFChapterTextProvider: ChapterTextProviding {

    /// Fingerprint of the open book (carried for parity with the other
    /// adapters; not needed for extraction).
    private let fingerprint: DocumentFingerprint

    /// The PDF file on disk — opened lazily per call.
    private let fileURL: URL

    /// Number of consecutive pages grouped into one translation unit.
    private let pagesPerUnit: Int

    init(fingerprint: DocumentFingerprint, fileURL: URL, pagesPerUnit: Int = 1) {
        self.fingerprint = fingerprint
        self.fileURL = fileURL
        self.pagesPerUnit = max(1, pagesPerUnit)
    }

    func translationUnits() async throws -> [TranslationUnitID] {
        pageRanges().map { range in
            TranslationUnitID(kind: .pdfPageRange, value: Self.encode(range))
        }
    }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard unit.kind == .pdfPageRange,
              let range = Self.decode(unit.value),
              pageRanges().contains(range) else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        guard let document = PDFDocument(url: fileURL) else {
            throw ChapterTextProviderError.sourceUnavailable(unit)
        }
        var parts: [String] = []
        for page in range.lowerBound...range.upperBound {
            if let text = document.page(at: page)?.string, !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n")
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        // A negative page predates the book's first unit and resolves to nil.
        guard let page = locator.page, page >= 0 else { return nil }
        let ranges = pageRanges()
        guard let last = ranges.last else { return nil }
        // A page past the last unit clamps to the last unit (it is still
        // inside a unit) — consistent with the TXT/MD adapters' boundary
        // contract (plan Decision 2.6).
        if page > last.upperBound { return TranslationUnitID(kind: .pdfPageRange, value: Self.encode(last)) }
        guard let range = ranges.first(where: { $0.contains(page) }) else {
            return nil
        }
        return TranslationUnitID(kind: .pdfPageRange, value: Self.encode(range))
    }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard unit.kind == .pdfPageRange, let range = Self.decode(unit.value) else {
            return nil
        }
        let ranges = pageRanges()
        guard let position = ranges.firstIndex(of: range),
              position + 1 < ranges.count else {
            return nil
        }
        return TranslationUnitID(kind: .pdfPageRange, value: Self.encode(ranges[position + 1]))
    }

    // MARK: - Page-range arithmetic

    /// The zero-indexed, inclusive page ranges for the open PDF. An empty list
    /// when the PDF cannot be opened or has no pages.
    private func pageRanges() -> [ClosedRange<Int>] {
        guard let document = PDFDocument(url: fileURL) else { return [] }
        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var start = 0
        while start < pageCount {
            let end = min(start + pagesPerUnit - 1, pageCount - 1)
            ranges.append(start...end)
            start = end + 1
        }
        return ranges
    }

    /// Encodes an inclusive page range as `"start-end"`.
    private static func encode(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)-\(range.upperBound)"
    }

    /// Decodes a `"start-end"` page-range string. Returns `nil` for a
    /// malformed value or an inverted range.
    private static func decode(_ value: String) -> ClosedRange<Int>? {
        let parts = value.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let start = Int(parts[0]), let end = Int(parts[1]),
              start >= 0, end >= start else {
            return nil
        }
        return start...end
    }
}
