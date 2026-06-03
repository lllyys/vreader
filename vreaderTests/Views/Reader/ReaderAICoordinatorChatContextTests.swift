// Feature #86 WI-1: the Chat tab's `bookContext` covers the WHOLE current
// chapter (not the fixed ~2500-char `.section` window), via the #69 scope stack
// reused through `ReaderAICoordinator.chatContext`. These pin the pure-logic
// seam: chapter scope when bounds resolve, degrade to `.section` when they don't
// (EPUB / no TOC / no locator), and the budget clamp for an over-budget chapter.
// The host wiring (refreshChatContext on text/locator/TOC change) is device-verified.

import Testing
import Foundation
@testable import vreader

@Suite("ReaderAICoordinator chat context (Feature #86 WI-1)")
@MainActor
struct ReaderAICoordinatorChatContextTests {

    private func fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 100, format: .txt
        )
    }
    private func coordinator() -> ReaderAICoordinator {
        ReaderAICoordinator(
            fallbackTitle: "Title", bookFormat: .txt,
            fingerprintKey: fingerprint().canonicalKey
        )
    }
    private func locator(_ offset: Int) -> Locator {
        Locator.validated(bookFingerprint: fingerprint(), charOffsetUTF16: offset)!
    }
    private func toc(_ pairs: [(String, Int)]) -> [TOCEntry] {
        pairs.map { TOCEntry(title: $0.0, level: 0, locator: locator($0.1)) }
    }

    /// A TXT-shaped TOC (char-offset locators) → the chat context is the WHOLE
    /// current chapter, not the centered 2500-char section window.
    @Test func chatContext_withChapterBounds_returnsChapterNotSectionWindow() {
        let c = coordinator()
        let chapter1 = String(repeating: "A", count: 3000)
        let chapter2 = String(repeating: "B", count: 2000)
        c.loadedTextContent = chapter1 + chapter2
        c.tocEntries = toc([("Ch1", 0), ("Ch2", 3000)])
        c.currentLocator = locator(3000)  // start of chapter 2

        #expect(c.chatContext == chapter2)               // whole chapter 2
        #expect(c.chatContext != c.currentTextContent)   // != the section window
    }

    /// An empty (EPUB-shaped, non-char-offset) TOC → degrade to the section.
    @Test func chatContext_emptyTOC_degradesToSection() {
        let c = coordinator()
        c.loadedTextContent = String(repeating: "A", count: 5000)
        c.tocEntries = []
        c.currentLocator = locator(2500)
        #expect(c.chatContext == c.currentTextContent)
    }

    /// No locator → degrade to the section.
    @Test func chatContext_noLocator_degradesToSection() {
        let c = coordinator()
        c.loadedTextContent = String(repeating: "A", count: 5000)
        c.tocEntries = toc([("Ch1", 0)])
        c.currentLocator = nil
        #expect(c.chatContext == c.currentTextContent)
    }

    /// No loaded text → the same fallback the section path returns.
    @Test func chatContext_noLoadedText_returnsFallback() {
        let c = coordinator()
        c.loadedTextContent = nil
        #expect(c.chatContext == c.currentTextContent)
    }

    /// A chapter larger than the budget is clamped (the extractor's centered
    /// window) so per-request tokens stay bounded.
    @Test func chatContext_overBudgetChapter_clampsToBudget() {
        let c = coordinator()
        c.loadedTextContent = String(repeating: "A", count: 20_000)
        c.tocEntries = toc([("Ch1", 0)])
        c.currentLocator = locator(5000)
        #expect(c.chatContext.utf16.count <= AIContextBudget.defaultMaxUTF16)
    }
}
