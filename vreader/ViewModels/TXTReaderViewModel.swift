// Purpose: ViewModel for the TXT reader view. Manages reading state,
// position persistence (via ReaderPositionService), session tracking,
// and word count estimation.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008d).
// - File loading delegated to TXTFileLoader (WI-008d).
// - Lifecycle operations (session, flush, time display) delegated to ReaderLifecycleHelper (R6).
// - Uses protocol abstractions for testability (service, persistence, tracker).
// - Staged error handling: service failure aborts, position/timestamp failures non-fatal.
// - Position uses canonical UTF-16 offsets matching TXTOffsetMapper conventions.
// - wordsRead estimated via Section 9.6 normative formula.
// - Chapter-based lazy loading (WI-5): stores chapter index and loads one chapter at a time.
//   Falls back to full-text open if chapter-based fails.
//
// @coordinates-with: TXTFileLoader.swift, ReaderLifecycleHelper.swift,
//   ReaderPositionService.swift, TXTServiceProtocol.swift,
//   ReadingPositionPersisting.swift, ReadingSessionTracker.swift,
//   LocatorFactory.swift, TXTTextViewBridge.swift,
//   TXTChapterIndex.swift, TXTChapterContentLoader.swift, TXTOffsetTranslator.swift

import Foundation

/// ViewModel for the TXT reader screen.
@Observable
@MainActor
final class TXTReaderViewModel {

    // MARK: - Published State

    /// Decoded text content (nil until open completes).
    private(set) var textContent: String?

    /// Total text length in UTF-16 code units.
    private(set) var totalTextLengthUTF16: Int = 0

    /// Total word count from metadata.
    private(set) var totalWordCount: Int = 0

    /// Current scroll position as UTF-16 char offset (global/book-level, for persistence).
    private(set) var currentOffsetUTF16: Int = 0

    /// Current scroll position within the displayed chapter (local, for progress bar).
    /// In non-chapter mode, equals currentOffsetUTF16.
    private(set) var currentChapterLocalUTF16: Int = 0

    /// Start of current selection in UTF-16 offsets (nil if no selection).
    private(set) var currentSelectionStart: Int?

    /// End of current selection in UTF-16 offsets (nil if no selection).
    private(set) var currentSelectionEnd: Int?

    /// Whether the file is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m"). Delegated to lifecycle helper.
    var sessionTimeDisplay: String? { lifecycle.sessionTimeDisplay }

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty files.
    var totalProgression: Double? {
        guard totalTextLengthUTF16 > 0 else { return nil }
        return Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
    }

    /// Estimated words read based on Section 9.6 normative formula.
    /// `wordsRead = round((abs(endOffsetUTF16 - startOffsetUTF16) / totalLen) * totalWords)`
    /// Clamped to [0, totalWordCount]. Nil if no content loaded or empty.
    var estimatedWordsRead: Int? {
        guard textContent != nil, totalTextLengthUTF16 > 0, totalWordCount > 0 else {
            return nil
        }
        let startOffset = 0 // Reading always starts from beginning
        let fraction = Double(abs(currentOffsetUTF16 - startOffset)) / Double(totalTextLengthUTF16)
        let raw = (fraction * Double(totalWordCount)).rounded()
        return min(max(Int(raw), 0), totalWordCount)
    }

    // MARK: - Dependencies

    let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    let lifecycle: ReaderLifecycleHelper
    private let txtService: any TXTServiceProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Private State

    /// Generation counter to guard against open/close races.
    private var openGeneration: Int = 0
    /// True after open() completes position restore. Guards close() from saving
    /// stale position 0 when close() races with an in-progress open().
    private var isOpenComplete = false
    /// Time until which scroll position saves are suppressed after a position restore.
    /// Handles any residual TextKit relayout callbacks that escape the bridge-level guard.
    private var restoreSuppressUntil: Date?
    /// Duration to suppress scroll saves after position restore (seconds).
    /// Must be longer than the bridge's Phase 2 restore delay (0.8s) + margin.
    private static let restoreSuppressDuration: TimeInterval = 1.5

    // MARK: - Chapter-Based State (WI-5)

