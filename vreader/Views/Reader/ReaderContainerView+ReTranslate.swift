// Purpose: Feature #56 WI-15 host wiring — constructs the
// `ChapterReTranslateViewModel` on demand, derives the current
// `TranslationUnitID` + its source text from the published
// `ChapterTextProviding` adapter, refreshes the picker's provider list
// from `ProviderProfileStore`, and exposes a `Binding<Bool>` for the
// `.sheet(isPresented:)` modifier.
//
// Why this lives in its own file: the `body` block is already at the SwiftUI
// type-inference budget (Codex Gate-4 H1 in WI-13 added an explicit
// `ViewModifier` for the AI-translate route for the same reason); adding the
// re-translate construction logic inline would push it over. The extension
// holds the helpers, the body holds a single observer + sheet.
//
// @coordinates-with: ReaderContainerView.swift,
//   ChapterReTranslateViewModel.swift, ReTranslatePickerSheet.swift,
//   ChapterTextProviding.swift, ProviderProfileStore.swift, AIService.swift,
//   ChapterTranslationService.swift, ChapterTranslationStore.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import SwiftUI

/// Feature #56 WI-15: dedicated `ViewModifier` for the re-translate flow.
/// Factored out of `ReaderContainerView.body` so the body stays under
/// SwiftUI's type-inference budget (WI-13's
/// `ReaderOpenAITranslateObserver` precedent).
struct ReaderReTranslateObserver<SheetBody: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let sheetContent: () -> SheetBody
    let onTrigger: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: .readerMoreReTranslateChapter)) { _ in
                onTrigger()
            }
            .sheet(isPresented: isPresented, content: sheetContent)
    }
}

extension ReaderContainerView {

    // MARK: - Sheet binding

    /// `Binding<Bool>` for `.sheet(isPresented:)`. True whenever the VM has
    /// any non-dismissed sheet state (`picker`, `running`, `complete`); false
    /// when the VM is `.dismissed`. Writing `false` dismisses the sheet via
    /// the VM so the side effects (task cancellation, progress reset) all
    /// run.
    var reTranslatePickerBinding: Binding<Bool> {
        Binding(
            get: { reTranslateVM?.sheetState.isPresented ?? false },
            set: { newValue in
                if !newValue { reTranslateVM?.dismiss() }
            }
        )
    }

    /// The picker sheet's content view. Extracted from `body` so the
    /// SwiftUI type-checker doesn't time out on the surrounding stack.
    @ViewBuilder
    var reTranslateSheetContent: some View {
        if let vm = reTranslateVM {
            ReTranslatePickerSheet(
                theme: settingsStore.theme,
                viewModel: vm,
                providerProfiles: reTranslateProviderProfiles,
                availableModelsForActiveProfile: availableModelsForActiveProfile(
                    in: reTranslateProviderProfiles,
                    selectedID: vm.selection.providerProfileID)
            )
        } else {
            EmptyView()
        }
    }

    // MARK: - Notification handler

    /// Responds to `.readerMoreReTranslateChapter`. Resolves the current
    /// unit from the published text provider + current locator, constructs
    /// the VM if needed, refreshes the profile list, and presents the
    /// picker. A failure to resolve a unit (no provider published yet, or
    /// the position isn't in any unit) silently no-ops — the user can tap
    /// the row again once the reader is fully loaded.
    func handleReTranslateChapterRequested() {
        guard let provider = translateBookTextProvider else { return }
        guard let locator = currentLocator else { return }

        Task { @MainActor in
            guard let unit = await provider.unit(containing: locator) else { return }

            // Refresh the profile list every time the picker opens — picks
            // up newly-added providers + reflects any active-id change.
            let snapshot = await ProviderProfileStore.shared.loadSnapshot()
            reTranslateProviderProfiles = snapshot.profiles
            guard !snapshot.profiles.isEmpty else {
                // No providers configured: show the picker anyway so the
                // user sees the "configure a provider" empty state. We
                // still need a VM so the sheet has something to render —
                // build a no-op VM keyed to a sentinel profile id.
                let vm = ensureReTranslateVM(
                    initialProfileID: UUID(),
                    initialModel: "")
                vm.presentPicker(
                    unit: unit, unitTitle: nil, targetLanguage: targetLanguageForReTranslate())
                return
            }

            // Choose the active profile if one is set; otherwise fall back
            // to the first listed profile.
            let activeOrFirstProfile = snapshot.profiles.first(where: { $0.id == snapshot.activeID })
                ?? snapshot.profiles[0]

            let vm = ensureReTranslateVM(
                initialProfileID: activeOrFirstProfile.id,
                initialModel: activeOrFirstProfile.model)
            // Codex Gate-4 round-1 Low (thread `019e4399-b8cd`): the VM is
            // reused across opens, so its previous picker selection may
            // reference a profile that's since been deleted. Reset to the
            // active-or-first profile so the picker always has a valid
            // selection — the submit path can't fail purely because the
            // selected profile vanished between opens.
            let validProfileIDs = Set(snapshot.profiles.map(\.id))
            if !validProfileIDs.contains(vm.selection.providerProfileID) {
                vm.updateSelection { selection in
                    selection.providerProfileID = activeOrFirstProfile.id
                    selection.model = activeOrFirstProfile.model
                }
            }
            vm.presentPicker(
                unit: unit,
                unitTitle: reTranslateUnitTitle(for: unit),
                targetLanguage: targetLanguageForReTranslate())
        }
    }

