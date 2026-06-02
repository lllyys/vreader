// Purpose: Feature #81 — the SCOPED in-reader AI Providers list, pushed inside
// the bilingual setup sheet's NavigationStack from the engine strip's "Set up"
// / "Change…" button. Body is ONLY the provider list (reuses AIProviderListView
// + AIProviderEditSheet), NOT the full SettingsView — design Variant A.
//
// Renders the design's reader-specific chrome: a persistent "why-you're-here"
// context banner ("Choose the provider bilingual mode will use to translate
// this book.") above the list, and a bilingual-context empty state (gradient
// sparkle tile + "No providers yet" + keychain-privacy line + "Add provider"
// pill) supplied to AIProviderListView via its `emptyState` builder so the
// CTA still drives the canonical editor.
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-ai-provider-entry.jsx` (`AIProvidersSheetBody`).
//
// @coordinates-with: ReaderAIProvidersFlow.swift, BilingualSetupSheetContainer.swift,
//   AIProviderListView.swift, ReaderThemeV2.swift, ReaderSheetChrome.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx`

import SwiftUI

/// The scoped AI Providers list shown when the bilingual engine strip's "Set
/// up" / "Change…" is tapped. Pushed inside the bilingual sheet's
/// NavigationStack, so it carries the system nav bar (`‹ Bilingual` back +
/// "AI Providers" title + the reused list's `+`).
struct ReaderAIProvidersView: View {

    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2

    /// The flow model — owns the shared `AISettingsViewModel` and the
    /// activation/pop transitions.
    let flow: ReaderAIProvidersFlow

    static let accessibilityIdentifier = "readerAIProvidersView"

    var body: some View {
        VStack(spacing: 0) {
            contextBanner
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 4)

            AIProviderListView(
                viewModel: flow.viewModel,
                emptyState: { addAction in AnyView(emptyBody(onAdd: addAction)) },
                onEditorSaveSuccess: { id, wasAdd in
                    Task { await flow.handleEditorSaveSuccess(id: id, wasAdd: wasAdd) }
                },
                onRowActivated: { id in
                    Task { await flow.handleRowActivated(id: id) }
                }
            )
        }
        .background(Color(theme.sheetSurfaceColor).ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: - Context banner (shown for empty + populated)

    /// The "why-you're-here" banner — keeps the bilingual thread visible.
    private var contextBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(theme.accentColor).opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: "character.book.closed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
            }
            Text("Choose the provider **bilingual mode** will use to translate this book.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.inkColor))
                .lineSpacing(1.5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(theme.accentColor).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(theme.accentColor).opacity(0.20), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Bilingual-context empty state

    /// The design's empty body — gradient sparkle tile + serif headline +
    /// keychain-privacy line + "Add provider" pill. `onAdd` is
    /// `AIProviderListView`'s own add action, so the CTA reuses the canonical
    /// editor.
    private func emptyBody(onAdd: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(theme.accentColor), Color(theme.accentColor).opacity(0.67)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .shadow(color: Color(theme.accentColor).opacity(0.27), radius: 9, x: 0, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white)
            }
            .padding(.bottom, 14)

            Text("No providers yet")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 18)))
                .fontWeight(.semibold)
                .foregroundStyle(Color(theme.inkColor))

            Text("Add Claude, OpenAI, or any OpenAI-compatible endpoint. Your API key is stored in the device keychain — never synced.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 268)
                .padding(.top, 6)
                .padding(.bottom, 20)

            Button(action: onAdd) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("Add provider")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color(theme.accentColor)))
                .shadow(color: Color(theme.accentColor).opacity(0.33), radius: 7, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("readerAIProvidersAddButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 24)
    }
}
