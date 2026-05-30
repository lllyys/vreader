// Purpose: Feature #64 WI-4 — `HighlightPopoverModifier` (the SwiftUI
// `ViewModifier` driving the unified highlight-action popover) and its
// container-side attach helpers.
//
// Lives alongside `HighlightPopoverModifier.swift` (the protocol + parse
// helper + share types) — split so each file stays under the ~300-line
// guideline. `HighlightPopoverModifier` here is the actual `ViewModifier`.
//
// Flow:
//   .readerHighlightTapped  →  HighlightPopoverViewModel.handleTap  (async
//        lookup, out-of-order-guarded)  →  publishes HighlightPopoverContent
//   →  HighlightPopoverActionRouter.present  (takes over interaction state)
//   →  routed to the anchored `HighlightPopoverPresenting` card (.card) or a
//      SwiftUI `.sheet` (.sheet) per `HighlightPopoverPresenter.resolvedForm`.
//
// Two state holders, disjoint jobs: the view model owns the *lookup*; the
// router owns the *interaction* (mode / draft / outcome routing). The modifier
// bridges them and drives the anchored presenter's `presentCard` /
// `updateCard` / `dismissCard`.
//
// Supersedes feature #55's `NotePreviewModifier` (deleted in WI-10).
//
// @coordinates-with: HighlightPopoverModifier.swift, HighlightPopoverViewModel.swift,
//   HighlightPopoverActionRouter.swift, HighlightActionCardView.swift,
//   HighlightPopoverPresenter.swift, UIKitHighlightPopoverPresenter.swift (WI-5)

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

// MARK: - The ViewModifier

struct HighlightPopoverModifier: ViewModifier {

    /// Owns the async highlight lookup + the out-of-order tap guard.
    @State private var viewModel: HighlightPopoverViewModel
    /// Owns the popover's interaction state + action dispatch.
    @State private var router: HighlightPopoverActionRouter
    /// The anchored-card presenter (the `.card` form). Injected for testing.
    @State private var cardPresenter: any HighlightPopoverPresenting
    /// Drives the SwiftUI `.sheet` form (the `.sheet` form). `nil` ⇒ no sheet.
    @State private var sheetContent: HighlightPopoverContent?
    /// Drives the share `.sheet(item:)`. Modifier-owned (NOT router-owned) and
    /// set only AFTER the popover surface has finished dismissing, so the
    /// share sheet never collides with the popover's own dismissal (R2-F7).
    @State private var shareItem: HighlightShareItem?
    /// An action to run from the popover-sheet's real `onDismiss` — used to
    /// present the share sheet only once the popover sheet has fully
    /// dismissed. `nil` ⇒ a plain dismissal.
    @State private var pendingPostSheetDismiss: (@MainActor () -> Void)?
    /// Feature #1121 WI-2: the in-flight Edit-handoff auto-open task (a settle
    /// delay before opening the editor). Cancelled + replaced by a newer edit
    /// request, and cancelled by a real highlight tap, so a stale edit can never
    /// win over what the user is doing now.
    @State private var pendingEditTask: Task<Void, Never>?
    /// The token of the latest accepted edit request — a delayed task only fires
    /// if it still matches (single-flight supersession, audit High).
    @State private var latestEditToken: UUID?

    let theme: ReaderThemeV2
    /// Optional chapter/location string for the meta row.
    let chapter: String?
    /// Resolves the reader's content `UIView` — the anchored card's
    /// `sourceView`. `nil` (or a `{ nil }` provider) ⇒ the sheet form.
    let hostViewProvider: () -> UIView?

