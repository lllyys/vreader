// Purpose: Manages AI panel setup, view model lifecycle, and book text loading for AI context.
// Extracted from ReaderContainerView to reduce file size (pure refactor).
//
// @coordinates-with ReaderContainerView.swift, AIReaderPanel.swift,
//   AIReaderAvailability.swift, AIAssistantViewModel.swift,
//   AITranslationViewModel.swift, AIChatViewModel.swift

import SwiftUI
import PDFKit

/// Owns the AI-related state: view models, text content, and context extraction.
@Observable
@MainActor
final class ReaderAICoordinator {

    /// AI summarization view model. Nil until `setupIfNeeded()` succeeds.
    private(set) var aiViewModel: AIAssistantViewModel?
    /// AI translation view model. Nil until `setupIfNeeded()` succeeds.
    private(set) var translationViewModel: AITranslationViewModel?
    /// AI chat view model. Nil until `setupIfNeeded()` succeeds.
    private(set) var chatViewModel: AIChatViewModel?

    /// Full text content loaded from the book file. Used as the source for AI context extraction.
    var loadedTextContent: String?

    /// Current reading position locator, updated via `.readerPositionDidChange` notification.
    /// Used by AIContextExtractor to determine which section to send as AI context.
    var currentLocator: Locator?

    /// Feature #86 WI-1: the reader's TOC entries, synced from the host so
    /// `chatContext` can resolve the current chapter's span. Empty until the host
    /// loads + syncs the TOC (a late TOC upgrades the chat context on the next
    /// `refreshChatContext()`).
    var tocEntries: [TOCEntry] = []

    /// Whether the AI assistant button should be visible.
    var isAIAvailable: Bool {
        AIReaderAvailability.isAvailable(
            featureFlags: FeatureFlags.shared,
            keychainService: KeychainService(),
            consentManager: AIConsentManager()
        )
    }

    /// Text content for AI context. Extracts ~2500 chars around the current reading position
    /// using AIContextExtractor, instead of sending the entire book.
    var currentTextContent: String {
        guard let loaded = loadedTextContent, !loaded.isEmpty else {
            return fallbackTitle.isEmpty ? "No content available" : fallbackTitle
        }
        let extractor = AIContextExtractor()
        if let locator = currentLocator {
            let extracted = extractor.extractContext(
                locator: locator,
                textContent: loaded,
                format: bookFormat
            )
            if !extracted.isEmpty { return extracted }
        }
        // Fallback: extract from beginning
        return String(loaded.prefix(extractor.targetCharacterCount))
    }

    /// Feature #86 WI-1: the Chat tab's book context — the WHOLE current chapter
    /// (not the fixed ~2500-char `.section` window), bounded by the
    /// `AIContextBudget.defaultMaxUTF16` (12_000) budget. Resolves the chapter via
    /// the #69 scope stack (`SummaryScopeResolver` + `AIContextExtractor`). When
    /// the chapter can't be resolved — EPUB / non-char-offset TOC, no locator, or
    /// no loaded text — it **degrades to `currentTextContent` (`.section`)**, so
    /// EPUB chat and the no-context fallback are unchanged.
    var chatContext: String { scopedChatContext(.chapter) }

