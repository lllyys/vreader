// Purpose: Bottom sheet panel for AI summarization, translation, and chat in the reader.
// Displays AI response text, loading state, and error messages.
// Provides a tab picker to switch between Summarize, Translate, and Chat modes.
//
// Re-skinned for feature #60 visual-identity v2 (WI-10): wrapped in the
// shared `ReaderSheetChrome` with `title: nil` (no standard title bar)
// and the design `AISheet`'s custom header — a sparkle accent avatar,
// the "AI Assistant" / "with this book's context" titles, and a close
// button. The Summarize/Chat/Translate tab picker and every tab's
// wiring (the real provider/streaming calls, the feature-#50 provider
// picker, retry, consent) are preserved unchanged.
//
// Key decisions:
// - Uses AIAssistantViewModel for summarization state management.
// - Uses AITranslationViewModel for translation with bilingual display.
// - Uses AIChatViewModel for multi-turn chat with book context.
// - Segmented picker at the top switches between Summarize, Translate, and Chat tabs.
// - The Summarize tab body is the re-skinned `AISummaryTabView`
//   (feature #65 WI-1) — its summary card's Share chip presents a
//   `ShareActivityView` carrying the summary text.
// - The Chat tab body is the re-skinned `AIChatView` (feature #65
//   WI-2) — it takes the v2 `theme` for its bubble forms + pill input.
// - Dismiss button always available (the header's close button).
// - The feature-#50 in-reader provider picker is preserved — it sits in
//   the custom header next to the close button so a user can still flip
//   providers without leaving the reader.
// - Locator and text content passed in from the reader container.
//
// @coordinates-with: AIAssistantViewModel.swift, AITranslationViewModel.swift,
//   AIChatViewModel.swift, AISummaryTabView.swift, ShareSheet.swift,
//   ReaderContainerView.swift, ReaderSheetChrome.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The active tab in the AI reader panel.
enum AIReaderTab: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case translate = "Translate"
    case chat = "Chat"

    var id: String { rawValue }
}

/// Bottom sheet panel showing AI summarization and translation results.
struct AIReaderPanel: View {

    /// The AI assistant view model (shared with the reader).
    @Bindable var viewModel: AIAssistantViewModel

    /// The translation view model for bilingual translation.
    @Bindable var translationViewModel: AITranslationViewModel

    /// The chat view model for multi-turn AI chat.
    @Bindable var chatViewModel: AIChatViewModel

    /// The current locator for context extraction.
    let locator: Locator

    /// The full text content of the current section/page/chapter.
    let textContent: String

    /// The book format (determines context extraction strategy).
    let format: BookFormat

    /// Dismiss action provided by the presenting sheet.
    let onDismiss: () -> Void

    /// Visual-identity-v2 theme tokens for the sheet chrome (feature
    /// #60 WI-10). Defaults to `.paper` so existing callers / previews
    /// that omit it keep working.
    var theme: ReaderThemeV2 = .paper

    /// Initial tab to show (e.g., .translate from readerTranslateRequested). (bug #95)
    var initialTab: AIReaderTab = .summarize

    /// The currently selected tab.
    @State private var selectedTab: AIReaderTab = .summarize

    /// Feature #50 WI-7: in-reader provider picker. Owned by this view
    /// so its state survives tab changes and stays in sync with the
    /// shared ProviderProfileStore across reopens. Constructed once on
    /// init; the @State wrapper preserves the instance across body
    /// re-evaluations.
    @State private var providerPickerViewModel = AIProviderPickerViewModel()

    /// Feature #65 WI-1: the summary text to share. Set by the
    /// `AISummaryTabView` summary card's Share chip; presenting the
    /// `.sheet(item:)` with a non-nil value shows `ShareActivityView`.
    @State private var summaryShareItem: SummaryShareItem?

    var body: some View {
        ReaderSheetChrome(theme: theme, title: nil) {
            VStack(spacing: 0) {
                AIReaderPanelHeader(
                    theme: theme,
                    providerPickerViewModel: providerPickerViewModel,
                    onDismiss: onDismiss
                )

                Picker("Mode", selection: $selectedTab) {
                    ForEach(AIReaderTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("aiReaderTabPicker")

                Color(theme.ruleColor).frame(height: 0.5)

                switch selectedTab {
                case .summarize:
                    AISummaryTabView(
                        viewModel: viewModel,
                        locator: locator,
                        textContent: textContent,
                        format: format,
                        theme: theme,
                        onShare: { summaryShareItem = SummaryShareItem(text: $0) }
                    )
                case .translate:
                    TranslationPanel(
                        viewModel: translationViewModel,
                        locator: locator,
                        textContent: textContent,
                        format: format,
                        theme: theme
                    )
                case .chat:
                    AIChatView(viewModel: chatViewModel, theme: theme)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("aiReaderPanel")
        .onAppear { selectedTab = initialTab } // bug #95
        .sheet(item: $summaryShareItem) { item in
            ShareActivityView(activityItems: [item.text])
                .ignoresSafeArea()
        }
    }
}

/// Feature #65 WI-1: an `Identifiable` wrapper so the summary text can
/// drive a `.sheet(item:)` presenting `ShareActivityView`. A fresh
/// `id` per instance means each Share tap re-presents the sheet.
struct SummaryShareItem: Identifiable {
    let id = UUID()
    let text: String
}
#endif
