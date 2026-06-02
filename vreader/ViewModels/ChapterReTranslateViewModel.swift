// Purpose: Feature #56 WI-15 — the @MainActor, @Observable UI state for the
// per-chapter re-translation flow. Drives the provider-override picker sheet
// (`ReTranslatePickerSheet`) and the in-progress sheet (`ReTranslateProgress`).
//
// Acceptance criteria addressed:
//   (e) "per-chapter re-translate clears old cache and fetches fresh"
//   (f) "provider override for re-translate does not change the global active
//       provider"
//
// Key decisions:
// - **Cache row is deleted BEFORE the translation request**, by the
//   originally-cached key (`initialProviderProfileID` + initial promptVersion +
//   targetLanguage). Otherwise the service's cache-hit short-circuit would
//   serve the stale row and skip the network call. The new translation lands
//   under the picker-resolved key (override-profile-aware), so the old key is
//   orphaned and the delete is the only thing that frees its row.
// - **No mutation of `ProviderProfileStore`** — the picker selection lives on
//   the VM only. The resolver call carries the chosen profile + model; the
//   global active id is untouched.
// - **Source text comes through a closure** (`sourceTextProvider`) so a test
//   can supply a deterministic string without standing up a real
//   `ChapterTextProviding` actor. The host wires it to the live provider.
// - **Progress is real N-of-M** (Bug #311). Setup ticks 0% → 0.25 (cache
//   delete) → 0.5 (provider resolved); the translate phase then advances 0.5 →
//   0.95 driven by `ChapterTranslationService`'s per-chunk `onChunkProgress`
//   callback (committed-chunk count), and 1.0 is set when the flow finishes
//   (cache-write + host apply). Previously the translate phase was a faked 0.5
//   pin for the whole opaque request, which read as "stuck" on slow chapters.
// - **Empty source text completes immediately** — the runner is skipped, the
//   host callback is called with `[]`, the sheet moves to `.complete`. Mirrors
//   the service's own empty-segments contract (`translate(...)` returns
//   `[]/.miss` for empty source).
// - **Errors surface back to the picker**, not the progress sheet. A user who
//   sees an inline error needs to pick a different provider — not stare at a
//   stopped spinner. The picker re-renders with `lastError` visible.
//
// @coordinates-with: ChapterTranslationStore.swift,
//   ChapterTranslationService.swift, AIService.swift,
//   ReTranslatePickerSheet.swift, ReTranslateProgress.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import Foundation
import OSLog
import Observation

// Boundary protocols (`RetranslateProviderResolving`, `ChapterReTranslating`)
// live in `ChapterReTranslateBoundaries.swift` so this file stays under the
// 300-LoC budget (rule 50 §9).

// MARK: - Picker selection

/// The picker's current selection — the user's choice of provider, model,
/// style, and "keep glossary" toggle. Owned by the VM; mutates only through
/// `updateSelection(_:)` so the VM can react.
struct ReTranslatePickerSelection: Equatable, Sendable {
    var providerProfileID: UUID
    var model: String
    var style: TranslationStyle
    /// The design depicts a "Keep term overrides" toggle (`vreader-retranslate.jsx`).
    /// vreader has no glossary storage yet; the toggle is wired UI state with
    /// no current behavior change. Forward-compat for when glossary lands.
    var keepGlossary: Bool
}

// MARK: - Sheet state

/// The VM's `View`-facing state machine. The picker sheet binds to this and
/// renders the picker / progress / complete / error views accordingly.
enum ReTranslateSheetState: Equatable, Sendable {
    /// No sheet shown.
    case dismissed
    /// Picker is visible. `lastError` may be non-nil from a previous attempt.
    case picker
    /// Translation in flight. The progress sheet is shown.
    case running
    /// Translation finished. The host shows a transient acknowledgement and
    /// dismisses; the VM transitions back to `.dismissed` on `dismiss()`.
    case complete
}

// MARK: - View model

/// `@MainActor`, `@Observable` view model for the per-chapter re-translate
/// flow. One instance per reader; the host calls `presentPicker(...)` when the
/// More-menu re-translate row fires, then binds the picker / progress sheets
/// to `sheetState` and `selection`.
@MainActor
@Observable
final class ChapterReTranslateViewModel {

    // MARK: - Public state

    /// Current sheet state — drives picker / progress / complete UI.
    private(set) var sheetState: ReTranslateSheetState = .dismissed

