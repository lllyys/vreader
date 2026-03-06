// Purpose: Extracts text from PDF documents using PDFKit for search indexing.
// Each page becomes one TextUnit with sourceUnitId "pdf:page:<N>".
//
// Key decisions:
// - Uses PDFKit (system framework, no dependencies).
// - Pages are zero-indexed to match Locator.page convention.
// - Empty pages are included (empty text) to maintain page index alignment.
//
// @coordinates-with SearchTextExtractor.swift

import Foundation
import PDFKit

/// Extracts text from PDF documents for search indexing.
struct PDFTextExtractor: SearchTextExtractor {

    func extractTextUnits(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) async throws -> [TextUnit] {
        guard let document = PDFDocument(url: url) else {
            throw PDFTextExtractorError.cannotOpenPDF(url.lastPathComponent)
        }

        var units: [TextUnit] = []
        let pageCount = document.pageCount

        for i in 0..<pageCount {
            let pageText = document.page(at: i)?.string ?? ""
            units.append(TextUnit(
                sourceUnitId: "pdf:page:\(i)",
                text: pageText
            ))
        }

        return units
    }
}

/// Errors during PDF text extraction.
enum PDFTextExtractorError: Error, Sendable {
    case cannotOpenPDF(String)
}
