// Purpose: Feature #56 WI-14 — Book Details sheet host wiring for the
// "Translate entire book…" flow. Owns the confirm / status / cancel
// SwiftUI overlays; the action-row routing lives in `+Actions.swift`.
// Split out so `BookDetailsSheet.swift` stays under the rule-50 ~300-line
// guideline.
//
// The actual translate operation is owned by
// `BookTranslationCoordinator.shared` (a long-lived actor), so dismissing
// the Book Details sheet does NOT cancel a running job — the badge/banner
// continue to reflect the running job until completion.
//
// **Provider snapshot resolved at confirm time** (Codex Gate-4 medium
// finding). The reader host caches the text provider when the per-format
// container publishes it, but the active AI profile + model are read
// freshly inside `onConfirm` so the started job's config reflects the
// user's current Settings choices — not whatever was active when Book
// Details first opened.
//
// @coordinates-with: BookDetailsSheet.swift, BookDetailsSheet+Actions.swift,
//   BookTranslationViewModel.swift, TranslateBookActionRow.swift,
//   TranslateBookConfirmAlert.swift, TranslateStatusSheet.swift,
//   TranslateCancelAlert.swift, BookTranslationCoordinator.swift

#if canImport(UIKit)
import SwiftUI

/// Attaches the WI-14 translate-book overlays (confirm alert, status
/// sheet, cancel alert) to `BookDetailsSheet`'s body. Reads the
/// host-injected `BookTranslationViewModel`; if no VM is wired the
/// modifier passes through unchanged.
struct TranslateBookOverlayModifier: ViewModifier {
    let bookTitle: String
    let theme: ReaderThemeV2
    let sheet: BookDetailsSheet

    func body(content: Content) -> some View {
        if let vm = sheet.translateBookViewModel {
            content
                .modifier(TranslateBookBoundOverlay(
                    bookTitle: bookTitle, theme: theme, sheet: sheet, viewModel: vm))
        } else {
            content
        }
    }
}

/// Inner modifier that owns the `@Bindable` reference. Splitting it from
/// the wrapper above keeps the `viewModel != nil` branch clean — SwiftUI
/// does not allow `@Bindable` on an `Optional`.
private struct TranslateBookBoundOverlay: ViewModifier {
    let bookTitle: String
    let theme: ReaderThemeV2
    let sheet: BookDetailsSheet
    @Bindable var viewModel: BookTranslationViewModel

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Idempotent — the VM may already be observed by the
                // reader host (`ReaderContainerView` constructs + starts
                // observing the VM when the text provider is published).
                // Re-calling `startObserving` replaces the existing
                // task with the same source, so there is no duplication.
                Task { @MainActor in await viewModel.startObserving() }
            }
            // No `stopObserving` on disappear: the reader-side banner
            // continues to need progress snapshots after Book Details
            // dismisses. The VM's observation is host-scoped (the host
            // tears it down on book close via SwiftUI state lifetime),
            // not sheet-scoped.
            .overlay {
                if viewModel.isShowingConfirmAlert,
                   let estimate = viewModel.estimate {
                    TranslateBookConfirmAlert(
                        bookTitle: bookTitle,
                        unitCount: estimate.unitCount,
                        approximateInputTokens: estimate.approximateInputTokens,
                        providerLabel: viewModel.providerLabel,
                        targetLanguageLabel: sheet.translateBookTargetLanguage,
                        theme: theme,
                        onChangeProvider: {
                            // Accepted follow-up (Codex Gate-4 medium
                            // finding): the design's "Change provider"
                            // CTA routes to an inline provider-picker
                            // sheet. The picker is owned by feature #50
                            // (`AIProviderPickerViewModel`) and lives
                            // behind AI Settings — wiring it into this
                            // alert without churning the picker shape
                            // (or duplicating it) is a separate slice.
                            // For WI-14 we dismiss the alert so the
                            // user can change the active provider in
                            // Settings then re-tap "Translate entire
                            // book…" — the provider snapshot is
                            // re-resolved fresh at confirm time so the
                            // new choice IS reflected in the started
                            // job. Tracked for follow-up; not blocking.
                            viewModel.dismissConfirm()
                        },
                        onCancel: viewModel.dismissConfirm,
                        onConfirm: {
                            guard let provider = sheet.translateBookTextProvider else {
                                viewModel.dismissConfirm()
                                return
                            }
                            // Resolve the active provider snapshot at
                            // confirm time so a profile / model swap
                            // between Book Details open and "Translate"
                            // tap is reflected in the started job (Codex
                            // Gate-4 medium finding). Reads through the
                            // same AIService construction as the rest of
                            // bilingual mode (no shared singleton).
                            Task { @MainActor in
                                let aiService = AIService(
                                    featureFlags: FeatureFlags.shared,
                                    consentManager: AIConsentManager(),
                                    keychainService: KeychainService(),
                                    profileStore: ProviderProfileStore.shared)
                                guard
                                    let resolved = try? await aiService.resolveActiveProviderConfig(),
                                    let snapshot = await ProviderProfileStore.shared.activeProfileSnapshot()
                                else {
                                    viewModel.dismissConfirm()
                                    return
                                }
                                await viewModel.confirmTranslate(
                                    textProvider: provider,
                                    targetLanguage: sheet.translateBookTargetLanguage,
                                    providerProfileID: snapshot.id,
                                    config: resolved,
                                    style: .natural)
                            }
                        })
                }
                if viewModel.isShowingCancelAlert {
                    TranslateCancelAlert(
                        progress: viewModel.progress,
                        theme: theme,
                        onKeep: viewModel.dismissCancelAlert,
                        onConfirm: {
                            Task { @MainActor in await viewModel.confirmCancel() }
                        })
                }
            }
            .sheet(isPresented: $viewModel.isShowingStatusSheet) {
                TranslateStatusSheet(
                    progress: viewModel.progress,
                    targetLanguageLabel: sheet.translateBookTargetLanguage,
                    providerLabel: viewModel.providerLabel,
                    theme: theme,
                    onCancelAll: viewModel.requestCancel)
            }
    }
}
#endif