    /// The picker's current selection. Mutated only via `updateSelection(_:)`.
    private(set) var selection: ReTranslatePickerSelection

    /// The chapter being re-translated — the unit whose cache row will be
    /// cleared and re-fetched.
    private(set) var unit: TranslationUnitID?

    /// Human-readable title for the picker's context strip (e.g. chapter 6
    /// title). Optional — when nil the picker falls back to the unit's storage
    /// key, but the host should always supply it.
    private(set) var unitTitle: String?

    /// Target language — the picker shows this in the context strip and the
    /// translation uses it.
    private(set) var targetLanguage: String = "Chinese"

    /// Progress for the in-flight re-translate (Bug #311): 0 → 0.25 (cache
    /// delete) → 0.5 (provider resolved) → 0.5…0.95 (real per-chunk N-of-M from
    /// the service's `onChunkProgress`) → 1.0 (applied). Monotonic.
    private(set) var progress: Double = 0.0

    /// The most recent error message, displayed inline at the top of the
    /// picker so the user can pick a different provider and retry.
    private(set) var lastError: String?

    /// Optional callback fired when a re-translation succeeds — the host
    /// updates its `BilingualReadingViewModel.translationsByUnit` so the
    /// reader re-renders with the fresh segments. Set by the host that owns
    /// the bilingual VM.
    var onTranslationApplied: ((TranslationUnitID, [String]) -> Void)?

    // MARK: - Dependencies (injected)

    let bookFingerprintKey: String
    let promptVersion: String
    let initialProviderProfileID: UUID

    private let resolver: any RetranslateProviderResolving
    private let runner: any ChapterReTranslating
    private let store: ChapterTranslationStore
    /// Asynchronous source-text provider. Adapters resolve the unit's text
    /// off the main thread (PDFKit page extraction, EPUB spine read, Foliate
    /// WKWebView message) — wrapping this in `@Sendable async throws` lets
    /// the host stay on the main actor while the actual text resolution
    /// suspends, AND lets the VM differentiate three outcomes: an empty
    /// string returned (legitimately empty unit, complete with no work), a
    /// `CancellationError` thrown (cancel path, return to picker), or any
    /// other thrown error (surface in the picker's error banner).
    ///
    /// **Critical fix (Codex Gate-4 round-1 Critical, thread
    /// `019e4399-b8cd`)**: the previous signature was non-throwing with the
    /// host wrapping the call in `try?` — any thrown error from the
    /// underlying `ChapterTextProviding.sourceText(for:)` collapsed to
    /// empty text, the VM's empty-source branch treated it as success,
    /// posted `[]` back into the bilingual VM, and ended in `.complete` —
    /// while having already deleted the original cache row. The throwing
    /// signature surfaces the failure honestly so the VM can roll back to
    /// the picker without a misleading "Re-translated" success state.
    private let sourceTextProvider: @Sendable (TranslationUnitID) async throws -> String
    private let log = Logger(subsystem: "com.vreader.app", category: "ChapterReTranslateViewModel")

    /// In-flight translation task — cancelled by `cancel()`.
    private var inFlightTask: Task<Void, Never>?

    /// Bug #311 (Codex Gate-4 Medium): monotonically-increasing run id. Each
    /// `submit()` captures the current value into its per-chunk progress
    /// callback; `applyChunkProgress` applies a tick ONLY if its captured
    /// generation still matches AND the sheet is still `.running`. Bumped on
    /// `submit()` (new run), `cancel()`, and `dismiss()` so a queued tick from a
    /// cancelled / superseded / finished run can never move a new or idle bar
    /// (the `max()` guard alone only protects the terminal 1.0, not the reset-to-
    /// 0.0 cancel / retry paths).
    private var runGeneration = 0

    init(
        bookFingerprintKey: String,
        promptVersion: String,
        initialProviderProfileID: UUID,
        initialModel: String,
        initialStyle: TranslationStyle = .natural,
        initialKeepGlossary: Bool = true,
        resolver: any RetranslateProviderResolving,
        runner: any ChapterReTranslating,
        store: ChapterTranslationStore,
        sourceTextProvider: @escaping @Sendable (TranslationUnitID) async throws -> String
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.promptVersion = promptVersion
        self.initialProviderProfileID = initialProviderProfileID
        self.resolver = resolver
        self.runner = runner
        self.store = store
        self.sourceTextProvider = sourceTextProvider
        self.selection = ReTranslatePickerSelection(
            providerProfileID: initialProviderProfileID,
            model: initialModel,
            style: initialStyle,
            keepGlossary: initialKeepGlossary)
    }

