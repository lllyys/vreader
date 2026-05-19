// Purpose: Feature #55 WI-6/WI-7 — `notePreviewPresenterIfAvailable`, the
// container-side attach helper for the tap-on-annotated-text note preview.
//
// The reader containers (`TXTReaderContainerView`, `MDReaderContainerView`,
// `PDFReaderContainerView`, the EPUB / Foliate containers) carry an OPTIONAL
// `ModelContainer` — `nil` in SwiftUI previews and some test harnesses. This
// helper attaches `NotePreviewModifier` only when a real `ModelContainer` is
// present, building the `PersistenceActor` (which conforms to `HighlightLookup`,
// feature #55 WI-2) as the lookup. When the container is `nil` the view is
// returned unchanged — the preview is simply inert in a preview/test context.
//
// Keeps each container's `body` to a single readable call rather than an
// inline `if let` + `PersistenceActor(...)` construction repeated five times.
//
// @coordinates-with: NotePreviewModifier.swift, NotePreviewViewModel.swift,
//   PersistenceActor+Highlights.swift (HighlightLookup conformance)

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

extension View {
    /// Attaches the feature #55 note-preview presenter when `modelContainer`
    /// is non-nil. The `PersistenceActor` built over the container is the
    /// `HighlightLookup` the note-preview view model uses.
    ///
    /// `hostViewProvider` defaults to `{ nil }` — the v1 native + Foliate
    /// containers present the preview via the bottom-sheet form
    /// (`NotePreviewPresenter.resolvedForm` degrades a callout with no host).
    @ViewBuilder
    func notePreviewPresenterIfAvailable(
        modelContainer: ModelContainer?,
        bookFingerprintKey: String,
        theme: ReaderThemeV2,
        hostViewProvider: @escaping () -> UIView? = { nil }
    ) -> some View {
        if let modelContainer {
            self.notePreviewPresenter(
                highlightLookup: PersistenceActor(modelContainer: modelContainer),
                bookFingerprintKey: bookFingerprintKey,
                theme: theme,
                hostViewProvider: hostViewProvider
            )
        } else {
            self
        }
    }
}
#endif
