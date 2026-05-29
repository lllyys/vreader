// Purpose: Feature #42 Phase 1 (WI-5) — @MainActor view model that opens an EPUB
// through the Readium 3.x opening flow (AssetRetriever → PublicationOpener with
// DefaultPublicationParser) off the main actor, then hands the resulting
// `Publication` back to the main actor so `ReadiumEPUBHost` can mount an
// `EPUBNavigatorViewController`. Holds the open lifecycle state (loading /
// ready / failed) the host renders, and the pure `epubPreferences(for:)`
// translation from vreader's `EPUBLayoutPreference` to Readium `EPUBPreferences`.
//
// Scope (WI-5): open + render + scroll/paginate behind the `readiumEPUBEngine`
// flag. Scope (WI-6): reading-position save + restore — the pure Readium
// `Locator` ↔ `VReaderLocator` envelope mapping pair, a debounced save driven
// by the coordinator's `locationDidChange`, and a restore that loads the saved
// envelope so the host can pass `initialLocation` into the navigator. Highlights,
// theme/font, search, and TTS land in later WIs (WI-7…WI-10).
//
// Concurrency (feature #42 round-1 Med-4): the open is `async` and runs off the
// main actor inside Readium's own executors; the `Publication` reference is
// handed back to this @MainActor VM. No WebKit/UIKit object is stored in a
// Sendable actor — the navigator itself is owned by the host's coordinator.
// The mapping functions are pure `nonisolated static` so they unit-test without
// a render; the debounced save reuses a `ReaderPositionService`-style task so
// rapid `locationDidChange` calls coalesce to one persist.
//
// @coordinates-with ReadiumEPUBHost.swift, EPUBLayoutPreference.swift,
//   VReaderLocator.swift, PersistenceActor+ReadingPosition.swift

import Foundation
import OSLog
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

@MainActor
@Observable
final class ReadiumEPUBReaderViewModel {

    /// Open lifecycle the host renders.
    enum OpenState {
        case loading
        case ready(Publication)
        case failed(String)
    }

    private(set) var state: OpenState = .loading

    private let fileURL: URL
    private let log = Logger(subsystem: "com.vreader.app", category: "ReadiumEPUB")

    /// High (Gate-4 round 2): set by `close()` to invalidate an in-flight
    /// `open()`. The host's `.onDisappear` calls `close()` while a suspended
    /// `open()` (inside the SwiftUI `.task`) may still resume and assign
    /// `.ready(publication)` after the close — re-leaking a fresh `Publication`
    /// past teardown. `open()` re-checks this after every `await` before
    /// mutating `state`, so a dismiss-during-open never installs a publication
    /// into a closed VM. `@MainActor`-isolated so the read/write is serialized.
    private var isClosed = false

    // MARK: - Position persistence (WI-6)

    private let fingerprint: DocumentFingerprint
    private let persistence: (any VReaderLocatorPersisting)?
    private let deviceId: String
    private let positionSaveDebounceNs: UInt64

    /// Debounced save task — coalesces rapid `locationDidChange` calls so only
    /// the last reported locator persists (mirrors `ReaderPositionService`).
    private var saveTask: Task<Void, Never>?
    /// Monotonic version so a flush (`close()`) can drop a stale debounced write.
    private var saveVersion: UInt64 = 0
    /// The most recent Readium locator reported by the navigator, persisted on
    /// `close()` so a dismiss before the debounce fires still saves.
    private var pendingReadiumLocator: ReadiumShared.Locator?