    // MARK: - Presentation lifecycle

    /// Opens the picker for `unit`. The host calls this from the
    /// `.readerMoreReTranslateChapter` notification observer.
    func presentPicker(
        unit: TranslationUnitID, unitTitle: String?, targetLanguage: String
    ) {
        self.unit = unit
        self.unitTitle = unitTitle
        self.targetLanguage = targetLanguage
        self.lastError = nil
        self.progress = 0.0
        // Reset picker selection ONLY of state derived from the unit. The
        // user's last provider/model/style choice persists across openings —
        // matches the design intent ("pre-populates the provider + model +
        // style that the bilingual mode setup sheet established").
        self.sheetState = .picker
    }

    /// Dismisses the sheet. Cancels any in-flight task.
    func dismiss() {
        inFlightTask?.cancel()
        inFlightTask = nil
        runGeneration &+= 1  // invalidate any queued progress ticks
        sheetState = .dismissed
        progress = 0.0
    }

    /// Picker → Progress cancel. Restores the picker so the user can retry or
    /// change provider.
    func cancel() {
        inFlightTask?.cancel()
        inFlightTask = nil
        runGeneration &+= 1  // invalidate any queued progress ticks from this run
        progress = 0.0
        // A cancel from .running returns to .picker so the user can decide
        // whether to retry or change selection.
        if sheetState == .running { sheetState = .picker }
    }

    // MARK: - Selection mutation

    /// Apply a picker change via a transform closure. Atomic so the resulting
    /// selection state is always consistent (e.g. changing provider resets the
    /// model to that provider's first option).
    func updateSelection(_ transform: (inout ReTranslatePickerSelection) -> Void) {
        var copy = selection
        transform(&copy)
        selection = copy
    }

    // MARK: - Submit — the re-translate action

