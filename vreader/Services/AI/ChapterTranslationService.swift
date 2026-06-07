// Purpose: Translates one chapter unit for feature #56 bilingual reading.
// Pipeline: cache lookup → (on miss) segment → chunk → one AIService request
// per chunk → strict JSON-array decode → per-segment fallback on any decode /
// count / element mismatch → recombine → cache-write.
//
// Key decisions:
// - A SEPARATE actor (not a `PersistenceActor`/`AIService` extension) — it
//   composes the WI-2 store + WI-4 chunker/contract + WI-5 config seam.
// - The AI side is reached through the `TranslationRequestSending` protocol
//   (`AIService` conforms) so tests inject a deterministic mock — the
//   `LibraryPersisting`/`BookImporting` boundary-protocol precedent.
// - On a cache HIT the cached segments are returned with `fromCache == true`
//   and ZERO API calls (acceptance criterion (c)).
// - On any chunk decode failure (`TranslationChunkContract.DecodeError`) the
//   service falls back to one-segment-per-request under the SAME config +
//   style (v4 Gate-2 F5).
// - `Task.checkCancellation()` runs between chunks so a cancelled prefetch /
//   global job stops promptly (edge case (b)).
//
// @coordinates-with: ChapterTranslationStore.swift, ChapterSegmenter.swift,
//   ChapterTranslationChunker.swift, TranslationChunkContract.swift,
//   ResolvedAIProviderConfig.swift, AIService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-6)

import Foundation
import OSLog

/// The AI-request boundary the translation service depends on — `AIService`
/// conforms in production; tests inject a deterministic mock.
protocol TranslationRequestSending: Sendable {
    /// Sends one translation request through a pre-resolved provider config.
    func sendTranslationRequest(
        _ request: AIRequest,
        using config: ResolvedAIProviderConfig
    ) async throws -> AIResponse
}

extension AIService: TranslationRequestSending {
    func sendTranslationRequest(
        _ request: AIRequest,
        using config: ResolvedAIProviderConfig
    ) async throws -> AIResponse {
        try await sendRequest(request, using: config)
    }
}

/// A typed failure from chapter translation.
enum ChapterTranslationError: Error, Equatable {
    /// The device is offline and the unit is not cached.
    case offline
    /// The provider call failed (network / API error).
    case providerFailed(String)
    /// The translation was cancelled.
    case cancelled
}

/// The outcome of translating one unit.
struct ChapterTranslationResult: Sendable, Equatable {
    /// One translated segment per source segment, in order.
    let segments: [String]
    /// `true` when served entirely from the disk cache (no API call).
    let fromCache: Bool
}

/// Granularity of translation segmentation (mirrors `PerBookSettings`'
/// `bilingualGranularity`).
enum TranslationGranularity: String, Sendable {
    case paragraph
    case sentence
}

