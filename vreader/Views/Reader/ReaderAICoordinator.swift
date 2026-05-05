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

    /// Book title used as fallback when no text content is available.
    private let fallbackTitle: String
    /// Resolved book format for context extraction.
    private let bookFormat: BookFormat
    /// Fingerprint key for creating chat VM.
    private let fingerprintKey: String

    init(fallbackTitle: String, bookFormat: BookFormat, fingerprintKey: String) {
        self.fallbackTitle = fallbackTitle
        self.bookFormat = bookFormat
        self.fingerprintKey = fingerprintKey
    }

    /// Creates the AI ViewModels if AI features are available.
    func setupIfNeeded() {
        guard aiViewModel == nil, isAIAvailable else { return }
        let flags = FeatureFlags.shared
        let keychain = KeychainService()
        let service = AIService(
            featureFlags: flags,
            consentManager: AIConsentManager(),
            keychainService: keychain,
            providerFactory: { apiKey, config in
                OpenAICompatibleProvider(
                    baseURL: config.endpoint,
                    apiKey: apiKey,
                    model: config.model
                )
            }
        )
        aiViewModel = AIAssistantViewModel(aiService: service)
        translationViewModel = AITranslationViewModel(aiService: service)

        let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey)
        let chatVM = AIChatViewModel(aiService: service, bookFingerprint: fingerprint)
        chatVM.bookContext = currentTextContent
        chatViewModel = chatVM
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
            // Update chat VM book context with extracted section (not full text)
            chatViewModel?.bookContext = currentTextContent
        }
    }
}