    /// Feature #86 WI-3: the Chat tab's book context for a GIVEN scope. The three
    /// bounded scopes map onto the #69 `AIContextExtractor` stack:
    /// `.section` → the ~2500-char window; `.chapter` → the TOC-chapter slice;
    /// `.bookSoFar` → the budget-capped prefix to the locator. `.wholeBook`
    /// retrieval lands in WI-5 — until then it degrades to `.bookSoFar` (the
    /// broadest synchronous scope). Any unresolvable case degrades to
    /// `currentTextContent` (`.section`), so EPUB chat / no-context are unchanged.
    func scopedChatContext(_ scope: ChatContextScope) -> String {
        let section = currentTextContent
        guard let summaryScope = scope.summaryScope else {
            // .wholeBook (WI-5b): use the retrieved digest once available; until the
            // read completes, fall back to the broadest synchronous scope.
            if let digest = chatViewModel?.wholeBookRetrieval?.availableContext, !digest.isEmpty {
                return digest
            }
            return scopedChatContext(.bookSoFar)
        }
        if summaryScope == .section { return section }
        guard let loaded = loadedTextContent, !loaded.isEmpty,
              let locator = currentLocator
        else { return section }
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator, tocEntries: tocEntries, totalTextLengthUTF16: loaded.utf16.count
        )
        // Chapter needs resolved bounds; book-so-far does not.
        if summaryScope == .chapter, bounds == nil { return section }
        let extracted = AIContextExtractor().extractContext(
            locator: locator,
            fullText: loaded,
            format: bookFormat,
            scope: summaryScope,
            chapterBounds: bounds,
            maxUTF16: AIContextBudget.defaultMaxUTF16
        )
        return extracted.isEmpty ? section : extracted
    }

    /// Feature #86 WI-1/WI-3: the SINGLE place the chat's `bookContext` is
    /// assigned. Idempotent — recomputes from the current
    /// `loadedTextContent` / `currentLocator` / `tocEntries` for the chat's
    /// currently-selected scope (`.chapter` until the user changes it). The host
    /// calls this on every state change (text load, locator change, TOC arrival),
    /// and the chat VM calls it on a scope change, so a late TOC upgrades the
    /// context and a scroll never reverts it.
    func refreshChatContext() {
        guard let chatVM = chatViewModel else { return }
        let scopeText = scopedChatContext(chatVM.scope)
        // Feature #86 WI-4: fold in the reader's selected annotation kinds, read
        // from the in-memory cache (NO SwiftData fetch on relocate). When no cache
        // exists (AI without persistence), the block is empty → WI-1/3 behavior.
        let block = chatAnnotationCache?.annotationBlock(
            for: chatVM.sources, maxUTF16: AIContextBudget.defaultMaxUTF16
        ) ?? ""
        // Feature #86 WI-6: compute the provenance citations the context drew on;
        // the assembler retains only those that survive the budget clamp.
        let counts = chatAnnotationCache?.counts ?? (0, 0, 0)
        // Gate the whole-book coverage citation on the SAME condition the scope text
        // uses (a non-empty `availableContext` — i.e. .ready/.partial), so a stale
        // digest that survived disarm can't stamp a whole-book span on a send that
        // actually used the book-so-far fallback (Gate-4 High).
        let usesWholeBookDigest = chatVM.scope == .wholeBook
            && (chatVM.wholeBookRetrieval?.availableContext?.isEmpty == false)
        let wholeBookCoverage = usesWholeBookDigest
            ? chatVM.wholeBookRetrieval?.digest?.coverage : nil
        let citations = ChatCitationFactory.citations(
            scope: chatVM.scope, sources: chatVM.sources, counts: counts,
            wholeBookCoverage: wholeBookCoverage
        )
        let assembly = ChatContextAssembler.assemble(
            scopeText: scopeText, annotationBlock: block, citations: citations,
            maxUTF16: AIContextBudget.defaultMaxUTF16
        )
        chatVM.bookContext = assembly.bookContext
        chatVM.pendingCitations = assembly.citations
    }

    /// Feature #86 WI-4: the per-book annotation cache backing the sources chip.
    /// Created in `setupIfNeeded` when persistence is available.
    private(set) var chatAnnotationCache: ChatAnnotationCache?

    /// Pushes the cache's current per-kind counts to the chat VM's sources chip.
    private func syncSourceCounts() {
        chatViewModel?.sourceCounts = chatAnnotationCache?.counts ?? (0, 0, 0)
    }

    /// The pinned AI service for whole-book retrieval (WI-5b). Set in setupIfNeeded.
    private var pinnedAIService: AIService?

    /// The chat scope last seen by the funnel — so a whole-book read is armed only
    /// on the TRANSITION into `.wholeBook`, not on every sources toggle (Gate-4
    /// High: a sources change must NOT downgrade a `.ready` digest back to armed).
    private var lastChatScope: ChatContextScope = .chapter

    /// Feature #86 WI-5b: a scope/sources change. Arms whole-book retrieval ONLY
    /// when the scope transitions into `.wholeBook` (disarms when it leaves); a
    /// source-only toggle preserves `.ready`/`.partial`. Always re-assembles via
    /// the single funnel.
    private func handleChatContextChanged() {
        let scope = chatViewModel?.scope ?? .chapter
        if let retrieval = chatViewModel?.wholeBookRetrieval {
            if scope == .wholeBook, lastChatScope != .wholeBook {
                retrieval.arm()                       // transition INTO whole-book
            } else if scope != .wholeBook, retrieval.phase != .idle {
                retrieval.disarm()                    // left whole-book
            }
            // scope unchanged (e.g. a sources toggle) → preserve the read state.
        }
        lastChatScope = scope
        refreshChatContext()
    }

    /// Feature #86 WI-5b: the on-demand whole-book read. Resolves ONE provider
    /// config (pinned for the whole job), drives `WholeBookRetrievalViewModel.read`
    /// with a `condense` closure that summarizes each chunk, awaits completion, and
    /// re-assembles the context so the digest becomes the scope text.
    func runWholeBookRead() async {
        guard let retrieval = chatViewModel?.wholeBookRetrieval,
              let service = pinnedAIService,
              let text = loadedTextContent, !text.isEmpty
        else { return }
        if retrieval.isReady { return }
        if case .reading = retrieval.phase { await retrieval.readTask?.value; return }

        do {
            let config = try await service.resolveActiveProviderConfig()
            retrieval.read(
                fullText: text,
                chunkBudgetUTF16: AIContextBudget.defaultMaxUTF16,
                digestBudgetUTF16: AIContextBudget.defaultMaxUTF16,
                maxChunks: 30,   // overflow bound on provider calls — large books read a bounded digest
                condense: { chunk in
                    let request = AIRequest(
                        actionType: .summarize, bookFingerprint: nil, locator: nil,
                        contextText: chunk,
                        userPrompt: "Summarize the key events, characters, and ideas in this passage concisely.",
                        targetLanguage: nil, promptVersion: "v1"
                    )
                    return try await service.sendRequest(request, using: config).content
                }
            )
            await retrieval.readTask?.value
        } catch {
            // Provider/config failure → the VM lands in .partial; the scope text
            // falls back to book-so-far. Never blocks the send.
        }
        refreshChatContext()
    }

    /// Book title used as fallback when no text content is available.
    private let fallbackTitle: String
    /// Resolved book format for context extraction.
    private let bookFormat: BookFormat
    /// Fingerprint key for creating chat VM.
    private let fingerprintKey: String
    /// Annotation stores for the sources cache (the `PersistenceActor`, which
    /// conforms to all three). Nil when persistence isn't injected.
    private let annotationStores: (any AnnotationPersisting & HighlightPersisting & BookmarkPersisting)?

    /// Feature #88: the chat-session store (the `PersistenceActor`, which conforms
    /// to `ChatSessionPersisting`). Injected into the book-chat VM so a reader chat
    /// persists multiple switchable conversations. Nil when no persistence is
    /// injected (the chat stays ephemeral).
    private let chatSessionStore: (any ChatSessionPersisting)?

    init(
        fallbackTitle: String,
        bookFormat: BookFormat,
        fingerprintKey: String,
        annotationStores: (any AnnotationPersisting & HighlightPersisting & BookmarkPersisting)? = nil,
        chatSessionStore: (any ChatSessionPersisting)? = nil
    ) {
        self.fallbackTitle = fallbackTitle
        self.bookFormat = bookFormat
        self.fingerprintKey = fingerprintKey
        self.annotationStores = annotationStores
        self.chatSessionStore = chatSessionStore
    }

    /// Creates the AI ViewModels if AI features are available.
    func setupIfNeeded() {
        guard aiViewModel == nil, isAIAvailable else { return }
        let flags = FeatureFlags.shared
        let keychain = KeychainService()
        // Feature #50 WI-5: AIService now dispatches on the active
        // ProviderProfile via ProviderProfileStore.shared. The shared
        // store is mandatory in production (Gate-2 round-2 finding [2]).
        let service = AIService(
            featureFlags: flags,
            consentManager: AIConsentManager(),
            keychainService: keychain,
            profileStore: ProviderProfileStore.shared
        )
        let summaryVM = AIAssistantViewModel(aiService: service)
        aiViewModel = summaryVM
        // Feature #90 WI-2 (Gate-4 M1): seed the Summarize-tab bilingual target
        // language from the book's ESTABLISHED per-book bilingual setting, so the
        // summary inherits the reader's chosen language instead of the global
        // default. Sets the language only — no translation kicks at setup (there
        // is no summary yet).
        if let override = PerBookSettingsStore.settings(
            for: fingerprintKey, baseURL: ReaderContainerView.perBookSettingsBaseURL),
           let langKey = override.bilingualTargetLanguage {
            summaryVM.setSummaryTargetLanguage(BilingualLanguage.findOrDefault(key: langKey))
        }
        translationViewModel = AITranslationViewModel(aiService: service)

        let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey)
        let chatVM = AIChatViewModel(
            aiService: service,
            bookFingerprint: fingerprint,
            chatSessionStore: chatSessionStore   // Feature #88: persisted sessions (nil ⇒ ephemeral)
        )
        chatViewModel = chatVM
        // Feature #88 WI-3: trigger the ONE-SHOT session load from the long-lived
        // coordinator (idempotent + non-clobbering), NOT from `AIChatView.task`
        // (which reruns on every Chat-tab re-entry and would clobber a fresh /
        // unsaved thread — Gate-2 round-3). A nil store / general chat no-ops.
        if chatSessionStore != nil {
            Task { @MainActor [weak chatVM] in await chatVM?.loadSessions() }
        }
        // Feature #91: when agenticTools is ON, build the agentic tool registry over
        // the persistent FTS store + the persistence actor (also a LibraryPersisting)
        // OFF-MAIN (the cold SQLite open is heavy), then inject it. A build failure
        // (e.g. the store can't open) → nil → the chat stays on the non-agentic path.
        // Gated on the flag so there's zero cost OFF.
        if FeatureFlags.shared.agenticTools, let library = annotationStores as? any LibraryPersisting {
            Task { @MainActor [weak chatVM] in
                let registry = try? await AgenticToolRegistryBuilder.buildLive(
                    currentBook: fingerprint, library: library)
                chatVM?.setAgenticRegistry(registry)
            }
        }
        pinnedAIService = service
        // Feature #86 WI-5b: the whole-book retrieval state machine.
        chatVM.wholeBookRetrieval = WholeBookRetrievalViewModel()
        chatVM.onWholeBookReadRequested = { [weak self] in await self?.runWholeBookRead() }
        // Feature #86 WI-3/4/5b: re-assemble the context when the user changes scope
        // OR toggles sources, through the same single funnel; whole-book select arms.
        chatVM.onScopeChanged = { [weak self] in self?.handleChatContextChanged() }

        // Feature #86 WI-4: the sources cache. Loads once now and refreshes on
        // `.readerAnnotationsDidChange`; each (re)load re-assembles the context +
        // updates the chip counts.
        if let stores = annotationStores {
            let cache = ChatAnnotationCache(
                fingerprintKey: fingerprintKey,
                annotationStore: stores, highlightStore: stores, bookmarkStore: stores
            )
            cache.onChange = { [weak self] in
                self?.syncSourceCounts()
                self?.refreshChatContext()
            }
            chatAnnotationCache = cache
            Task { await cache.load() }   // populates, then fires onChange
        }

        // Feature #86 WI-1: assign chatViewModel FIRST, then refresh — else the
        // refresh no-ops against a nil VM (Gate-2 round-2 note).
        refreshChatContext()
    }

    /// Loads text content from the book file for AI context extraction.
    /// For TXT/MD: reads the full text file.
    /// For PDF: extracts text from all pages via PDFKit.
    /// For EPUB: reads spine items via EPUBParser + HTML stripping.
    /// The full text is stored in `loadedTextContent`; AIContextExtractor then
    /// extracts only the relevant section (~2500 chars) around the current position.
    func loadBookTextContent(fileURL: URL, format: String) async {
        guard loadedTextContent == nil else { return }

        let text: String? = await Task.detached {
            switch format {
            case "txt", "md":
                return try? String(contentsOf: fileURL, encoding: .utf8)

            case "pdf":
                guard let doc = PDFKit.PDFDocument(url: fileURL) else { return nil }
                var pages: [String] = []
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i), let text = page.string {
                        pages.append(text)
                    }
                }
                return pages.joined(separator: "\n\n")

            case "epub":
                // Extract text from EPUB spine items via EPUBParser + HTML stripping.
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: fileURL)
                    var textParts: [String] = []
                    for item in metadata.spineItems {
                        if let xhtml = try? await parser.contentForSpineItem(href: item.href) {
                            let plain = EPUBTextExtractor.stripHTML(xhtml)
                            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                textParts.append(trimmed)
                            }
                        }
                    }
                    await parser.close()
                    return textParts.isEmpty ? nil : textParts.joined(separator: "\n\n")
                } catch {
                    await parser.close()
                    return nil
                }

            default:
                return nil
            }
        }.value

        if let text, !text.isEmpty {
            loadedTextContent = text
            // Feature #86 WI-1: refresh the chat context (chapter-scoped) through
            // the single funnel, not a direct section write.
            refreshChatContext()
        }
    }
}
