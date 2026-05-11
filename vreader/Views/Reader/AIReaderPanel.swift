// Purpose: Bottom sheet panel for AI summarization, translation, and chat in the reader.
// Displays AI response text, loading state, and error messages.
// Provides a tab picker to switch between Summarize, Translate, and Chat modes.
//
// Key decisions:
// - Uses AIAssistantViewModel for summarization state management.
// - Uses AITranslationViewModel for translation with bilingual display.
// - Uses AIChatViewModel for multi-turn chat with book context.
// - Segmented picker at the top switches between Summarize, Translate, and Chat tabs.
// - States: idle (with action button), loading (ProgressView),
//   complete (scrollable response), error (message + retry),
//   featureDisabled, consentRequired.
// - Dismiss button always available.
// - Locator and text content passed in from the reader container.
//
// @coordinates-with: AIAssistantViewModel.swift, AITranslationViewModel.swift,
//   AIChatViewModel.swift, ReaderContainerView.swift

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $selectedTab) {
                    ForEach(AIReaderTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("aiReaderTabPicker")

                Divider()

                switch selectedTab {
                case .summarize:
                    summarizeContent
                case .translate:
                    TranslationPanel(
                        viewModel: translationViewModel,
                        locator: locator,
                        textContent: textContent,
                        format: format
                    )
                case .chat:
                    AIChatView(viewModel: chatViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                    .accessibilityIdentifier("aiPanelDoneButton")
                }
                // Feature #50 WI-7: in-reader provider picker. Lives in
                // the trailing slot so the user can flip the active
                // provider without leaving the reader. Persists to the
                // shared ProviderProfileStore; every in-flight AIService
                // call picks the new provider up via resolveProvider.
                ToolbarItem(placement: .topBarTrailing) {
                    AIProviderPicker(viewModel: providerPickerViewModel)
                }
            }
        }
        .accessibilityIdentifier("aiReaderPanel")
        .onAppear { selectedTab = initialTab } // bug #95
    }

    // MARK: - Summarize Tab Content

    @ViewBuilder
    private var summarizeContent: some View {
        switch viewModel.state {
        case .idle:
            idleView
        case .loading:
            loadingView
        case .complete:
            completeView
        case .error(let message):
            errorView(message: message)
        case .featureDisabled:
            featureDisabledView
        case .consentRequired:
            consentRequiredView
        case .streaming:
            // Streaming uses same display as complete (text accumulates)
            completeView
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Summarize the current section")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await viewModel.summarize(
                        locator: locator,
                        textContent: textContent,
                        format: format
                    )
                }
            } label: {
                Label("Summarize", systemImage: "text.quote")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("aiSummarizeButton")

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Generating summary\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .accessibilityIdentifier("aiPanelLoading")
    }

    @ViewBuilder
    private var completeView: some View {
        ScrollView {
            Text(viewModel.responseText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .accessibilityIdentifier("aiPanelResponse")

        Divider()

        HStack {
            Button {
                viewModel.reset()
            } label: {
                Label("New Request", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("aiNewRequestButton")

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task {
                    await viewModel.summarize(
                        locator: locator,
                        textContent: textContent,
                        format: format
                    )
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("aiRetryButton")

            Spacer()
        }
        .accessibilityIdentifier("aiPanelError")
    }

    @ViewBuilder
    private var featureDisabledView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("AI features are currently disabled.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Enable AI in Settings to use this feature.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("aiPanelDisabled")
    }

    @ViewBuilder
    private var consentRequiredView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "hand.raised")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("AI features require your consent.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Grant consent in Settings to use AI features.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Grant Consent") {
                viewModel.grantConsent()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("aiGrantConsentButton")

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("aiPanelConsent")
    }
}
#endif
