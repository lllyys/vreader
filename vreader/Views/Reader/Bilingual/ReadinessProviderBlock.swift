// Purpose: Feature #82 — the inline provider section (step 3) of the in-reader
// AI readiness sheet. Unlike `AIProviderListView` (a `List` with its own
// scroll + swipe actions), this renders provider rows INLINE in the readiness
// sheet's single ScrollView (per the design's `ReadinessProviderBlock`): a
// row per saved provider (active = checkmark), then an "Add provider" row that
// presents the canonical `AIProviderEditSheet`. `locked` (AI off) dims it.
//
// It reuses #81's `AIEditorContext` + `AIProviderEditSheet`, and the same
// post-dismiss save re-emission pattern (buffer `pendingSaved`, fire
// `onEditorSaveSuccess` from `.sheet(onDismiss:)`) so the readiness flow
// activates + pops only after the editor fully dismisses.
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-readiness.jsx`
// (`ReadinessProviderBlock`).
//
// @coordinates-with: ReaderAIReadinessView.swift, AIProviderListView.swift
//   (AIEditorContext), AIProviderEditSheet.swift, AISettingsViewModel.swift

import SwiftUI

/// Inline provider rows + an "Add provider" row, for the readiness sheet's
/// step 3. Callbacks bubble to the `ReaderAIProvidersFlow` (ready-gated pop).
struct ReadinessProviderBlock: View {

    let theme: ReaderThemeV2
    @Bindable var viewModel: AISettingsViewModel
    /// AI off → the provider step is not yet actionable (dimmed, non-interactive).
    let locked: Bool
    /// Fired after a row tap's `setActive` completes.
    let onRowActivated: (UUID) -> Void
    /// Re-emitted from `.sheet(onDismiss:)` after a successful add/edit.
    let onEditorSaveSuccess: (UUID, _ wasAdd: Bool) -> Void

    @State private var editorContext: AIEditorContext?
    @State private var pendingSavedID: UUID?
    @State private var pendingSavedWasAdd = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.profiles) { profile in
                providerRow(profile)
                Divider().overlay(Color(theme.ruleColor))
            }
            addRow
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(theme.sheetCardSurfaceColor))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(theme.ruleColor), lineWidth: 0.5))
        )
        .opacity(locked ? 0.45 : 1)
        .allowsHitTesting(!locked)
        .accessibilityIdentifier("readinessProviderBlock")
        .sheet(item: $editorContext, onDismiss: {
            if let id = pendingSavedID {
                pendingSavedID = nil
                onEditorSaveSuccess(id, pendingSavedWasAdd)
            }
        }) { context in
            AIProviderEditSheet(
                viewModel: viewModel,
                existing: context.profile,
                onSaveSuccess: { id, wasAdd in
                    pendingSavedID = id
                    pendingSavedWasAdd = wasAdd
                }
            )
        }
    }

    private func providerRow(_ profile: ProviderProfile) -> some View {
        Button {
            Task {
                await viewModel.setActive(profile.id)
                guard viewModel.activeID == profile.id else { return }
                onRowActivated(profile.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.activeID == profile.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.activeID == profile.id ? Color(theme.accentColor) : Color(theme.subColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Color(theme.inkColor))
                    Text(profile.model).font(.system(size: 11.5)).foregroundStyle(Color(theme.subColor)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if viewModel.activeID == profile.id {
                    Text("In use").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(theme.accentColor))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("readinessProviderRow_\(profile.id.uuidString)")
    }

    private var addRow: some View {
        Button { editorContext = .add() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(theme.accentColor))
                }
                Text("Add provider").font(.system(size: 15, weight: .medium)).foregroundStyle(Color(theme.accentColor))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("readinessAddProviderRow")
    }
}
