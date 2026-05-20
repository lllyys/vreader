// Purpose: Feature #56 WI-15 — the provider-override half-sheet for
// per-chapter re-translation. Renders the picker (provider list + model
// chips + style segmented + keep-glossary toggle + CTA) when the VM is in
// `.picker` state, and routes to `ReTranslateProgress` when running.
//
// Surface origin: `dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx`
// — `ReTranslatePickerSheet` JSX. The 5-provider hard-coded list in the JSX
// is illustrative; vreader's real surface is the user's configured
// `ProviderProfile` set (loaded by the host from `ProviderProfileStore`).
//
// Key decisions:
// - **Sheet-driven, not push-driven**: opens via SwiftUI `.sheet(isPresented:)`
//   so the More-menu close → sheet open animation matches the other reader
//   sheets (Book Details, Setup, etc.).
// - **Host owns the profile list**: profiles come in as `[ProviderProfile]`
//   so the picker is not coupled to `ProviderProfileStore`'s actor — tests
//   pass a deterministic list, the host fetches the live snapshot.
// - **Style + glossary live in the VM's selection** — every section is a pure
//   read of `vm.selection`, every interaction routes through
//   `vm.updateSelection(_:)` so the VM stays the source of truth.
// - The body is split: `ReTranslatePickerSheetParts.swift` carries the
//   provider list / model chips / style segmented / glossary row helpers so
//   this file stays under ~300 LoC (rule 50).
//
// @coordinates-with: ChapterReTranslateViewModel.swift,
//   ReTranslateProgress.swift, ReTranslatePickerSheetParts.swift,
//   ReaderSheetChrome.swift,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import SwiftUI

/// Provider-override half-sheet for the per-chapter re-translate flow. The
/// host wires this into a `.sheet(isPresented:)` bound to
/// `vm.sheetState.isPresented`; when the VM transitions to `.running`, the
/// internal switch routes to `ReTranslateProgress`.
struct ReTranslatePickerSheet: View {

    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2

    /// VM driving the picker. The view binds to `vm.selection` and
    /// `vm.sheetState`.
    @Bindable var viewModel: ChapterReTranslateViewModel

    /// User's configured AI provider profiles — surfaced as the picker's
    /// provider list. Host fetches the snapshot before presenting the sheet.
    let providerProfiles: [ProviderProfile]

    /// Models the user can pick for the active provider profile. For now
    /// vreader's `ProviderProfile.model` is a single editable field; we
    /// surface it as a single-item list so the model chip still appears
    /// even though there's no multi-model picker yet. A provider that
    /// exposes multiple model options would supply them via this list.
    let availableModelsForActiveProfile: [String]

    /// Sheet accessibility identifier for XCUITest + verify-cron.
    static let accessibilityIdentifier = "reTranslatePickerSheet"

    var body: some View {
        ReaderSheetChrome(
            theme: theme,
            title: sheetTitle,
            onClose: { viewModel.dismiss() },
            content: { content }
        )
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.sheetState {
        case .running:
            ReTranslateProgress(
                theme: theme,
                chapterTitle: viewModel.unitTitle ?? "This chapter",
                progress: viewModel.progress,
                onCancel: { viewModel.cancel() }
            )
        case .complete:
            completeState
        default:
            picker
        }
    }

    private var sheetTitle: String {
        viewModel.sheetState == .running
            ? "Re-translating"
            : "Re-translate chapter"
    }

    // MARK: - Picker (idle / error)

    @ViewBuilder
    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                contextStrip
                if let error = viewModel.lastError {
                    errorBanner(error)
                }
                ReTranslateProviderList(
                    theme: theme,
                    profiles: providerProfiles,
                    selectedProfileID: viewModel.selection.providerProfileID,
                    onSelect: { profile in
                        viewModel.updateSelection { selection in
                            selection.providerProfileID = profile.id
                            // Reset model to the profile's primary so the
                            // chip row never shows a stale model from a
                            // different provider.
                            selection.model = profile.model
                        }
                    }
                )
                if availableModelsForActiveProfile.count > 1 {
                    ReTranslateModelChips(
                        theme: theme,
                        models: availableModelsForActiveProfile,
                        selectedModel: viewModel.selection.model,
                        onSelect: { model in
                            viewModel.updateSelection { $0.model = model }
                        }
                    )
                }
                ReTranslateStyleSegmented(
                    theme: theme,
                    selectedStyle: viewModel.selection.style,
                    onSelect: { style in
                        viewModel.updateSelection { $0.style = style }
                    }
                )
                ReTranslateGlossaryToggleRow(
                    theme: theme,
                    keepGlossary: viewModel.selection.keepGlossary,
                    onToggle: {
                        viewModel.updateSelection { $0.keepGlossary.toggle() }
                    }
                )
                cta
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private var contextStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .font(.system(size: 16))
                .foregroundStyle(Color(theme.subColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.unitTitle ?? "This chapter")
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
                    .italic()
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                Text(targetLanguageSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(theme.subSurfaceFill))
        )
    }

    private var targetLanguageSummary: String {
        "Translating to \(viewModel.targetLanguage)"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.red)
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityIdentifier("reTranslateErrorBanner")
    }

    private var cta: some View {
        HStack(spacing: 10) {
            Text(estimateLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await viewModel.submit() }
            } label: {
                Text("Re-translate")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(Color(theme.accentColor))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reTranslateSubmitButton")
        }
        .padding(.top, 4)
    }

    private var estimateLabel: String {
        // Token cost is provider-dependent and we don't have a calibrated
        // estimator in the codebase — surface a guidance line that mirrors
        // the design's intent without inventing numbers we can't back up.
        "Existing translation is kept until the new one is ready."
    }

    // MARK: - Complete state

    private var completeState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(theme.accentColor))
            Text("Re-translated")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 18)))
                .foregroundStyle(Color(theme.inkColor))
            Button {
                viewModel.dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(Color(theme.accentColor))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reTranslateDoneButton")
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

extension ReTranslateSheetState {
    /// Convenience: whether the SwiftUI `.sheet(isPresented:)` binding
    /// should be true. The picker and running and complete are all
    /// "presented" — only `.dismissed` collapses the sheet.
    var isPresented: Bool {
        switch self {
        case .dismissed: return false
        case .picker, .running, .complete: return true
        }
    }
}

private extension ReaderThemeV2 {
    /// A subtle sub-surface fill matching the design's `rgba(0,0,0,0.03)` /
    /// `rgba(255,255,255,0.04)`. The reader theme's other surfaces use
    /// `surfaceColor` for the page background; the context strip wants a
    /// slightly elevated card on top of that.
    var subSurfaceFill: UIColor {
        isDark
            ? UIColor(white: 1.0, alpha: 0.04)
            : UIColor(white: 0.0, alpha: 0.03)
    }
}
