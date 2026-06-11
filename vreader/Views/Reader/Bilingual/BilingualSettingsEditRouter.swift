// Purpose: Feature #99 WI-4 — the shared edit-mode routing used by all
// six bilingual hosts, so the fan-out stays wiring:
//  - `BilingualTranslationSettingsObserver`: the keyed
//    `.readerMoreTranslationSettings` observer every host attaches.
//  - `BilingualSettingsEditRouter`: prefill at present + the
//    dirty-BEFORE-apply confirm routing (applies through the EXISTING
//    `setTargetLanguage`/`setGranularity`; never touches
//    `needsSetupSheet`/`setEnabled`) + the re-translate banner post.
//  - `BilingualCachedLanguagesFetcher`: the generation-stamped
//    cached-languages fetch (the feature-#101 fetcher precedent) — a
//    superseded or dismissed presentation's completion is dropped.
//
// @coordinates-with: BilingualSettingsEditModel.swift,
//   BilingualSetupSheet+EditMode.swift, BilingualReadingViewModel.swift,
//   ChapterTranslationStore.swift, ReaderNotifications.swift,
//   BilingualRetranslateBanner.swift

import SwiftUI

/// The keyed re-entry observer (feature #99). Every bilingual host
/// attaches one; the payload's `fingerprintKey` must match this book.
struct BilingualTranslationSettingsObserver: ViewModifier {
    let bookFingerprintKey: String
    /// Fired with the book title carried in the notification (the
    /// container posts it from `book.title`; "" when absent).
    let onRequest: (_ bookTitle: String) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .readerMoreTranslationSettings)
        ) { notification in
            guard notification.userInfo?["fingerprintKey"] as? String
                == bookFingerprintKey else { return }
            onRequest((notification.userInfo?["bookTitle"] as? String) ?? "")
        }
    }
}

extension View {
    /// Attaches the feature-#99 translation-settings re-entry observer.
    func bilingualTranslationSettingsObserver(
        bookFingerprintKey: String,
        onRequest: @escaping (_ bookTitle: String) -> Void
    ) -> some View {
        modifier(BilingualTranslationSettingsObserver(
            bookFingerprintKey: bookFingerprintKey, onRequest: onRequest))
    }
}

/// Shared edit-mode routing (feature #99 WI-4).
@MainActor
enum BilingualSettingsEditRouter {

    /// The draft the edit sheet opens with — the book's CURRENT settings.
    static func prefillState(vm: BilingualReadingViewModel) -> BilingualSetupSheetState {
        BilingualSetupSheetState(
            languageKey: vm.targetLanguage, granularity: vm.granularity)
    }

    /// Edit-confirm routing: computes the dirty kind BEFORE applying
    /// (the setters mutate the baseline), applies through the existing
    /// equality-guarded setters, and posts the re-translate banner
    /// notification for a genuinely new language. Returns the dirty
    /// kind so the host can warm the prefetch when something changed.
    @discardableResult
    static func confirmEdit(
        vm: BilingualReadingViewModel,
        draft: BilingualSetupSheetState,
        cachedLanguages: Set<String>
    ) -> BilingualSettingsEditModel.DirtyKind {
        let previousLanguage = BilingualLanguage.findOrDefault(key: vm.targetLanguage).key
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: vm.targetLanguage,
            currentGranularity: vm.granularity,
            draft: draft,
            cachedLanguages: cachedLanguages
        )
        vm.setTargetLanguage(draft.languageKey)
        vm.setGranularity(draft.granularity)
        if BilingualSettingsEditModel.shouldShowRetranslateBanner(dirty: dirty) {
            NotificationCenter.default.post(
                name: .readerBilingualRetranslateStarted, object: nil,
                userInfo: [
                    "fingerprintKey": vm.bookFingerprintKey,
                    "language": BilingualLanguage.findOrDefault(key: draft.languageKey).key,
                    "previousLanguage": previousLanguage,
                ])
        }
        return dirty
    }
}

/// Generation-stamped cached-languages fetch: each `fetch` supersedes
/// any in-flight one; `invalidate()` drops every in-flight completion
/// (sheet dismissed / book changed). `@MainActor` so the
/// compare-and-apply is race-free.
@MainActor
final class BilingualCachedLanguagesFetcher {
    private var generation = 0

    /// Drops any in-flight fetch's completion.
    func invalidate() { generation += 1 }

    /// Starts a fetch; `apply` runs only if no newer fetch/invalidate
    /// superseded this one by completion time.
    func fetch(
        bookFingerprintKey: String,
        store: ChapterTranslationStore = .shared,
        into apply: @escaping @MainActor (Set<String>) -> Void
    ) {
        generation += 1
        let stamped = generation
        Task { [weak self] in
            let languages = await store.cachedLanguages(
                forBookWithKey: bookFingerprintKey)
            guard let self, stamped == self.generation else { return }
            apply(languages)
        }
    }
}
