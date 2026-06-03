// Feature #86 WI-3: the Chat context-scope selection — the scope-menu metadata,
// `AIChatViewModel.setScope` (re-assembly funnel), and `ReaderAICoordinator`'s
// scope-aware `scopedChatContext` / `refreshChatContext`. The SwiftUI bar/menu
// chrome is device-verified; this pins the pure logic.

import Testing
import Foundation
@testable import vreader

// MARK: - Scope menu metadata

@Suite("ChatContextScope menu copy (Feature #86 WI-3)")
struct ChatContextScopeMenuTests {

    @Test func menuDescription_perScope() {
        #expect(ChatContextScope.section.menuDescription == "Just the passage you’re reading")
        #expect(ChatContextScope.chapter.menuDescription == "The whole current chapter")
        #expect(ChatContextScope.bookSoFar.menuDescription == "Everything up to your page")
        #expect(ChatContextScope.wholeBook.menuDescription == "Reads the entire book on demand")
    }

    @Test func tokenEstimate_perScope_wholeBookIsOnDemand() {
        #expect(ChatContextScope.section.tokenEstimate == "~600 tokens")
        #expect(ChatContextScope.chapter.tokenEstimate == "~4.2k tokens")
        #expect(ChatContextScope.bookSoFar.tokenEstimate == "~58k tokens")
        #expect(ChatContextScope.wholeBook.tokenEstimate == "on-demand")
    }

    @Test func menuFooter_isSpoilerAwareOnlyForWholeBook() {
        #expect(ChatContextScope.menuFooter(forSelected: .wholeBook).contains("spoilers"))
        for scope in [ChatContextScope.section, .chapter, .bookSoFar] {
            #expect(ChatContextScope.menuFooter(forSelected: scope).contains("cost more"))
        }
    }
}

// MARK: - AIChatViewModel.setScope

@Suite("AIChatViewModel scope selection (Feature #86 WI-3)")
@MainActor
struct AIChatViewModelScopeTests {

    private func makeVM() -> AIChatViewModel {
        AIChatViewModel(
            aiService: AIService(
                featureFlags: FeatureFlags.shared,
                consentManager: AIConsentManager(),
                keychainService: KeychainService(),
                profileStore: ProviderProfileStore.shared
            ),
            bookFingerprint: nil
        )
    }

    @Test func defaultScope_isChapter() {
        #expect(makeVM().scope == .chapter)
    }

    @Test func setScope_changesScope_andInvokesCallback() {
        let vm = makeVM()
        var calls = 0
        vm.onScopeChanged = { calls += 1 }
        vm.setScope(.bookSoFar)
        #expect(vm.scope == .bookSoFar)
        #expect(calls == 1)
    }

    @Test func setScope_sameScope_isNoOp() {
        let vm = makeVM()
        var calls = 0
        vm.onScopeChanged = { calls += 1 }
        vm.setScope(.chapter)   // already .chapter
        #expect(calls == 0)
    }
}

// MARK: - ReaderAICoordinator scope-aware context

@Suite("ReaderAICoordinator scoped chat context (Feature #86 WI-3)")
@MainActor
struct ReaderAICoordinatorScopedContextTests {

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

    /// `.section` is the centered window; `.chapter` is the whole chapter — they
    /// differ for a multi-chapter book.
    @Test func scopedContext_sectionVsChapter() {
        let c = coordinator()
        let ch1 = String(repeating: "A", count: 3000)
        let ch2 = String(repeating: "B", count: 2000)
        c.loadedTextContent = ch1 + ch2
        c.tocEntries = toc([("Ch1", 0), ("Ch2", 3000)])
        c.currentLocator = locator(3000)

        #expect(c.scopedChatContext(.chapter) == ch2)
        #expect(c.scopedChatContext(.section) == c.currentTextContent)
        #expect(c.scopedChatContext(.chapter) != c.scopedChatContext(.section))
    }

    /// `.bookSoFar` reaches back to the book start (here within budget) — it
    /// includes chapter-1 text the `.chapter` (ch2-only) scope excludes.
    @Test func scopedContext_bookSoFar_reachesBackToStart() {
        let c = coordinator()
        let ch1 = String(repeating: "A", count: 1000)
        let ch2 = String(repeating: "B", count: 1000)
        c.loadedTextContent = ch1 + ch2
        c.tocEntries = toc([("Ch1", 0), ("Ch2", 1000)])
        c.currentLocator = locator(1500)   // mid chapter 2
        let soFar = c.scopedChatContext(.bookSoFar)
        #expect(soFar.contains("A"))       // includes chapter-1 text
    }

    /// `.wholeBook` retrieval lands in WI-5; until then it degrades to the broadest
    /// synchronous scope (`.bookSoFar`), NOT the narrow section.
    @Test func scopedContext_wholeBook_degradesToBookSoFar_untilWI5() {
        let c = coordinator()
        c.loadedTextContent = String(repeating: "A", count: 1000) + String(repeating: "B", count: 1000)
        c.tocEntries = toc([("Ch1", 0), ("Ch2", 1000)])
        c.currentLocator = locator(1500)
        #expect(c.scopedChatContext(.wholeBook) == c.scopedChatContext(.bookSoFar))
    }

    /// An unresolvable scope (no loaded text) degrades to the section fallback for
    /// every scope.
    @Test func scopedContext_noLoadedText_degradesToSection() {
        let c = coordinator()
        c.loadedTextContent = nil
        for scope in ChatContextScope.allCases {
            #expect(c.scopedChatContext(scope) == c.currentTextContent)
        }
    }
}