    init(
        viewModel: HighlightPopoverViewModel,
        router: HighlightPopoverActionRouter,
        cardPresenter: any HighlightPopoverPresenting,
        theme: ReaderThemeV2,
        chapter: String?,
        hostViewProvider: @escaping () -> UIView?
    ) {
        _viewModel = State(initialValue: viewModel)
        _router = State(initialValue: router)
        _cardPresenter = State(initialValue: cardPresenter)
        self.theme = theme
        self.chapter = chapter
        self.hostViewProvider = hostViewProvider
    }

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .readerHighlightTapped)
            ) { note in
                guard let event = HighlightPopoverRequest.event(from: note) else { return }
                // A real tap supersedes any pending Edit-handoff auto-open (audit High).
                pendingEditTask?.cancel(); pendingEditTask = nil; latestEditToken = nil
                Task { await viewModel.handleTap(event, chapter: chapter) }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .readerHighlightEditRequested)
            ) { note in
                // Feature #1121 WI-2: the HighlightsSheet "Edit" handoff. Open the
                // unified card in editing mode for the requested highlight. Book
                // guard: ignore a request for a different book (a same-book
                // multi-window guard; cross-book is already a lookup no-op).
                // `sourceRect: .zero` → the card's sheet form (no per-format anchor
                // needed) → format-agnostic. A short settle lets the navigation
                // land; the task is cancellable + token-guarded so a stale edit
                // never wins over a newer edit or a real tap (audit High).
                guard let request = HighlightPopoverRequest.editRequest(from: note),
                      request.bookFingerprintKey == viewModel.bookFingerprintKey
                else { return }
                pendingEditTask?.cancel()
                latestEditToken = request.token
                pendingEditTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, latestEditToken == request.token else { return }
                    await viewModel.handleTap(
                        ReaderHighlightTapEvent(
                            highlightID: request.highlightID,
                            sourceRect: .zero,
                            openInEditMode: true
                        ),
                        chapter: chapter
                    )
                }
            }
            .onDisappear { pendingEditTask?.cancel(); pendingEditTask = nil }
            .onChange(of: viewModel.presented) { _, newValue in
                if let newValue {
                    // Feature #1121: open in `.editing` for an Edit-handoff
                    // auto-open; `.reading` for a normal tap.
                    router.present(newValue, initialMode: viewModel.presentedInitialMode)
                } else {
                    router.dismiss()
                }
            }
            .onChange(of: router.content) { _, _ in routePresentation() }
            .onChange(of: router.mode) { _, _ in syncLiveCard() }
            .onChange(of: router.noteDraft) { _, _ in syncLiveCard() }
            .onChange(of: router.pressedColor) { _, _ in syncLiveCard() }
            .sheet(item: $sheetContent, onDismiss: { sheetDidDismiss() }) { content in
                HighlightActionCardView(
                    content: content,
                    theme: theme,
                    mode: router.mode,
                    form: .sheet,
                    noteDraft: router.noteDraft,
                    pressedColor: router.pressedColor,
                    onAction: { action in Task { await dispatch(action) } },
                    onDraftChange: { router.updateDraft($0) },
                    onDismiss: { dismissEverything() }
                )
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $shareItem) { item in
                HighlightActivityView(activityItems: [item.text])
            }
    }

    // MARK: - Presentation routing

    /// Routes the router's current `content` to the anchored card or the
    /// sheet. `nil` tears down whichever surface is up — and, when a share is
    /// pending, presents the share sheet only from the surface's REAL
    /// dismissal completion so two modals never stack (R2-F7).
    private func routePresentation() {
        guard let content = router.content else {
            tearDownSurfaces {
                if let text = router.pendingShareText {
                    router.clearPendingShare()
                    shareItem = HighlightShareItem(text: text)
                }
            }
            return
        }
        let host = hostViewProvider()
        let lineCount = content.note?
            .components(separatedBy: .newlines).count ?? 0
        let form = HighlightPopoverPresenter.resolvedForm(
            for: content,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            noteLineCount: lineCount,
            hasHostView: host != nil
        )
        switch form {
        case .sheet:
            cardPresenter.dismissCard()
            sheetContent = content
        case .card:
            guard let host else {
                // resolvedForm returns .card only when hasHostView — defensive.
                sheetContent = content
                return
            }
            sheetContent = nil
            cardPresenter.presentCard(
                content,
                theme: theme,
                mode: router.mode,
                noteDraft: router.noteDraft,
                pressedColor: router.pressedColor,
                in: host,
                onAction: { action in Task { await dispatch(action) } },
                onDraftChange: { router.updateDraft($0) },
                onDismiss: { dismissEverything() }
            )
        }
    }

    /// Pushes a `mode` / `noteDraft` / `pressedColor` change into the live
    /// anchored card via `updateCard` — an in-place `rootView` reassignment,
    /// NOT a dismiss + re-present, so the keyboard is preserved (R2-F6). The
    /// `.sheet` form re-renders itself from the `@State`, so no explicit hook
    /// is needed there.
    private func syncLiveCard() {
        guard let content = router.content, sheetContent == nil else { return }
        cardPresenter.updateCard(
            content: content, mode: router.mode, noteDraft: router.noteDraft,
            pressedColor: router.pressedColor
        )
    }

    // MARK: - Surface teardown (completion-aware)

    /// Tears down whichever popover surface is currently up and runs
    /// `completion` from the surface's REAL dismissal completion — so a
    /// follow-up surface (the share sheet) is presented only after the popover
    /// has fully dismissed, never stacking two modals.
    ///
    /// - Sheet form: stash `completion` in `pendingPostSheetDismiss` and clear
    ///   `sheetContent`. SwiftUI fires the `.sheet`'s `onDismiss` →
    ///   `sheetDidDismiss`, which runs the stashed action.
    /// - Card form (or nothing presented): `dismissCard(completion:)` runs the
    ///   completion from the popover's real dismiss completion — or
    ///   synchronously when nothing is presented.
    private func tearDownSurfaces(then completion: @escaping @MainActor () -> Void) {
        if sheetContent != nil {
            pendingPostSheetDismiss = completion
            sheetContent = nil
        } else {
            cardPresenter.dismissCard(completion: completion)
        }
    }

    /// Fired by the popover `.sheet`'s `onDismiss` — the real completion hook.
    /// Runs any stashed post-dismiss action (share follow-up); otherwise it is
    /// a plain dismissal.
    private func sheetDidDismiss() {
        let action = pendingPostSheetDismiss
        pendingPostSheetDismiss = nil
        action?()
    }

    // MARK: - Action dispatch

    private func dispatch(_ action: HighlightPopoverAction) async {
        await router.route(action)
        // A `.success` recolor / save rebuilt `router.content`; the live card
        // refresh rides `onChange(of: router.content)` → `routePresentation`.
        // A `.share` cleared `router.content` + set `pendingShareText`;
        // `routePresentation`'s nil-branch tears the surface down and presents
        // the share sheet from the real dismiss completion.
    }

    /// Tears down every popover surface and the view-model + router state.
    /// Used by plain-dismiss paths (× button, scrim tap, sheet drag-down).
    private func dismissEverything() {
        sheetContent = nil
        pendingPostSheetDismiss = nil
        cardPresenter.dismissCard()
        router.dismiss()
        viewModel.dismiss()
    }
}