    /// WI-5 init kept for the render-only seam (and the existing WI-5 unit
    /// tests). Position persistence is inert when `persistence` is nil — the VM
    /// opens + renders but never saves/restores.
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.fingerprint = ReadiumEPUBReaderViewModel.fingerprintPlaceholder
        self.persistence = nil
        self.deviceId = ""
        self.positionSaveDebounceNs = 2_000_000_000
    }

    /// WI-6 init — wires reading-position save/restore through the injected
    /// persistence boundary. The host constructs this when it has a
    /// `modelContainer`.
    init(
        fileURL: URL,
        fingerprint: DocumentFingerprint,
        persistence: any VReaderLocatorPersisting,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.fileURL = fileURL
        self.fingerprint = fingerprint
        self.persistence = persistence
        self.deviceId = deviceId
        self.positionSaveDebounceNs = positionSaveDebounceNs
    }

    /// A throwaway fingerprint for the render-only WI-5 init; never persisted
    /// (the WI-5 init leaves `persistence` nil, so the mapping is never invoked).
    private static let fingerprintPlaceholder = DocumentFingerprint(
        contentSHA256: String(repeating: "0", count: 64),
        fileByteCount: 0,
        format: .epub
    )

    // MARK: - Opening

    /// Opens the EPUB via Readium's `AssetRetriever` → `PublicationOpener`.
    /// Idempotent: a second call after a successful open is a no-op so a
    /// transient host re-mount does not reopen. The heavy parse runs inside
    /// Readium's async executors (off the main actor); the `Publication` is
    /// stored back on this @MainActor VM.
    func open() async {
        if case .ready = state { return }
        guard !isClosed else { return }

        guard let assetURL = FileURL(url: fileURL) else {
            state = .failed("invalid file URL")
            log.error("ReadiumEPUB open: invalid FileURL")
            return
        }

        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )

        switch await assetRetriever.retrieve(url: assetURL) {
        case let .failure(error):
            guard !isClosed else { return }
            state = .failed(String(describing: error))
            log.error("ReadiumEPUB retrieve failed: \(String(describing: error), privacy: .public)")
        case let .success(asset):
            switch await opener.open(asset: asset, allowUserInteraction: false) {
            case let .failure(error):
                guard !isClosed else { return }
                state = .failed(String(describing: error))
                log.error("ReadiumEPUB open failed: \(String(describing: error), privacy: .public)")
            case let .success(publication):
                // High (Gate-4 round 2): the host disappeared mid-open — do
                // NOT install the freshly-opened publication into a closed VM.
                guard !isClosed else { return }
                state = .ready(publication)
                log.info("ReadiumEPUB opened: \(publication.metadata.title ?? "untitled", privacy: .public)")
            }
        }
    }

    // MARK: - Teardown

    /// Releases the open `Publication` (dropping Readium's container + the
    /// EPUB's open file handles) and returns to the loading state. Called from
    /// the host's `.onDisappear` when the reader genuinely leaves the hierarchy
    /// (nav pop) so the publication is freed deterministically rather than
    /// waiting on `@State` teardown timing — the bug-#252 lesson applied to the
    /// Readium engine: tie the close to the resource owner (the host). The
    /// navigator/registry side of teardown is handled by the representable's
    /// `dismantleUIViewController`. Idempotent. Sets `isClosed` first so an
    /// in-flight `open()` that resumes after this point cannot re-install a
    /// publication (Gate-4 round-2 High).
    func close() {
        isClosed = true
        state = .loading
        // Synchronous close() is the WI-5 render-only test seam — `persistence`
        // is nil there, so nothing is ever pending. Just cancel the timer. The
        // host uses the awaitable `closeAndFlush()` so the final position is
        // guaranteed to persist before suspension.
        saveVersion &+= 1
        saveTask?.cancel()
        saveTask = nil
        pendingReadiumLocator = nil
    }

    /// Awaitable teardown for the host's `.onDisappear`: resets state, flushes a
    /// still-pending debounced save, AND awaits any in-flight persist, so the
    /// final position is guaranteed written before iOS suspends the app (the
    /// host wraps this in `beginBackgroundTask`). Mirrors `EPUBReaderViewModel`.
    ///
    /// Gate-4 round-1 High: the debounce task can already have consumed the
    /// pending locator and be mid-`persist` when teardown fires. Cancelling the
    /// task only stops its `Task.sleep`, not an already-running DB write — so we
    /// both flush a still-pending locator AND `await` the in-flight task's value.
    /// Exactly one of the two paths fires (pending is nil once the task consumes
    /// it), so there is no double-persist; all state is `@MainActor`-serialized.
    func closeAndFlush() async {
        isClosed = true
        state = .loading
        saveVersion &+= 1
        let inFlight = saveTask
        saveTask?.cancel()
        saveTask = nil
        let pending = pendingReadiumLocator
        pendingReadiumLocator = nil
        if let pending {
            // The debounce hadn't fired yet (locator still pending) — persist now.
            await persist(pending)
        }
        // Await a persist the debounce task already started before we cancelled.
        await inFlight?.value
    }

    /// Surface an `EPUBNavigatorViewController` init failure (thrown from the
    /// representable's `makeUIViewController`) into the host's render state so
    /// the host swaps in its `.failed` error view instead of leaving an empty
    /// placeholder controller on screen.
    func markNavigatorInitFailed(_ message: String) {
        state = .failed(message)
    }

    // MARK: - Preferences mapping (pure)

    /// Translates vreader's `EPUBLayoutPreference` into a Readium
    /// `EPUBPreferences`. `.scroll` → continuous vertical scroll
    /// (`scroll: true`); `.paged` → horizontal paginated (`scroll: false`).
    /// Pure + static so the mapping is unit-testable without a render.
    nonisolated static func epubPreferences(for layout: EPUBLayoutPreference) -> EPUBPreferences {
        EPUBPreferences(scroll: layout == .scroll)
    }

    // MARK: - Position save / restore (WI-6)

    /// Schedules a debounced position save from the coordinator's
    /// `locationDidChange`. Rapid calls coalesce — only the last locator
    /// persists after `positionSaveDebounceNs`. Inert when persistence is nil
    /// (render-only WI-5 init) or the VM is closed.
    func save(readiumLocator: ReadiumShared.Locator) {
        guard persistence != nil, !isClosed else { return }
        pendingReadiumLocator = readiumLocator

        saveVersion &+= 1
        let capturedVersion = saveVersion
        let debounce = positionSaveDebounceNs
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled, let self, self.saveVersion == capturedVersion else { return }
            let loc = self.pendingReadiumLocator
            self.pendingReadiumLocator = nil
            if let loc { await self.persist(loc) }
        }
    }

    /// Loads the saved position and maps it back to a Readium `Locator` for the
    /// host to pass as the navigator's `initialLocation`. Returns nil when there
    /// is nothing to restore (no persistence, no saved envelope, non-Readium
    /// envelope, or a decode failure).
    func restoredReadiumLocator() async -> ReadiumShared.Locator? {
        guard let persistence else { return nil }
        let envelope = try? await persistence.loadVReaderLocator(
            bookFingerprintKey: fingerprint.canonicalKey
        )
        guard let envelope else { return nil }
        return ReadiumEPUBReaderViewModel.readiumLocator(from: envelope)
    }

    /// Awaitable envelope dual-write. Maps the Readium locator → envelope +
    /// legacy `Locator` and saves both in one transaction. Persistence errors
    /// are non-fatal (logged) — a failed position save degrades gracefully.
    private func persist(_ readiumLocator: ReadiumShared.Locator) async {
        guard let persistence else { return }
        guard let envelope = ReadiumEPUBReaderViewModel.makeVReaderLocator(
            from: readiumLocator,
            fingerprintKey: fingerprint.canonicalKey,
            fingerprint: fingerprint,
            originalFormat: fingerprint.format
        ), let legacy = envelope.legacyLocator else {
            log.error("ReadiumEPUB position save: failed to map locator")
            return
        }
        do {
            try await persistence.saveVReaderLocator(
                bookFingerprintKey: fingerprint.canonicalKey,
                vreaderLocator: envelope,
                legacyLocator: legacy,
                deviceId: deviceId
            )
        } catch {
            log.error(
                "ReadiumEPUB position save failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
