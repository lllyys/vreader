// Purpose: Loads and prepares a TXT file for reading — service open + position
// restore. Extracted from TXTReaderViewModel.open() in WI-008d to reduce VM size.
//
// Key decisions:
// - Pure function (enum namespace) — no state, no MainActor.
// - Throws original TXTServiceError without wrapping.
// - Position restore is non-fatal (falls back to offset 0).
// - Offset is clamped to text length to prevent out-of-bounds.
// - Checks Task.isCancelled between service open and position restore.
// - Reports whether a saved position was found (for restore-suppress logic).
// - Chapter-based load path (WI-5) resolves saved position to a chapter index.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTServiceProtocol.swift,
//   ReadingPositionPersisting.swift, TXTChapterIndex.swift, TXTOffsetTranslator.swift

import Foundation

/// Result of loading a TXT file.
struct TXTLoadResult: Sendable {
    let metadata: TXTFileMetadata
    let restoredOffsetUTF16: Int
    /// Whether a saved position was found and restored (drives scroll-suppress).
    let hadSavedPosition: Bool
}

/// Loads a TXT file: opens via service and restores the saved reading position.
enum TXTFileLoader {

    /// Opens the file via the given service and restores the saved position.
    /// Throws the original service error on failure — no wrapping.
    static func load(
        url: URL,
        service: any TXTServiceProtocol,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async throws -> TXTLoadResult {
        // Stage 1: Open via service (throws on failure)
        let meta = try await service.open(url: url)

        // Early exit if cancelled — close service to avoid leak
        if Task.isCancelled {
            await service.close()
            throw CancellationError()
        }

        // Stage 2: Restore saved position (non-fatal)
        let (offset, hadSaved) = await restoreOffset(
            textLengthUTF16: meta.totalTextLengthUTF16,
            positionStore: positionStore,
            bookFingerprintKey: bookFingerprintKey
        )

        return TXTLoadResult(
            metadata: meta,
            restoredOffsetUTF16: offset,
            hadSavedPosition: hadSaved
        )
    }

    // MARK: - Private

    private static func restoreOffset(
        textLengthUTF16: Int,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async -> (offset: Int, hadSaved: Bool) {
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedOffset = savedLocator.charOffsetUTF16 {
                return (clamp(savedOffset, max: textLengthUTF16), true)
            }
        } catch {
            // Position restore failure is non-fatal — fall back to 0
        }
        return (0, false)
    }

    private static func clamp(_ offset: Int, max: Int) -> Int {
        min(Swift.max(offset, 0), max)
    }
}

// MARK: - Chapter-Based Loading (WI-5)

/// Result of chapter-based file loading.
struct TXTChapterLoadResult: Sendable {
    let chapterOpenResult: TXTChapterOpenResult
    /// Zero-based chapter index to display initially.
    let initialChapterIndex: Int
    /// UTF-16 offset within the initial chapter (for scroll restore).
    let restoredLocalOffsetUTF16: Int
    /// Whether a saved position was found (for restore-suppress logic).
    let hadSavedPosition: Bool
}

extension TXTFileLoader {

    /// Opens the file using chapter-based lazy loading and resolves saved position.
    static func loadChapterBased(
        url: URL,
        service: any TXTServiceProtocol,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async throws -> TXTChapterLoadResult {
        // Stage 1: Open via chapter-based service (throws on failure)
        let openResult = try await service.openChapterBased(url: url)

        // Early exit if cancelled — close service to avoid leak
        if Task.isCancelled {
            await service.close()
            throw CancellationError()
        }

        // Stage 2: Resolve saved position to chapter + local offset
        let chapters = openResult.chapterIndex.chapters
        let (initialIdx, localOffset, hadSaved) = await resolveChapterPosition(
            chapters: chapters,
            positionStore: positionStore,
            bookFingerprintKey: bookFingerprintKey
        )

        return TXTChapterLoadResult(
            chapterOpenResult: openResult,
            initialChapterIndex: initialIdx,
            restoredLocalOffsetUTF16: localOffset,
            hadSavedPosition: hadSaved
        )
    }

    /// Resolves saved position to chapter index + local offset.
    /// GH #30: Prefers `txtchapter:N:M` href (direct, no drift) over global
    /// UTF-16 binary search (fragile for multi-byte encodings).
    private static func resolveChapterPosition(
        chapters: [TXTChapter],
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async -> (chapterIndex: Int, localOffset: Int, hadSaved: Bool) {
        do {
            guard let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            ) else { return (0, 0, false) }

            // GH #30: Prefer chapter-encoded href (no offset drift)
            if let href = savedLocator.href,
               let parsed = parseChapterHref(href),
               parsed.chapterIndex >= 0, parsed.chapterIndex < chapters.count {
                let maxLocal = chapters[parsed.chapterIndex].textLengthUTF16
                let clamped = min(max(parsed.localOffset, 0), max(maxLocal, 0))
                return (parsed.chapterIndex, clamped, true)
            }

            // Fallback: global UTF-16 offset binary search (legacy locators)
            if let savedOffset = savedLocator.charOffsetUTF16 {
                if let localPos = TXTOffsetTranslator.toLocal(
                    globalUTF16: savedOffset, chapters: chapters
                ) {
                    return (localPos.chapterIndex, localPos.localOffsetUTF16, true)
                }
                if !chapters.isEmpty {
                    return (chapters.count - 1, 0, true)
                }
            }
        } catch {
            // Non-fatal — fall back to chapter 0
        }
        return (0, 0, false)
    }

    /// Parses "txtchapter:{index}:{localOffset}" from a Locator href.
    private static func parseChapterHref(_ href: String) -> (chapterIndex: Int, localOffset: Int)? {
        let parts = href.split(separator: ":")
        guard parts.count == 3, parts[0] == "txtchapter",
              let idx = Int(parts[1]), let offset = Int(parts[2]) else { return nil }
        return (idx, offset)
    }
}