// MARK: - Attach helpers

extension View {
    /// Feature #64 WI-4 — attach the unified highlight-action popover to a
    /// reader container. The modifier observes `.readerHighlightTapped`,
    /// resolves the tapped highlight, and presents the anchored card or the
    /// bottom sheet.
    func unifiedHighlightPopoverPresenter(
        viewModel: HighlightPopoverViewModel,
        router: HighlightPopoverActionRouter,
        cardPresenter: any HighlightPopoverPresenting = UIKitHighlightPopoverPresenter(),
        theme: ReaderThemeV2,
        chapter: String? = nil,
        hostViewProvider: @escaping () -> UIView?
    ) -> some View {
        modifier(
            HighlightPopoverModifier(
                viewModel: viewModel,
                router: router,
                cardPresenter: cardPresenter,
                theme: theme,
                chapter: chapter,
                hostViewProvider: hostViewProvider
            )
        )
    }

    /// Feature #64 WI-4 — container-friendly attach point. Builds the
    /// `HighlightPopoverViewModel` (over the `PersistenceActor` `HighlightLookup`)
    /// and the `HighlightPopoverActionRouter` (over the supplied
    /// `HighlightMutating`) when `modelContainer` is non-nil; otherwise the
    /// view is returned unchanged (inert in a SwiftUI preview / test).
    ///
    /// `mutating` is the format's highlight-mutation boundary — a
    /// `HighlightCoordinator` for the `HighlightRenderer`-backed formats, the
    /// Foliate mutator for AZW3/MOBI (WI-9). `hostViewProvider` defaults to
    /// `{ nil }` — a container that passes `{ nil }` gets the bottom-sheet
    /// form (`resolvedForm` degrades the card with no host).
    @ViewBuilder
    func unifiedHighlightPopoverPresenterIfAvailable(
        modelContainer: ModelContainer?,
        bookFingerprintKey: String,
        mutating: (any HighlightMutating)?,
        theme: ReaderThemeV2,
        chapter: String? = nil,
        hostViewProvider: @escaping () -> UIView? = { nil }
    ) -> some View {
        if let modelContainer, let mutating {
            self.unifiedHighlightPopoverPresenter(
                viewModel: HighlightPopoverViewModel(
                    persistence: PersistenceActor(modelContainer: modelContainer),
                    bookFingerprintKey: bookFingerprintKey
                ),
                router: HighlightPopoverActionRouter(mutating: mutating),
                theme: theme,
                chapter: chapter,
                hostViewProvider: hostViewProvider
            )
        } else {
            self
        }
    }
}
#endif
