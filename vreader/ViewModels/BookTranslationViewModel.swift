// Purpose: Feature #56 WI-14 — @MainActor, @Observable UI state for the
// global "translate entire book" flow. Drives the confirm alert
// (estimate), the status sheet (subscribes to BookTranslationCoordinator
// progress), and the cancel alert. One per book, created lazily by the
// Book Details sheet / library card / reader chrome.
//
// Key decisions:
// - **@MainActor** because every flag here drives a SwiftUI binding
//   directly. Per `.claude/rules/50-codebase-conventions.md` §1, view
//   models in this codebase are @MainActor + @Observable.
// - **No singleton.** This is one instance per (book, surface) — Book
//   Details makes one, the library long-press flow makes one. The shared
//   state — actual job state — lives on `BookTranslationCoordinator.shared`,
//   so two view models for the same book observe the same job.
// - **Cancel is two-step.** `requestCancel()` opens the cancel
//   confirmation alert (the design's `TranslateCancelAlert`); only
//   `confirmCancel()` actually tells the coordinator to stop. This
//   pattern matches the design — the alert disabuses the user that
//   cached chapters will be lost.
// - The VM does not own the AsyncStream subscription — `startObserving()`
//   spawns a `Task` whose lifetime is tied to the VM (`deinit` cancels
//   it). Without this we'd leak the subscription on every transient VM.
//
// @coordinates-with: BookTranslationCoordinator.swift,
//   BookTranslationProgress.swift, ChapterTextProviding.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-14)

import Foundation
import OSLog

/// @MainActor, @Observable view model for the global translate-entire-book
/// flow. One instance per surface (Book Details sheet, library long-press,
/// reader chrome) — multiple instances for the same book observe the same
/// `BookTranslationCoordinator.shared` job.
@MainActor
@Observable
final class BookTranslationViewModel {

    /// The book this VM tracks. Matches `LibraryBookItem.fingerprintKey`.
    let bookFingerprintKey: String

    /// Latest progress snapshot from the coordinator. Driven by the
    /// subscription started in `startObserving()`.
    private(set) var progress: BookTranslationProgress = .idle(total: 0)

    /// Up-front estimate displayed in the confirm alert. `nil` until
    /// `presentConfirm(...)` resolves the unit count.
    private(set) var estimate: BookTranslationEstimate?

    /// Provider label to show in the confirm alert + status sheet.
    /// Resolved fresh during `presentConfirm` (Codex Gate-4 medium
    /// finding) so a profile change between Book Details open and the
    /// translate tap is reflected.
    private(set) var providerLabel: String = "AI provider"

    /// SwiftUI sheet/alert flags.
    var isShowingConfirmAlert: Bool = false
    var isShowingStatusSheet: Bool = false
    var isShowingCancelAlert: Bool = false

    /// Error state surfaced by the confirm-step estimate (mostly "the
    /// book has no translation units" — surfaced so the UI can show a
    /// short message rather than silently opening an empty alert).
    private(set) var estimateError: String?

    private let coordinator: BookTranslationCoordinator
    private let log = Logger(subsystem: "com.vreader.app", category: "BookTranslationViewModel")
    private var observationTask: Task<Void, Never>?

    init(bookFingerprintKey: String, coordinator: BookTranslationCoordinator) {
        self.bookFingerprintKey = bookFingerprintKey
        self.coordinator = coordinator
    }

    // No `deinit` cancellation of `observationTask` — touching a
    // @MainActor-isolated property from `deinit` (nonisolated) is a Swift
    // 6 error. Hosts call `stopObserving()` from `.onDisappear` instead;
    // for transient VMs the task simply ends when the AsyncStream finishes
    // (a closed stream is the coordinator's responsibility on terminal
    // phases — see `BookTranslationCoordinator.updateProgress`).

    // MARK: - Observation lifecycle

    /// Subscribes to the coordinator's progress stream. Idempotent — a
    /// second call replaces the existing subscription. The current
    /// snapshot is loaded synchronously so the UI shows the right state
    /// even before the first stream tick.
    func startObserving() async {
        observationTask?.cancel()
        progress = await coordinator.currentProgress(forBookWithKey: bookFingerprintKey)
        let stream = await coordinator.progressUpdates(forBookWithKey: bookFingerprintKey)
        observationTask = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                await self.update(progress: snapshot)
            }
        }
    }

    private func update(progress newProgress: BookTranslationProgress) {
        self.progress = newProgress
    }

    /// Stops the subscription — call from `onDisappear` for transient
    /// VMs to avoid stranding the stream.
    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Confirm flow

    /// Loads the estimate and shows the confirm alert. Used by the Book
    /// Details "Translate entire book…" row and the library card's
    /// long-press action. The optional `resolveProviderLabel` closure
    /// lets the host inject a live "Provider · Model" label fresh at
    /// confirm time — defaulting to the static `providerLabel` value
    /// if the host has nothing to inject.
    func presentConfirm(
        textProvider: any ChapterTextProviding,
        targetLanguage: String,
        resolveProviderLabel: (@Sendable () async -> String?)? = nil
    ) async {
        estimateError = nil
        do {
            let value = try await coordinator.estimate(
                bookFingerprintKey: bookFingerprintKey,
                textProvider: textProvider,
                targetLanguage: targetLanguage)
            estimate = value
            if let resolver = resolveProviderLabel,
               let fresh = await resolver() {
                providerLabel = fresh
            }
            isShowingConfirmAlert = true
        } catch {
            log.error("Translate-entire-book estimate failed: \(String(describing: error), privacy: .public)")
            estimateError = "Could not estimate the translation. Please try again."
            isShowingConfirmAlert = false
        }
    }

    /// Closes the confirm alert without starting a job. The Book Details
    /// "Not now" button calls this.
    func dismissConfirm() {
        isShowingConfirmAlert = false
    }

    /// User confirmed the translate-entire-book action. Hides the
    /// confirm alert, opens the status sheet so the user sees progress,
    /// and asks the coordinator to start the job (text provider was
    /// already passed to `presentConfirm`; the coordinator's start path
    /// takes the same `textProvider` so a new instance is OK).
    func confirmTranslate(
        textProvider: any ChapterTextProviding,
        targetLanguage: String,
        providerProfileID: UUID,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle
    ) async {
        isShowingConfirmAlert = false
        await startObserving()
        isShowingStatusSheet = true
        await coordinator.start(
            bookFingerprintKey: bookFingerprintKey,
            textProvider: textProvider,
            targetLanguage: targetLanguage,
            providerProfileID: providerProfileID,
            config: config,
            style: style)
    }

    // MARK: - Status sheet

    /// Opens the status sheet — called when the user taps the library-
    /// card badge or the reader-chrome banner.
    func openStatusSheet() {
        isShowingStatusSheet = true
    }

    /// Closes the status sheet (the running job is unaffected).
    func closeStatusSheet() {
        isShowingStatusSheet = false
    }

    // MARK: - Cancel flow

    /// User tapped the status sheet's "Cancel translation" button —
    /// show the confirmation alert (the design's `TranslateCancelAlert`).
    func requestCancel() {
        isShowingCancelAlert = true
    }

    /// User decided not to cancel after seeing the alert.
    func dismissCancelAlert() {
        isShowingCancelAlert = false
    }

    /// User confirmed they want to stop the job. Hides the alert + the
    /// status sheet and tells the coordinator to cancel.
    func confirmCancel() async {
        isShowingCancelAlert = false
        isShowingStatusSheet = false
        await coordinator.cancel(bookFingerprintKey: bookFingerprintKey)
    }
}
