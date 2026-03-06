// Purpose: Manages background indexing queue for search.
// Ensures serial execution to avoid concurrent FTS5 index writes.
//
// Key decisions:
// - Protocol `IndexingCoordinating` for testability.
// - Uses actor isolation for thread-safe status tracking.
// - Serial queue via AsyncStream to avoid concurrent index writes.
// - Background priority tasks for non-blocking indexing.
// - Supports enqueue, cancel, and status checking.
//
// @coordinates-with SearchService.swift, SearchTextExtractor.swift

import Foundation

// MARK: - Status

/// Status of indexing for a specific book.
enum IndexingStatus: Sendable, Equatable {
    case notIndexed
    case indexing
    case indexed
    case failed(String)
}

// MARK: - Protocol

/// Protocol for managing background indexing operations.
protocol IndexingCoordinating: Sendable {
    /// Enqueues a book for background indexing.
    func enqueueIndexing(
        fingerprint: DocumentFingerprint,
        textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async

    /// Cancels pending indexing for a book.
    func cancelIndexing(fingerprint: DocumentFingerprint) async

    /// Returns the current indexing status for a book.
    func indexingStatus(fingerprint: DocumentFingerprint) async -> IndexingStatus
}

// MARK: - Implementation

/// Coordinates background indexing with serial execution.
actor BackgroundIndexingCoordinator: IndexingCoordinating {

    private let searchService: any SearchProviding
    private var statuses: [String: IndexingStatus] = [:]
    private var cancelledKeys: Set<String> = []
    private var pendingJobs: [(String, [TextUnit], [Int: Int]?)] = []
    private var isProcessing = false

    init(searchService: any SearchProviding) {
        self.searchService = searchService
    }

    func enqueueIndexing(
        fingerprint: DocumentFingerprint,
        textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async {
        let key = fingerprint.canonicalKey
        cancelledKeys.remove(key)
        statuses[key] = .indexing
        // Dedupe: replace existing pending job for same key
        pendingJobs.removeAll { $0.0 == key }
        pendingJobs.append((key, textUnits, segmentBaseOffsets))

        if !isProcessing {
            isProcessing = true
            Task.detached(priority: .background) { [weak self] in
                await self?.processQueue()
            }
        }
    }

    func cancelIndexing(fingerprint: DocumentFingerprint) async {
        let key = fingerprint.canonicalKey
        cancelledKeys.insert(key)
        pendingJobs.removeAll { $0.0 == key }
        if statuses[key] == .indexing {
            statuses[key] = .notIndexed
        }
    }

    func indexingStatus(fingerprint: DocumentFingerprint) async -> IndexingStatus {
        statuses[fingerprint.canonicalKey] ?? .notIndexed
    }

    // MARK: - Private

    private func processQueue() async {
        while let job = pendingJobs.first {
            pendingJobs.removeFirst()
            let (key, textUnits, offsets) = job

            // Check cancellation before processing
            if cancelledKeys.contains(key) {
                cancelledKeys.remove(key)
                continue
            }

            // Find the fingerprint from the key
            // The key format is "{format}:{sha256}:{byteCount}"
            guard let fingerprint = Self.parseFingerprintKey(key) else {
                statuses[key] = .failed("Invalid fingerprint key")
                continue
            }

            do {
                try await searchService.indexBook(
                    fingerprint: fingerprint,
                    textUnits: textUnits,
                    segmentBaseOffsets: offsets
                )
                // Check cancellation after processing
                if cancelledKeys.contains(key) {
                    cancelledKeys.remove(key)
                    statuses[key] = .notIndexed
                } else {
                    statuses[key] = .indexed
                }
            } catch {
                if !cancelledKeys.contains(key) {
                    statuses[key] = .failed(
                        error is CancellationError
                            ? "Cancelled"
                            : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }
        isProcessing = false
    }

    /// Parses a canonical key back into a DocumentFingerprint.
    /// Key format: "{format}:{sha256}:{byteCount}"
    static func parseFingerprintKey(_ key: String) -> DocumentFingerprint? {
        let parts = key.split(separator: ":", maxSplits: 2)
        guard parts.count == 3,
              let format = BookFormat(rawValue: String(parts[0])),
              let byteCount = Int64(parts[2]) else {
            return nil
        }
        let sha256 = String(parts[1])
        return DocumentFingerprint.validated(
            contentSHA256: sha256,
            fileByteCount: byteCount,
            format: format
        )
    }
}