/// Actor translating one chapter unit, with a provider-aware disk cache.
actor ChapterTranslationService {

    /// The per-chunk character budget. Conservative — well under any
    /// mainstream provider's context window so a chunk + its prompt scaffold
    /// fit comfortably; large chapters are split into several requests.
    static let defaultMaxCharsPerChunk = 6000

    private let sender: any TranslationRequestSending
    private let store: ChapterTranslationStore
    private let promptVersion: String
    private let maxCharsPerChunk: Int
    private let log = Logger(subsystem: "com.vreader.app", category: "ChapterTranslationService")

    init(
        sender: any TranslationRequestSending,
        store: ChapterTranslationStore,
        promptVersion: String,
        maxCharsPerChunk: Int = ChapterTranslationService.defaultMaxCharsPerChunk
    ) {
        self.sender = sender
        self.store = store
        self.promptVersion = promptVersion
        self.maxCharsPerChunk = maxCharsPerChunk
    }

    /// Bug #306: a CACHE-ONLY lookup that needs NO provider config. Returns the
    /// cached translation when a fresh (count-matching) row exists, else nil.
    /// Lets the prefetcher serve an already-translated chapter BEFORE the
    /// provider gate (`resolveProviderConfig`), so a cached chapter still renders
    /// when AI is later disabled / unconfigured / key-less — previously the gate
    /// threw first and the disk cache (inside `translate`) was never reached.
    func cachedTranslation(
        bookFingerprintKey: String,
        unit: TranslationUnitID,
        sourceText: String,
        targetLanguage: String,
        providerProfileID: UUID,
        granularity: TranslationGranularity = .paragraph
    ) async -> ChapterTranslationResult? {
        let lookupKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: bookFingerprintKey,
            unitStorageKey: unit.storageKey,
            targetLanguage: targetLanguage,
            providerProfileID: providerProfileID,
            promptVersion: promptVersion)
        let segments: [String]
        switch granularity {
        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
        }
        guard let cached = await store.translation(forKey: lookupKey),
              cached.sourceParagraphCount == segments.count else { return nil }
        return ChapterTranslationResult(segments: cached.translatedSegments, fromCache: true)
    }

    /// Translates `unit`'s source text into `targetLanguage`. Serves from the
    /// disk cache on a hit; on a miss segments → chunks → requests → decodes →
    /// caches. Throws `ChapterTranslationError` on a provider failure or
    /// cancellation.
    func translate(
        bookFingerprintKey: String,
        unit: TranslationUnitID,
        sourceText: String,
        targetLanguage: String,
        providerProfileID: UUID,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle,
        granularity: TranslationGranularity = .paragraph,
        // Bug #311: optional real progress source. Fired after each chunk
        // completes with `(completedChunks, totalChunks)` so a caller (the
        // re-translate VM) can drive an honest N-of-M progress bar instead of
        // a faked 0.5 pin during the opaque per-chunk network phase. nil by
        // default — the whole-book coordinator + bilingual paths don't use it.
        onChunkProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ChapterTranslationResult {
        let lookupKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: bookFingerprintKey,
            unitStorageKey: unit.storageKey,
            targetLanguage: targetLanguage,
            providerProfileID: providerProfileID,
            promptVersion: promptVersion)

        // Segment the source per the requested granularity FIRST — the
        // segment count is needed to detect a stale cache row.
        let segments: [String]
        switch granularity {
        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
        }

        // Cache lookup. A row is served only when its `sourceParagraphCount`
        // still matches the live chapter — a chapter whose source has since
        // changed (content-replacement rule edit, re-import) produces a
        // mismatch, which is treated as STALE: the row is dropped and the
        // chapter re-translated (plan audit-driven addition).
        if let cached = await store.translation(forKey: lookupKey) {
            if cached.sourceParagraphCount == segments.count {
                return ChapterTranslationResult(
                    segments: cached.translatedSegments, fromCache: true)
            }
            log.info("Stale cache row (count \(cached.sourceParagraphCount) != live \(segments.count)); re-translating")
            // A delete failure does not block re-translation — the later
            // upsert refreshes the same lookupKey regardless. Logged so the
            // swallow is visible (rule 50 §6).
            do {
                try await store.deleteTranslation(forKey: lookupKey)
            } catch {
                log.error("Stale-row delete failed (upsert will still refresh it): \(String(describing: error), privacy: .public)")
            }
        }

        guard !segments.isEmpty else {
            return ChapterTranslationResult(segments: [], fromCache: false)
        }

        // Chunk → translate each chunk → recombine in source order.
        let chunks = ChapterTranslationChunker.chunk(
            segments: segments, maxCharsPerChunk: maxCharsPerChunk)
        var translated = [String](repeating: "", count: segments.count)

        // Bug #330: a single chunk's provider failure must NOT abort the whole
        // chapter — leave that chunk's segments source-only (empty translation)
        // and continue. But if EVERY chunk fails (a genuine outage, not just one
        // over-budget chunk), surface the error rather than silently returning an
        // all-source-only result.
        var completedChunks = 0
        var anyChunkSucceeded = false
        var lastChunkError: Error?
        for chunk in chunks {
            do {
                try Task.checkCancellation()
            } catch {
                throw ChapterTranslationError.cancelled
            }
            let chunkSegments = chunk.map { segments[$0] }
            do {
                let chunkResult = try await translateChunk(
                    chunkSegments, targetLanguage: targetLanguage, config: config, style: style)
                for (offset, segmentIndex) in chunk.enumerated() {
                    translated[segmentIndex] = chunkResult[offset]
                }
                anyChunkSucceeded = true
            } catch is CancellationError {
                // The between-chunk / per-piece Task.checkCancellation() throws a
                // raw CancellationError — surface it as the typed .cancelled.
                throw ChapterTranslationError.cancelled
            } catch ChapterTranslationError.cancelled {
                // Bug #330 (Codex): `send()` maps a provider-side cancellation to
                // the TYPED `.cancelled`. It must NOT be degraded-and-continued —
                // a cancel aborts the whole translation. Rethrow before the
                // generic degradation catch below.
                throw ChapterTranslationError.cancelled
            } catch {
                // Bug #330: degrade this chunk to source-only and keep going.
                log.error("Chunk failed (segments \(chunk) left source-only): \(String(describing: error), privacy: .public)")
                lastChunkError = error
            }
            // Bug #311: real N-of-M progress — fire AFTER the chunk resolves
            // (success or graceful-degrade) so the count reflects committed work.
            completedChunks += 1
            onChunkProgress?(completedChunks, chunks.count)
        }
        if !anyChunkSucceeded, let err = lastChunkError {
            throw err
        }

        // Cache-write the recombined ordered translation. A store-write
        // failure does not fail the translation — the caller still gets the
        // freshly translated text; it just won't be cached this time. The
        // swallow is logged so the failure is visible (rule 50 §6).
        //
        // Bug #330: do NOT cache a PARTIALLY-degraded result. If a chunk failed
        // (its segments are source-only ""), caching would make the gap permanent
        // — a later read would hit the cache and never retry the failed chunk.
        // Skip the write so a re-read re-attempts the failed segments; the caller
        // still gets this run's partial result.
        if lastChunkError == nil {
            do {
                try await store.upsert(ChapterTranslationRecord(
                    bookFingerprintKey: bookFingerprintKey,
                    unitStorageKey: unit.storageKey,
                    targetLanguage: targetLanguage,
                    providerProfileID: providerProfileID,
                    promptVersion: promptVersion,
                    translatedSegments: translated,
                    sourceParagraphCount: segments.count))
            } catch {
                log.error("Cache-write failed (translation still returned): \(String(describing: error), privacy: .public)")
            }
        }

        return ChapterTranslationResult(segments: translated, fromCache: false)
    }

    /// Bug #268: translates a PRE-SEGMENTED list of source segments directly,
    /// bypassing `ChapterSegmenter` AND the disk cache. Used by the bilingual
    /// EPUB divergence-fallback: when the DOM leaf-enumerate's block count
    /// diverges from the plain-text paragraph segmentation (nested `<pre>` /
    /// mixed-content `<blockquote>`), translating the enumerate's OWN block
    /// `text[]` makes blocks↔segments 1:1 BY CONSTRUCTION — eliminating the
    /// whole-chapter source-only fallback. The returned array is always the same
    /// length as `segments`. No disk cache: the fallback is rare, and the
    /// plain-text path's cache row is keyed by a different segment count that
    /// must not be thrashed.
    func translatePreSegmented(
        segments: [String],
        targetLanguage: String,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle
    ) async throws -> [String] {
        guard !segments.isEmpty else { return [] }
        let chunks = ChapterTranslationChunker.chunk(
            segments: segments, maxCharsPerChunk: maxCharsPerChunk)
        var translated = [String](repeating: "", count: segments.count)
        // Bug #330: same graceful degradation as `translate` — a single chunk's
        // failure leaves its segments source-only; an all-chunks failure surfaces
        // the error.
        var anyChunkSucceeded = false
        var lastChunkError: Error?
        for chunk in chunks {
            do {
                try Task.checkCancellation()
            } catch {
                throw ChapterTranslationError.cancelled
            }
            let chunkSegments = chunk.map { segments[$0] }
            do {
                let chunkResult = try await translateChunk(
                    chunkSegments, targetLanguage: targetLanguage, config: config, style: style)
                for (offset, segmentIndex) in chunk.enumerated() {
                    translated[segmentIndex] = chunkResult[offset]
                }
                anyChunkSucceeded = true
            } catch is CancellationError {
                throw ChapterTranslationError.cancelled
            } catch ChapterTranslationError.cancelled {
                // Bug #330 (Codex): typed cancellation from `send()` must abort,
                // not degrade.
                throw ChapterTranslationError.cancelled
            } catch {
                log.error("Pre-segmented chunk failed (segments \(chunk) source-only): \(String(describing: error), privacy: .public)")
                lastChunkError = error
            }
        }
        if !anyChunkSucceeded, let err = lastChunkError {
            throw err
        }
        return translated
    }

    // MARK: - Private

    /// Translates one chunk: a single whole-chunk request with a strict
    /// JSON-array decode; on any decode / count / element mismatch, falls back
    /// to one request per segment (still under the same config + style).
    private func translateChunk(
        _ chunkSegments: [String],
        targetLanguage: String,
        config: ResolvedAIProviderConfig,
        style: TranslationStyle
    ) async throws -> [String] {
        // Bug #330: an oversized SINGLE segment (the chunker gives it its own
        // chunk but does NOT sub-split it) is sub-split into ≤budget pieces,
        // translated piece by piece, and rejoined into the one segment's
        // translation — sending the whole oversized paragraph would overflow the
        // provider's context window → error.
        if chunkSegments.count == 1 {
            let pieces = ChapterTranslationChunker.subSplit(
                chunkSegments[0], maxChars: maxCharsPerChunk)
            if pieces.count > 1 {
                var joined = ""
                for piece in pieces {
                    try Task.checkCancellation()
                    let piecePrompt = TranslationChunkContract.userPrompt(
                        segments: [piece], targetLanguage: targetLanguage, style: style)
                    let pieceResponse = try await send(prompt: piecePrompt, config: config)
                    if let decoded = try? TranslationChunkContract.decode(
                        pieceResponse.content, expectedCount: 1) {
                        joined += decoded[0]
                    } else {
                        joined += pieceResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return [joined]
            }
        }

        // First attempt — the whole chunk in one request.
        let prompt = TranslationChunkContract.userPrompt(
            segments: chunkSegments, targetLanguage: targetLanguage, style: style)
        let response = try await send(prompt: prompt, config: config)
        if let decoded = try? TranslationChunkContract.decode(
            response.content, expectedCount: chunkSegments.count) {
            return decoded
        }

        // Decode failed → per-segment fallback.
        log.warning("Chunk decode failed; falling back to per-segment requests")
        var perSegment: [String] = []
        perSegment.reserveCapacity(chunkSegments.count)
        for segment in chunkSegments {
            try Task.checkCancellation()
            let onePrompt = TranslationChunkContract.userPrompt(
                segments: [segment], targetLanguage: targetLanguage, style: style)
            let oneResponse = try await send(prompt: onePrompt, config: config)
            if let oneDecoded = try? TranslationChunkContract.decode(
                oneResponse.content, expectedCount: 1) {
                perSegment.append(oneDecoded[0])
            } else {
                // Even the per-segment decode failed — keep order intact with
                // the raw model text rather than dropping the segment.
                perSegment.append(oneResponse.content.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return perSegment
    }

    /// Issues one translation request, mapping a transport failure to a typed
    /// `ChapterTranslationError`.
    private func send(
        prompt: String,
        config: ResolvedAIProviderConfig
    ) async throws -> AIResponse {
        let request = AIRequest(
            actionType: .translate,
            bookFingerprint: nil,
            locator: nil,
            contextText: "",
            userPrompt: prompt,
            targetLanguage: nil,
            promptVersion: promptVersion)
        do {
            return try await sender.sendTranslationRequest(request, using: config)
        } catch is CancellationError {
            throw ChapterTranslationError.cancelled
        } catch let error as ChapterTranslationError {
            throw error
        } catch {
            // Bug #320: keep the RAW detail (enum-case syntax + provider JSON) in
            // the log only; the thrown `.providerFailed` carries a sanitized,
            // user-facing message (`sanitizedProviderMessage`).
            log.error("Chapter translation failed: \(String(describing: error), privacy: .public)")
            throw Self.mapTransportError(error)
        }
    }

    /// Maps a raw transport error to a typed `ChapterTranslationError`,
    /// distinguishing a genuine offline failure (so the caller can render
    /// source-only per edge case (c)) from a generic provider failure.
    ///
    /// Only a `URLError` carrying an unambiguous connectivity code is treated
    /// as `.offline`. `AIError.networkError` is deliberately NOT mapped to
    /// `.offline` — it is a catch-all also thrown for invalid responses and
    /// misconfigured base URLs, so mapping it to `.offline` would mis-drive
    /// the source-only fallback on a provider/config fault (Gate-4 round-2).
    private static func mapTransportError(_ error: Error) -> ChapterTranslationError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .dataNotAllowed, .cannotConnectToHost, .timedOut:
                return .offline
            default:
                return .providerFailed(sanitizedProviderMessage(error))
            }
        }
        return .providerFailed(sanitizedProviderMessage(error))
    }

    /// Bug #320: the user-facing message for a non-offline translation failure.
    /// NEVER `String(describing: error)` — that stringifies an `AIError` to its
    /// enum-case syntax + raw provider JSON (e.g. `providerError("HTTP 400: {…}")`),
    /// which leaks internals and reads as a crash. Mirrors the sanitized path the
    /// Chat/Summarize/Translate tabs use: a known `AIError` → its `errorDescription`,
    /// anything else → `localizedDescription`. The raw detail is kept in the log
    /// only (logged at the catch site).
    static func sanitizedProviderMessage(_ error: Error) -> String {
        if let aiError = error as? AIError, let description = aiError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