    /// Runs the re-translate flow: delete the original cache row → resolve the
    /// picker's provider config → call the translation runner → on success,
    /// fire `onTranslationApplied`. Errors surface back to the picker.
    func submit() async {
        guard let unit else {
            log.error("submit() called with no unit")
            return
        }

        runGeneration &+= 1
        let generation = runGeneration
        sheetState = .running
        progress = 0.0
        lastError = nil

        // Capture the work into a Task so .cancel() can stop it. The Task is
        // explicitly typed `Task<Void, Never>` — `self?.runSubmit(...)` would
        // otherwise produce `Task<()?, Never>`, which doesn't match the
        // `inFlightTask` field.
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runSubmit(unit: unit, generation: generation)
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    /// The inner submit pipeline. Split out so the Task body is small and the
    /// guard / progression is obvious.
    private func runSubmit(unit: TranslationUnitID, generation: Int) async {
        // 1. Delete the cache row for the ORIGINAL profile so a subsequent
        //    cache lookup on the original key returns nil. The new translation
        //    lands under the (potentially overridden) picker key; the original
        //    row would otherwise stay live and continue to serve a stale hit
        //    when bilingual mode is on with the original profile.
        let originalKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: bookFingerprintKey,
            unitStorageKey: unit.storageKey,
            targetLanguage: targetLanguage,
            providerProfileID: initialProviderProfileID,
            promptVersion: promptVersion)
        do {
            try await store.deleteTranslation(forKey: originalKey)
        } catch {
            // Logged-and-swallowed (rule 50 §6) — a delete failure does NOT
            // block re-translation. If the original row is still live, the
            // re-translate still writes a fresh row under the new key; only
            // an inconsistent cache state remains, which the next re-translate
            // resolves.
            log.error("delete-before-retranslate failed: \(String(describing: error), privacy: .public)")
        }

        progress = 0.25

        // 2. Source text for the unit. Three outcomes (Codex Gate-4 round-1
        //    Critical, thread `019e4399-b8cd`):
        //    - empty string returned → legitimately empty unit, complete.
        //    - CancellationError thrown → cancel path; restore picker.
        //    - any other Error thrown → surface in picker, do NOT post a
        //      misleading "Re-translated" success.
        let sourceText: String
        do {
            sourceText = try await sourceTextProvider(unit)
        } catch is CancellationError {
            // Cancellation: cancel() (or a dismiss) already restored state.
            return
        } catch {
            log.error("sourceText(for:) failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't read the chapter text. Try again."
            sheetState = .picker
            return
        }
        guard !sourceText.isEmpty else {
            log.info("empty source text for unit \(unit.storageKey, privacy: .public); skipping")
            onTranslationApplied?(unit, [])
            progress = 1.0
            sheetState = .complete
            return
        }

        // 3. Resolve provider config (the picker's choice).
        let config: ResolvedAIProviderConfig
        do {
            config = try await resolver.resolveProviderConfig(
                profileID: selection.providerProfileID,
                modelOverride: selection.model)
        } catch {
            log.error("resolveProviderConfig failed: \(String(describing: error), privacy: .public)")
            lastError = errorMessage(from: error)
            sheetState = .picker
            return
        }

        progress = 0.5

        // 4. Run the translation. On cancel, the task body unwinds and the
        //    cancel() path has already returned the sheet to .picker.
        let result: ChapterTranslationResult
        do {
            result = try await runner.translateForRetranslate(
                bookFingerprintKey: bookFingerprintKey,
                unit: unit,
                sourceText: sourceText,
                targetLanguage: targetLanguage,
                providerProfileID: selection.providerProfileID,
                config: config,
                style: selection.style,
                granularity: .paragraph,
                // Bug #311: real N-of-M progress. The service fires this from
                // its actor as each chunk lands; hop to the main actor to update
                // the @Observable bar. `applyChunkProgress` is monotonic-guarded
                // so a late callback can never undo the terminal 1.0 below.
                onChunkProgress: { [weak self] done, total in
                    Task { @MainActor in self?.applyChunkProgress(done, total, generation: generation) }
                })
        } catch is CancellationError {
            // Cancellation: cancel() already restored state. Bail.
            return
        } catch {
            log.error("translate failed: \(String(describing: error), privacy: .public)")
            lastError = errorMessage(from: error)
            sheetState = .picker
            return
        }

        progress = 1.0
        // 5. Apply translations to the bilingual VM (via host callback).
        onTranslationApplied?(unit, result.segments)
        sheetState = .complete
    }

    // MARK: - Progress mapping (Bug #311)

    /// Maps real chunk completion into the translate phase's slice of the bar.
    /// The flow is 0.25 (cache delete) → 0.5 (provider resolved) → [translate]
    /// → 1.0 (applied); this owns the [translate] slice: a 0.5 baseline at zero
    /// chunks rising toward — but never reaching — 1.0, because the terminal 1.0
    /// is set only when the whole flow finishes (cache-write + host apply), so
    /// the bar never claims 100% mid-flight. `totalChunks <= 0` (defensive, e.g.
    /// an empty chunking) returns the 0.5 baseline.
    static func translateProgress(chunksDone: Int, totalChunks: Int) -> Double {
        guard totalChunks > 0 else { return 0.5 }
        let clamped = min(max(chunksDone, 0), totalChunks)
        let fraction = Double(clamped) / Double(totalChunks)
        // Translate phase occupies 0.5 → 0.95; the 0.95…1.0 head is reserved
        // for the post-translate cache-write + apply.
        return 0.5 + 0.45 * fraction
    }

    /// Applies a per-chunk progress tick to `progress`. Guards (Codex Gate-4
    /// Medium): the tick is dropped unless its captured `generation` still
    /// matches the current run AND the sheet is still `.running` — so a tick
    /// queued (via the actor→main hop) by a cancelled / superseded / finished
    /// run can't move a new or idle bar. Within a live run it is MONOTONIC: the
    /// mapped value is always < 1.0, so a late tick can't undo the terminal 1.0.
    private func applyChunkProgress(_ chunksDone: Int, _ totalChunks: Int, generation: Int) {
        guard generation == runGeneration, sheetState == .running else { return }
        progress = max(progress, Self.translateProgress(chunksDone: chunksDone, totalChunks: totalChunks))
    }

    // MARK: - Error formatting

    /// Produces a short user-facing string from a translation error. The full
    /// error is logged separately at the call site.
    private func errorMessage(from error: Error) -> String {
        if let translationError = error as? ChapterTranslationError {
            switch translationError {
            case .offline:
                return "You appear to be offline. Try again when you have a connection."
            case .providerFailed(let message):
                return "Translation failed: \(message)"
            case .cancelled:
                return "Translation was cancelled."
            }
        }
        return "Translation failed: \(error.localizedDescription)"
    }
}