    /// Chapter index for the current book (nil if using legacy full-text mode).
    private(set) var chapterIndex: TXTChapterIndex?
    /// Current chapter index being displayed.
    private(set) var currentChapterIdx: Int = 0
    /// Text content of the current chapter (replaces full textContent for display).
    private(set) var currentChapterText: String?
    /// Content loader for on-demand chapter access.
    private var chapterContentLoader: TXTChapterContentLoader?

    /// Whether the VM is in chapter-based mode (vs legacy full-text mode).
    var isChapterMode: Bool { chapterIndex != nil }

    // MARK: - Continuous-Scroll State (Bug #180 re-scoped fix)

    /// Chapter-awareness layer for continuous scroll. Non-nil only after
    /// `openContinuous` succeeds — the chaptered TXT in Scroll layout path.
    private(set) var chapterOffsetIndex: TXTChapterOffsetIndex?
    /// Whole-book text chunks fed to the continuous `UITableView` surface.
    private(set) var continuousChunks: [String]?
    /// Cumulative document-global UTF-16 start offset of each continuous chunk.
    private(set) var continuousChunkStartOffsets: [Int]?
    /// Document-global UTF-16 offset to restore the continuous surface to on
    /// first layout. Nil when no saved position.
    private(set) var continuousRestoreGlobalOffset: Int?

    /// Whether the VM is rendering chaptered TXT as one continuous surface.
    /// In continuous mode the bridge reports document-global offsets and
    /// `currentChapterIdx` is DERIVED from scroll position, not a render state.
    var isContinuousMode: Bool { chapterOffsetIndex != nil }

    /// Current chapter title (WI-6 overlay).
    var currentChapterTitle: String? {
        guard let idx = chapterIndex, currentChapterIdx < idx.count else { return nil }
        return idx.chapters[currentChapterIdx].title
    }

    /// Total chapter count (WI-6 overlay).
    var totalChapterCount: Int { chapterIndex?.count ?? 0 }

    /// Feature #68: for the current chapter, the UTF-16 length of the
    /// heading line that is part of `currentChapterText` (regex-detected
    /// chapters), or 0 when the chapter is synthetic / "前言" / has no
    /// leading heading line in its body. Drives `buildChapterStart`'s
    /// `headingLineLength` argument.
    ///
    /// Pure render-time derivation — zero migration. `TXTChapter` carries
    /// no `isSynthetic` flag (it is `Codable`-persisted), so this compares
    /// the chapter text's first line, trimmed, to the chapter title,
    /// trimmed. A regex-detected chapter's first body line IS the matched
    /// heading line (the regex builder sets the chapter's UTF-16 start to
    /// that line); the length returned excludes the trailing newline so
    /// the restyle runs over the visible line only. Synthetic ("Chapter
    /// N") and "前言" chapters return 0 because neither title appears
    /// verbatim as the body's first line.
    var currentChapterHeadingLineLength: Int {
        Self.headingLineLength(
            chapterText: currentChapterText, chapterTitle: currentChapterTitle
        )
    }

    /// Pure derivation behind `currentChapterHeadingLineLength` —
    /// extracted as a `static` so it is directly unit-testable without
    /// constructing a fully-loaded chapter index (feature #68 WI-2).
    ///
    /// Returns the UTF-16 length of `chapterText`'s first line (excluding
    /// the trailing newline) when that line, trimmed, equals
    /// `chapterTitle` trimmed — i.e. the chapter is regex-detected and
    /// its heading line is part of the body. Returns 0 otherwise:
    /// synthetic ("Chapter N") and "前言" chapters never have their title
    /// verbatim as the body's first line.
    nonisolated static func headingLineLength(
        chapterText: String?, chapterTitle: String?
    ) -> Int {
        guard let text = chapterText, !text.isEmpty,
              let title = chapterTitle else { return 0 }
        let nsText = text as NSString
        let firstNewline = nsText.rangeOfCharacter(from: CharacterSet.newlines)
        let firstLineLength = firstNewline.location == NSNotFound
            ? nsText.length
            : firstNewline.location
        guard firstLineLength > 0 else { return 0 }
        let firstLine = nsText.substring(to: firstLineLength)
        let trimmedFirstLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedFirstLine == trimmedTitle else { return 0 }
        return firstLineLength
    }