    // MARK: - VM construction

    /// Builds the VM lazily on first use, reusing it on subsequent picker
    /// opens so the user's last selection persists. The translation service
    /// uses the same shared `ChapterTranslationStore` as the global
    /// translate-book coordinator, so cache reads/writes are consistent
    /// across both flows.
    private func ensureReTranslateVM(
        initialProfileID: UUID, initialModel: String
    ) -> ChapterReTranslateViewModel {
        if let existing = reTranslateVM { return existing }

        let aiService = AIService(
            featureFlags: FeatureFlags.shared,
            consentManager: AIConsentManager(),
            keychainService: KeychainService(),
            profileStore: ProviderProfileStore.shared)
        let translationService = ChapterTranslationService(
            sender: aiService,
            store: ChapterTranslationStore.shared,
            promptVersion: "bilingual-v1")

        let vm = ChapterReTranslateViewModel(
            bookFingerprintKey: book.fingerprintKey,
            promptVersion: "bilingual-v1",
            initialProviderProfileID: initialProfileID,
            initialModel: initialModel,
            resolver: aiService,
            runner: translationService,
            store: ChapterTranslationStore.shared,
            sourceTextProvider: { [provider = translateBookTextProvider] unit in
                // `ChapterTextProviding` is a `Sendable` value-or-actor
                // protocol (not class-bound), so it's captured strongly here.
                // The provider's actual lifetime is the per-format container
                // that owns it; a re-translate VM outliving that container
                // would still hold a usable reference because the provider's
                // backing state (chapter index, EPUB spine cache) is fully
                // value/actor-isolated. The async suspension doesn't block
                // the main actor.
                //
                // **Throwing on purpose (Codex Gate-4 round-1 Critical, thread
                // `019e4399-b8cd`)**: an empty string means "legitimately
                // empty unit" (the VM completes the run as no-op). A throw
                // surfaces a real source-text failure or cancellation up
                // to the VM, which rolls back to the picker WITHOUT posting
                // the misleading "Re-translated" success state.
                //
                // No-provider edge case: the VM presents the picker only
                // after `handleReTranslateChapterRequested` confirmed a
                // provider was published; an unset capture here is the
                // host-swap edge case (provider replaced mid-flight) — we
                // surface it as a throw so the VM rolls back.
                guard let provider else {
                    struct NoProviderError: Error {}
                    throw NoProviderError()
                }
                return try await provider.sourceText(for: unit)
            })

        // Apply translations back to the chrome notification so the active
        // per-format container can re-render with the fresh segments.
        vm.onTranslationApplied = { [bookKey = book.fingerprintKey] unit, segments in
            NotificationCenter.default.post(
                name: .readerBilingualReTranslateApplied,
                object: nil,
                userInfo: [
                    "fingerprintKey": bookKey,
                    "unit": unit,
                    "segments": segments
                ])
        }
        reTranslateVM = vm
        return vm
    }

    /// Returns the bilingual target language from the active book's
    /// per-book settings, falling back to the default. Mirrors the
    /// `readerBilingualDidChange` payload's `language` so the picker uses
    /// whatever the user already chose for bilingual mode.
    private func targetLanguageForReTranslate() -> String {
        bilingualLanguage ?? BilingualReadingViewModel.defaultTargetLanguage
    }

    /// Best-effort human-readable title for the unit's context strip.
    /// Looks up the unit's storage key in the host's `tocEntries` by
    /// matching the entry's locator's `href` (EPUB) or chapter ordinal
    /// (TXT/MD/PDF). Returns nil when no match — the picker falls back to
    /// "This chapter".
    private func reTranslateUnitTitle(for unit: TranslationUnitID) -> String? {
        // EPUB / Foliate units key by href; the TOC entry's locator carries
        // an href that should match.
        for entry in tocEntries {
            if entry.locator.href == unit.value { return entry.title }
        }
        return nil
    }

    // MARK: - Picker helpers

    /// Returns the models available for the picker's currently selected
    /// provider. vreader's `ProviderProfile.model` is a single editable
    /// string today — the picker only shows the model chip row when there
    /// are multiple options, so for now this returns `[profile.model]`,
    /// and the chip row is hidden. Forward-compat for providers that
    /// surface a model registry.
    func availableModelsForActiveProfile(
        in profiles: [ProviderProfile], selectedID: UUID
    ) -> [String] {
        guard let profile = profiles.first(where: { $0.id == selectedID }) else { return [] }
        return [profile.model]
    }
}
