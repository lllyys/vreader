// Purpose: Locator restoration with format-specific fallback chains.
//
// Each format has a prioritized chain of strategies:
// - EPUB: CFI → href+progression → quote recovery → failed
// - PDF:  page → quote recovery → failed
// - TXT:  charOffset → charRange → quote recovery → failed
//
// Quote recovery uses QuoteRecovery for text-based fallback when structural
// anchors (CFI, page, offset) become stale after content changes.
//
// @coordinates-with Locator.swift, QuoteRecovery.swift

import Foundation

/// The strategy that succeeded during locator restoration.
enum RestorationStrategy: String, Sendable {
    /// EPUB: restored via CFI (pass-through — actual resolution is Readium's job).
    case cfi
    /// EPUB: restored via href + progression within spine.
    case hrefProgression
    /// Any format: restored via text quote search.
    case quoteRecovery
    /// PDF: restored via page index.
    case pageIndex
    /// TXT: restored via UTF-16 character offset.
    case utf16Offset
    /// Could not restore using any strategy.
    case failed
}

/// Result of attempting to restore a locator to a concrete position.
struct RestorationResult: Sendable {
    /// The strategy that succeeded.
    let strategy: RestorationStrategy
    /// For TXT: the resolved UTF-16 offset in the current text.
    let resolvedUTF16Offset: Int?
    /// For PDF: the resolved page index.
    let resolvedPage: Int?
    /// For EPUB: the resolved href.
    let resolvedHref: String?
    /// For EPUB: the resolved progression within the href.
    let resolvedProgression: Double?
    /// Confidence in the restoration (from quote recovery).
    let confidence: QuoteConfidence?
}

/// Stateless restoration logic for saved Locators.
enum LocatorRestorer {

    // MARK: - EPUB Restoration

    /// Attempts EPUB restoration: CFI -> href+progression -> quote recovery.
    /// - Parameters:
    ///   - locator: The saved locator to restore.
    ///   - spineHrefs: Available spine item hrefs in the current EPUB.
    ///   - textContent: Optional full text of the target spine item (for quote recovery).
    static func restoreEPUB(
        locator: Locator,
        spineHrefs: [String],
        textContent: String?
    ) -> RestorationResult {
        // Strategy 1: CFI pass-through (non-empty only)
        if let cfi = locator.cfi, !cfi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RestorationResult(
                strategy: .cfi,
                resolvedUTF16Offset: nil,
                resolvedPage: nil,
                resolvedHref: nil,
                resolvedProgression: nil,
                confidence: nil
            )
        }

        // Strategy 2: href + progression
        if let href = locator.href,
           let progression = locator.progression,
           spineHrefs.contains(href) {
            return RestorationResult(
                strategy: .hrefProgression,
                resolvedUTF16Offset: nil,
                resolvedPage: nil,
                resolvedHref: href,
                resolvedProgression: progression,
                confidence: nil
            )
        }

        // Strategy 3: Quote recovery
        if let result = attemptQuoteRecovery(locator: locator, text: textContent) {
            return result
        }

        return failedResult
    }

    // MARK: - PDF Restoration

    /// Attempts PDF restoration: page -> quote recovery.
    /// - Parameters:
    ///   - locator: The saved locator to restore.
    ///   - totalPages: Total number of pages in the current PDF.
    ///   - pageText: Text of the target page for quote search.
    static func restorePDF(
        locator: Locator,
        totalPages: Int,
        pageText: String?
    ) -> RestorationResult {
        // Strategy 1: Page index (0-indexed, must be < totalPages)
        if let page = locator.page, page >= 0, page < totalPages {
            return RestorationResult(
                strategy: .pageIndex,
                resolvedUTF16Offset: nil,
                resolvedPage: page,
                resolvedHref: nil,
                resolvedProgression: nil,
                confidence: nil
            )
        }

        // Strategy 2: Quote recovery
        if let result = attemptQuoteRecovery(locator: locator, text: pageText) {
            return result
        }

        return failedResult
    }

    // MARK: - TXT Restoration

    /// Attempts TXT restoration: offset -> range -> quote recovery.
    /// - Parameters:
    ///   - locator: The saved locator to restore.
    ///   - currentText: The current full text of the document.
    static func restoreTXT(
        locator: Locator,
        currentText: String
    ) -> RestorationResult {
        let textLength = currentText.utf16.count

        // Strategy 1: charOffsetUTF16
        if let offset = locator.charOffsetUTF16, offset >= 0, offset <= textLength {
            return RestorationResult(
                strategy: .utf16Offset,
                resolvedUTF16Offset: offset,
                resolvedPage: nil,
                resolvedHref: nil,
                resolvedProgression: nil,
                confidence: nil
            )
        }

        // Strategy 2: charRangeStartUTF16 + charRangeEndUTF16
        if let start = locator.charRangeStartUTF16,
           let end = locator.charRangeEndUTF16,
           start >= 0, end >= start, end <= textLength {
            return RestorationResult(
                strategy: .utf16Offset,
                resolvedUTF16Offset: start,
                resolvedPage: nil,
                resolvedHref: nil,
                resolvedProgression: nil,
                confidence: nil
            )
        }

        // Strategy 3: Quote recovery
        if let result = attemptQuoteRecovery(locator: locator, text: currentText) {
            return result
        }

        return failedResult
    }

    // MARK: - Private Helpers

    /// Attempts quote recovery using the locator's textQuote and context fields.
    /// Returns nil if quote is absent or not found.
    private static func attemptQuoteRecovery(
        locator: Locator,
        text: String?
    ) -> RestorationResult? {
        guard let quote = locator.textQuote, let text, !text.isEmpty else {
            return nil
        }

        guard let recovery = QuoteRecovery.findQuote(
            quote: quote,
            contextBefore: locator.textContextBefore,
            contextAfter: locator.textContextAfter,
            in: text
        ) else {
            return nil
        }

        return RestorationResult(
            strategy: .quoteRecovery,
            resolvedUTF16Offset: recovery.utf16Offset,
            resolvedPage: nil,
            resolvedHref: nil,
            resolvedProgression: nil,
            confidence: recovery.confidence
        )
    }

    /// Convenience for a failed restoration result.
    private static var failedResult: RestorationResult {
        RestorationResult(
            strategy: .failed,
            resolvedUTF16Offset: nil,
            resolvedPage: nil,
            resolvedHref: nil,
            resolvedProgression: nil,
            confidence: nil
        )
    }
}