    /// Whether there is a next chapter (WI-6 overlay).
    var hasNextChapter: Bool { chapterIndex.map { currentChapterIdx < $0.count - 1 } ?? false }

    /// Whether there is a previous chapter (WI-6 overlay).
    var hasPreviousChapter: Bool { currentChapterIdx > 0 }

    /// Scroll fraction within the current chapter (0.0-1.0). For progress bar binding.
    /// In continuous mode (Bug #180), the per-chapter fraction is derived from
    /// the document-global offset via `chapterOffsetIndex`. In chapter (Paged)
    /// mode, uses the loaded chapter text length. In non-chapter mode, uses
    /// `totalTextLengthUTF16` as denominator.
    var chapterScrollFraction: Double {
        if let offsetIndex = chapterOffsetIndex {
            return offsetIndex.chapterLocalFraction(globalUTF16: currentOffsetUTF16).fraction
        }
        let len = isChapterMode
            ? (currentChapterText?.utf16.count ?? 0)
            : totalTextLengthUTF16
        guard len > 0 else { return 0 }
        return Double(min(currentChapterLocalUTF16, len)) / Double(len)
    }

    /// Book-level progress from chapter position + scroll fraction (WI-6 overlay).
    func chapterBasedProgression(scrollFraction: Double) -> Double {
        guard let idx = chapterIndex, idx.count > 0 else { return 0 }
        return (Double(currentChapterIdx) + scrollFraction) / Double(idx.count)
    }

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        txtService: any TXTServiceProtocol,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.txtService = txtService
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        let posService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
        self.positionService = posService
        self.lifecycle = ReaderLifecycleHelper(
            bookFingerprint: bookFingerprint,
            positionService: posService,
            sessionTracker: sessionTracker,
            positionStore: positionStore
        )
    }

    // MARK: - Lifecycle

    /// Opens the TXT file and restores the saved reading position.
    func open(url: URL) async {
        guard !isLoading else { return }

        // Guard against re-open: close previous state first
        if textContent != nil {
            await close()
        }

        openGeneration += 1
        let myGeneration = openGeneration
        isOpenComplete = false

        isLoading = true
        errorMessage = nil

        // Stage 1+2: Load, decode, and restore position (via TXTFileLoader)
        let loadResult: TXTLoadResult
        do {
            loadResult = try await TXTFileLoader.load(
                url: url,
                service: txtService,
                positionStore: positionStore,
                bookFingerprintKey: bookFingerprintKey
            )
        } catch is CancellationError {
            resetState()
            isLoading = false
            return
        } catch {
            resetState()
            isLoading = false
            errorMessage = (error as? TXTServiceError).map(describeServiceError)
                ?? "Failed to open file."
            return
        }

        guard myGeneration == openGeneration else {
            await txtService.close()
            isLoading = false
            return
        }

        // Set content ASAP so the view can start rendering
        textContent = loadResult.metadata.text
        totalTextLengthUTF16 = loadResult.metadata.totalTextLengthUTF16
        totalWordCount = loadResult.metadata.totalWordCount
        currentOffsetUTF16 = loadResult.restoredOffsetUTF16

        restoreSuppressUntil = loadResult.hadSavedPosition
            ? Date().addingTimeInterval(Self.restoreSuppressDuration)
            : nil

        // PERF: Show content immediately — session/lastOpened are non-blocking
        isOpenComplete = true
        isLoading = false

        // Stage 3: Start reading session (fire-and-forget, non-fatal)
        do {
            try lifecycle.beginSession()
        } catch {
            // Session failure is non-fatal — user can still read
        }

        // Stage 4: Update last opened (fire-and-forget)
        Task { await lifecycle.updateLastOpened() }

        // Bug #164: seed AI/TTS with the restored locator. The suppress
        // window in `updateScrollPosition` exists to drop TextKit relayout
        // storms (storm-zero updates that would overwrite the restored
        // offset downstream). It also drops the legitimate restored offset
        // — so without an explicit post here, `startTTS()` would still see
        // `aiCoordinator.currentLocator == nil` until the user scrolls.
        broadcastPosition(makeLocator())
    }

    /// Opens the TXT file using chapter-based lazy loading (WI-5).
    /// Falls back to full-text open if chapter-based loading fails.
    func openChapterBased(url: URL) async {
        guard !isLoading else { return }
        AppLogger.txt.debug("openChapterBased called")

        if textContent != nil || chapterIndex != nil { await close() }

        openGeneration += 1
        let myGeneration = openGeneration
        isOpenComplete = false
        isLoading = true
        errorMessage = nil

        let chapterLoadResult: TXTChapterLoadResult
        do {
            chapterLoadResult = try await TXTFileLoader.loadChapterBased(
                url: url, service: txtService,
                positionStore: positionStore, bookFingerprintKey: bookFingerprintKey
            )
        } catch is CancellationError {
            AppLogger.txt.debug("openChapterBased cancelled")
            resetState(); isLoading = false; return
        } catch {
            AppLogger.txt.error("openChapterBased failed, falling back: \(error)")
            await txtService.close(); isLoading = false; await open(url: url); return
        }

        guard myGeneration == openGeneration else {
            await txtService.close(); isLoading = false; return
        }

        let openResult = chapterLoadResult.chapterOpenResult
        chapterIndex = openResult.chapterIndex
        chapterContentLoader = openResult.contentLoader
        currentChapterIdx = chapterLoadResult.initialChapterIndex

        let chapters = openResult.chapterIndex.chapters
        if !chapters.isEmpty {
            let target = chapters[chapterLoadResult.initialChapterIndex]
            do {
                let text = try await openResult.contentLoader.loadChapter(target)
                currentChapterText = text; textContent = text
            } catch {
                resetChapterState(); await txtService.close(); isLoading = false; await open(url: url); return
            }
        } else {
            currentChapterText = ""; textContent = ""
        }

        totalTextLengthUTF16 = openResult.chapterIndex.totalTextLengthUTF16
        totalWordCount = 0

        if chapterLoadResult.hadSavedPosition, !chapters.isEmpty {
            let ch = chapters[chapterLoadResult.initialChapterIndex]
            currentChapterLocalUTF16 = chapterLoadResult.restoredLocalOffsetUTF16
            currentOffsetUTF16 = ch.globalStartUTF16 + chapterLoadResult.restoredLocalOffsetUTF16
        } else {
            currentChapterLocalUTF16 = 0
            currentOffsetUTF16 = 0
        }

        restoreSuppressUntil = chapterLoadResult.hadSavedPosition
            ? Date().addingTimeInterval(Self.restoreSuppressDuration) : nil

        isOpenComplete = true; isLoading = false
        AppLogger.txt.debug("openChapterBased done: chapters=\(openResult.chapterIndex.chapters.count) initialIdx=\(chapterLoadResult.initialChapterIndex) isChapterMode=\(self.isChapterMode) hadSaved=\(chapterLoadResult.hadSavedPosition) localOffset=\(self.currentChapterLocalUTF16)")
        do { try lifecycle.beginSession() } catch { /* non-fatal */ }
        Task { await lifecycle.updateLastOpened() }

        if !chapters.isEmpty {
            let loader = openResult.contentLoader
            let idx = chapterLoadResult.initialChapterIndex
            Task.detached { [chapters] in
                await loader.preloadAdjacent(currentIndex: idx, chapters: chapters)
            }
        }

        // Bug #164 (round-1 audit fix): seed AI/TTS with the restored
        // chapter-mode locator. Same rationale as `open(...)` above —
        // suppress-window logic drops the storm-zero updates AND the
        // legitimate restored offset, so we post once explicitly.
        broadcastPosition(makeLocator())
    }

    /// Opens a chaptered TXT file as one continuous scrollable surface
    /// (Bug #180 re-scoped fix). Builds the whole-book chunk array + the
    /// chapter-offset index, then resolves the saved position to a
    /// document-global offset. Falls back to legacy full-text `open` if the
    /// underlying chapter-based load fails. If the file has no chapters, the
    /// continuous surface is not built (caller routes to a non-continuous path).
    func openContinuous(url: URL) async {
        guard !isLoading else { return }
        AppLogger.txt.debug("openContinuous called")

        if textContent != nil || chapterIndex != nil { await close() }

        openGeneration += 1
        let myGeneration = openGeneration
        isOpenComplete = false
        isLoading = true
        errorMessage = nil

        let chapterLoadResult: TXTChapterLoadResult
        do {
            chapterLoadResult = try await TXTFileLoader.loadChapterBased(
                url: url, service: txtService,
                positionStore: positionStore, bookFingerprintKey: bookFingerprintKey
            )
        } catch is CancellationError {
            AppLogger.txt.debug("openContinuous cancelled")
            resetState(); isLoading = false; return
        } catch {
            AppLogger.txt.error("openContinuous failed, falling back: \(error)")
            await txtService.close(); isLoading = false; await open(url: url); return
        }

        guard myGeneration == openGeneration else {
            await txtService.close(); isLoading = false; return
        }

        let openResult = chapterLoadResult.chapterOpenResult
        let index = openResult.chapterIndex

        // Continuous scroll only solves the multi-chapter SWAP jump. A book
        // with fewer than 2 chapters (a non-chaptered file — `openChapterBased`
        // synthesizes exactly one synthetic chapter for short non-chaptered
        // text) never swaps, so it keeps the legacy small-file / large-file
        // rendering split. This preserves the plan's "non-chaptered TXT
        // unchanged" invariant.
        guard index.chapters.count >= 2 else {
            AppLogger.txt.debug("openContinuous: <2 chapters, falling back to chapter-based")
            await txtService.close(); isLoading = false
            await openChapterBased(url: url); return
        }

        // Decode the whole book once and split it into the continuous-surface
        // chunk array. A decode failure (or empty book) falls back to the
        // legacy chapter-based open so the user can still read.
        let fullText: String
        do {
            fullText = try await openResult.contentLoader.fullDecodedText()
        } catch {
            AppLogger.txt.error("openContinuous full decode failed, falling back: \(error)")
            await txtService.close(); isLoading = false
            await openChapterBased(url: url); return
        }

        guard myGeneration == openGeneration else {
            await txtService.close(); isLoading = false; return
        }

        let chunkResult = TXTContinuousChunkBuilder.build(fullText: fullText)
        guard !chunkResult.chunks.isEmpty else {
            // Empty book — fall back to the chapter-based path which handles
            // the empty-file case explicitly.
            AppLogger.txt.debug("openContinuous: empty book, falling back to chapter-based")
            await txtService.close(); isLoading = false
            await openChapterBased(url: url); return
        }

        chapterIndex = index
        chapterContentLoader = openResult.contentLoader
        chapterOffsetIndex = TXTChapterOffsetIndex.build(from: index)
        continuousChunks = chunkResult.chunks
        continuousChunkStartOffsets = chunkResult.chunkStartOffsets
        textContent = fullText
        currentChapterText = fullText
        totalTextLengthUTF16 = index.totalTextLengthUTF16
        totalWordCount = 0

        // Resolve the saved position to a document-global offset. The loader
        // already parsed `txtchapter:idx:local` / legacy global locators into
        // (chapterIndex, localOffset); convert to global via the offset index.
        //
        // Codex round-1 audit fix [Medium]: derive `currentChapterIdx` /
        // `currentChapterLocalUTF16` FROM the computed global offset rather
        // than trusting the saved (idx, local) pair. `resolveChapterPosition`
        // can clamp `localOffset` to `textLengthUTF16` at an exact chapter
        // end, which makes the global offset land on the NEXT chapter's
        // start. Deriving keeps the continuous-mode "chapter is a function
        // of global offset" invariant — so `makeLocator` does not emit a
        // stale `txtchapter:` href before the first scroll callback arrives.
        if chapterLoadResult.hadSavedPosition, !index.chapters.isEmpty,
           let offsetIndex = chapterOffsetIndex {
            let savedIdx = chapterLoadResult.initialChapterIndex
            let savedLocal = chapterLoadResult.restoredLocalOffsetUTF16
            let rawGlobal = offsetIndex.globalStart(ofChapter: savedIdx) + savedLocal
            let globalOffset = min(max(rawGlobal, 0), totalTextLengthUTF16)
            continuousRestoreGlobalOffset = globalOffset > 0 ? globalOffset : nil
            currentOffsetUTF16 = globalOffset
            let derivedIdx = offsetIndex.chapterContaining(globalOffset)
            currentChapterIdx = derivedIdx
            currentChapterLocalUTF16 = globalOffset - offsetIndex.globalStart(ofChapter: derivedIdx)
        } else {
            continuousRestoreGlobalOffset = nil
            currentOffsetUTF16 = 0
            currentChapterIdx = 0
            currentChapterLocalUTF16 = 0
        }

        restoreSuppressUntil = chapterLoadResult.hadSavedPosition
            ? Date().addingTimeInterval(Self.restoreSuppressDuration) : nil

        isOpenComplete = true; isLoading = false
        AppLogger.txt.debug("openContinuous done: chapters=\(index.chapters.count) chunks=\(chunkResult.chunks.count) restoreGlobal=\(self.continuousRestoreGlobalOffset ?? -1)")
        do { try lifecycle.beginSession() } catch { /* non-fatal */ }
        Task { await lifecycle.updateLastOpened() }

        // Bug #164: seed AI/TTS with the restored locator (see `open`).
        broadcastPosition(makeLocator())
    }

    // MARK: - Chapter Navigation (WI-5)

    /// Navigates to a specific chapter by index. No-op if out of bounds or not in chapter mode.
    /// Used by TOC / Contents-toolbar chapter jumps in the legacy single-chapter
    /// (Paged) path. In continuous mode the container's `onNavigate` instead
    /// publishes the target as a document-global `uiState.scrollToOffset`
    /// (no text swap); this swap path is the Paged fallback only.
    func navigateToChapter(_ index: Int) async {
        guard let chIdx = chapterIndex, let loader = chapterContentLoader,
              index >= 0, index < chIdx.chapters.count else { return }
        let chapter = chIdx.chapters[index]
        AppLogger.txt.debug("navigateToChapter: idx=\(index) title=\(chapter.title)")
        do {
            let text = try await loader.loadChapter(chapter)
            currentChapterIdx = index; currentChapterText = text; textContent = text
            currentChapterLocalUTF16 = 0 // Start at top of new chapter
            // Use globalStartUTF16 only if populated; otherwise estimate from byte ratio
            if chapter.globalStartUTF16 >= 0 {
                currentOffsetUTF16 = chapter.globalStartUTF16
            } else {
                // Estimate: byte position × average chars/byte ratio
                let totalBytes = chIdx.totalBytes
                let totalUTF16 = totalTextLengthUTF16
                if totalBytes > 0, totalUTF16 > 0 {
                    currentOffsetUTF16 = Int(Double(chapter.startByte) / Double(totalBytes) * Double(totalUTF16))
                } else {
                    currentOffsetUTF16 = 0
                }
            }
            // Bug #164 (round-1 audit fix): chapter nav writes
            // `currentOffsetUTF16` directly without going through
            // `updateScrollPosition`, so without an explicit post AI/TTS
            // would keep using the previous chapter's locator until the
            // user scrolls. Round-2 audit fix: only broadcast on the
            // successful-load path so a failed `loadChapter` doesn't emit
            // a bogus position-change event.
            broadcastPosition(makeLocator())
        } catch { errorMessage = "Failed to load chapter \(index + 1)." }
        let chapters = chIdx.chapters
        Task.detached { [index] in
            await loader.preloadAdjacent(currentIndex: index, chapters: chapters)
        }
    }

    /// Navigates to the chapter matching a TOC entry title.
    /// Returns true if a match was found. (GH #30)
    @discardableResult
    func navigateToChapterByTitle(_ title: String) async -> Bool {
        guard let chIdx = chapterIndex else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = chIdx.chapters.firstIndex(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }) {
            await navigateToChapter(idx)
            return true
        }
        return false
    }

    /// Navigates to the chapter containing the given global UTF-16 offset.
    /// If globalStartUTF16 is populated, uses exact match.
    /// Otherwise estimates chapter from byte-position ratio. (GH #30)
    func navigateToGlobalOffset(_ globalUTF16: Int) async {
        guard let chIdx = chapterIndex, !chIdx.chapters.isEmpty else { return }

        // Check if offsets are populated
        let hasOffsets = chIdx.chapters.first(where: { $0.globalStartUTF16 >= 0 }) != nil

        if hasOffsets {
            var targetIndex = 0
            for (i, ch) in chIdx.chapters.enumerated() {
                guard ch.globalStartUTF16 >= 0 else { continue }
                if ch.globalStartUTF16 <= globalUTF16 {
                    targetIndex = i
                } else {
                    break
                }
            }
            await navigateToChapter(targetIndex)
        } else {
            // Estimate: map UTF-16 offset to byte position, find containing chapter
            let totalUTF16 = max(totalTextLengthUTF16, 1)
            let fraction = Double(globalUTF16) / Double(totalUTF16)
            let estimatedByte = Int64(fraction * Double(chIdx.totalBytes))
            var targetIndex = 0
            for (i, ch) in chIdx.chapters.enumerated() {
                if ch.startByte <= estimatedByte {
                    targetIndex = i
                } else {
                    break
                }
            }
            await navigateToChapter(targetIndex)
        }
    }

    /// Advances to the next chapter. No-op if already at the last chapter.
    func nextChapter() async { await navigateToChapter(currentChapterIdx + 1) }

    /// Goes back to the previous chapter. No-op if already at the first chapter.
    func previousChapter() async { await navigateToChapter(currentChapterIdx - 1) }

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    func close() async {
        openGeneration += 1

        let locator = (textContent != nil && isOpenComplete) ? makeLocator() : nil
        await lifecycle.close(locator: locator)

        await txtService.close()
        resetState()
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        let locator = textContent != nil ? makeLocator() : nil
        await lifecycle.onBackground(locator: locator)
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard textContent != nil else { return }
        if let error = lifecycle.onForeground() {
            errorMessage = error
        }
    }

    // MARK: - Position Updates

    /// Called when the scroll position changes. Offset is in UTF-16 code units.
    /// In continuous mode (Bug #180), the offset is document-global: the table
    /// reports document-global offsets via `chunkStartOffsets`, and
    /// `currentChapterIdx` is DERIVED from it. In chapter (Paged) mode, the
    /// bridge reports chapter-local offsets and the global offset is computed.
    /// In non-chapter mode, local == global.
    func updateScrollPosition(charOffsetUTF16: Int) {
        guard textContent != nil, isOpenComplete else { return }
        let clamped = clampOffset(charOffsetUTF16)

        if let offsetIndex = chapterOffsetIndex {
            // Continuous mode: incoming offset is already document-global.
            // Derive the chapter; store global + chapter-local.
            currentOffsetUTF16 = clamped
            let idx = offsetIndex.chapterContaining(clamped)
            currentChapterIdx = idx
            currentChapterLocalUTF16 = clamped - offsetIndex.globalStart(ofChapter: idx)
        } else if isChapterMode, let chapters = chapterIndex?.chapters,
                  currentChapterIdx < chapters.count {
            // Chapter (Paged) mode: the bridge offset is local to the chapter.
            let chapter = chapters[currentChapterIdx]
            currentChapterLocalUTF16 = clamped
            let globalStart = chapter.globalStartUTF16 >= 0 ? chapter.globalStartUTF16 : 0
            currentOffsetUTF16 = globalStart + clamped
        } else {
            currentChapterLocalUTF16 = clamped
            currentOffsetUTF16 = clamped
        }

        // Suppress scroll position saves during the post-restore settling window.
        if let suppressUntil = restoreSuppressUntil {
            if Date() < suppressUntil { return }
            restoreSuppressUntil = nil
        }

        let locator = makeLocator()
        lifecycle.recordProgressAndScheduleSave(locator: locator)

        // Bug #164: broadcast the live position so AI/TTS pick up the user's
        // current scroll point. Native TXT (UITextView) was the only reader
        // path that wasn't posting this notification, so `startTTS()` always
        // saw `aiCoordinator.currentLocator == nil` and started from offset 0
        // even after the user had scrolled. Posting AFTER the suppress check
        // mirrors the existing save behaviour: storm-zero updates during the
        // post-restore settling window must not overwrite the restored
        // position downstream.
        broadcastPosition(locator)
    }

    /// Bug #164: posts `.readerPositionDidChange` with the supplied locator
    /// so the cross-component bus (AI coordinator / TTS) sees this view
    /// model's live position. Single source of truth for "TXT position
    /// changed" — every state mutation that moves the user's reading point
    /// (scroll, chapter nav, restore-on-open) routes through here.
    /// Suppress-window callers MUST gate this themselves (see
    /// `updateScrollPosition`); explicit non-storm callers (open / chapter
    /// nav) post unconditionally so the restored or jumped-to offset reaches
    /// AI/TTS even before the first user-driven scroll.
    private func broadcastPosition(_ locator: Locator) {
        NotificationCenter.default.post(
            name: .readerPositionDidChange, object: locator
        )
    }

    // MARK: - Selection

    /// Called when the user's text selection changes.
    /// A zero-width range (start == end) is a cursor, not a selection — clear it.
    func updateSelection(startUTF16: Int, endUTF16: Int) {
        if startUTF16 == endUTF16 {
            currentSelectionStart = nil
            currentSelectionEnd = nil
        } else {
            currentSelectionStart = clampOffset(min(startUTF16, endUTF16))
            currentSelectionEnd = clampOffset(max(startUTF16, endUTF16))
        }
    }

    /// Clears the current selection.
    func clearSelection() {
        currentSelectionStart = nil
        currentSelectionEnd = nil
    }

    // MARK: - Private: Locator Construction

    /// Full locator for position persistence.
    /// GH #30: In chapter mode, encodes chapter index + local offset in `href`
    /// so restore uses the index directly — no global offset reverse-mapping.
    func makeLocator() -> Locator {
        let progression = totalTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
            : 0.0

        let chapterHref: String? = isChapterMode
            ? "txtchapter:\(currentChapterIdx):\(currentChapterLocalUTF16)"
            : nil

        AppLogger.txt.debug("makeLocator: isChapterMode=\(self.isChapterMode) chIdx=\(self.currentChapterIdx) local=\(self.currentChapterLocalUTF16) href=\(chapterHref ?? "nil")")

        return Locator.validated(
            bookFingerprint: bookFingerprint,
            href: chapterHref,
            totalProgression: progression,
            charOffsetUTF16: currentOffsetUTF16
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: chapterHref, progression: nil, totalProgression: progression,
            cfi: nil, page: nil,
            charOffsetUTF16: currentOffsetUTF16,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Private: State Reset

    private func resetState() {
        textContent = nil
        totalTextLengthUTF16 = 0
        totalWordCount = 0
        currentOffsetUTF16 = 0
        currentSelectionStart = nil
        currentSelectionEnd = nil
        isOpenComplete = false
        restoreSuppressUntil = nil
        resetChapterState()
    }

    private func resetChapterState() {
        chapterIndex = nil
        currentChapterIdx = 0
        currentChapterText = nil
        chapterContentLoader = nil
        currentChapterLocalUTF16 = 0
        // Bug #180: clear continuous-scroll state.
        chapterOffsetIndex = nil
        continuousChunks = nil
        continuousChunkStartOffsets = nil
        continuousRestoreGlobalOffset = nil
    }

    // MARK: - Private: Offset Clamping

    private func clampOffset(_ offset: Int) -> Int {
        min(max(offset, 0), totalTextLengthUTF16)
    }

    // MARK: - Private: Error Description

    private func describeServiceError(_ error: TXTServiceError) -> String {
        switch error {
        case .fileNotFound: return "The file could not be found."
        case .encodingDetectionFailed: return "Could not detect file encoding."
        case .decodingFailed: return "The file could not be decoded."
        case .notOpen: return "No file is currently open."
        case .alreadyOpen: return "A file is already open."
        }
    }
}

// MARK: - TXTTextViewBridgeDelegate Conformance

#if canImport(UIKit)
extension TXTReaderViewModel: TXTTextViewBridgeDelegate {
    func scrollPositionDidChange(topCharOffsetUTF16: Int) {
        updateScrollPosition(charOffsetUTF16: topCharOffsetUTF16)
    }

    func selectionDidChange(utf16Range: UTF16Range) {
        updateSelection(startUTF16: utf16Range.startUTF16, endUTF16: utf16Range.endUTF16)
    }
}
#endif
