// Purpose: Feature #56 WI-10 — concrete production adapter
// bridging the bilingual view model's `ChapterPrefetching` seam to
// `ChapterTranslationService` + the active `AIService` provider.
//
// The bilingual VM holds an `any ChapterPrefetching` and asks it
// to translate one unit. This adapter resolves the active provider
// config once per request (so a profile change mid-prefetch does
// not flap), pulls the unit's source text via the injected
// `ChapterTextProviding`, then asks `ChapterTranslationService` for
// the ordered translated segments.
//
// Key decisions:
// - **A `Sendable` `struct`.** Captures `Sendable` references only
//   (the actors and the provider profile id), so the VM can hold it
//   across actor hops without an extra layer.
// - **Per-request config resolution.** Each `translatedSegments(...)`
//   call resolves the active provider config fresh from `AIService`,
//   so a user who switches profile after starting a chapter still
//   gets a coherent prefetch with the picker's config — the VM's
//   epoch guard discards a stale result anyway.
// - **Source text is fetched on demand.** The chapter text provider
//   is the seam — for EPUB it's `EPUBChapterTextProvider`, which
//   reads + strips HTML. The prefetcher caches nothing on its own;
//   the disk cache is `ChapterTranslationStore`'s job.
//
// @coordinates-with: ChapterPrefetching.swift,
//   ChapterTranslationService.swift, AIService.swift,
//   ChapterTextProviding.swift,
//   BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Foundation
import OSLog

/// Production adapter routing the bilingual VM's prefetch trigger
/// through `ChapterTranslationService` + the active `AIService`
/// provider. One per open book.
struct ChapterTranslationPrefetcher: ChapterPrefetching, Sendable {

    /// Observability for the prefetch path. The bilingual VM swallows a
    /// prefetch failure as "retry later" (so the reader doesn't break), which
    /// previously made a misconfigured provider / consent gate / failing AI
    /// call invisible — the UI activated but no translation ever rendered, with
    /// no signal. These error logs surface the underlying cause.
    private static let log = Logger(subsystem: "com.vreader.app", category: "BilingualPrefetch")

    /// The book this adapter prefetches for. Matches the VM's
    /// `bookFingerprintKey` so the cache lookup key is built
    /// consistently.
    let bookFingerprintKey: String

    /// Resolves source text per unit. EPUB supplies
    /// `EPUBChapterTextProvider` (struct), other formats supply
    /// their own concrete adapter (WI-11..13).
    let textProvider: any ChapterTextProviding

    /// The translation service — wraps the per-chunk request loop
    /// and the on-disk cache. Actor-isolated so concurrent prefetch
    /// tasks for different units serialize through it.
    let translationService: ChapterTranslationService

    /// The active AI service — `resolveActiveProviderConfig()` is
    /// called per request to snapshot the credential + provider,
    /// then `ChapterTranslationService` uses the resulting config
    /// directly without re-resolving between chunks.
    let aiService: AIService

    /// Translation style — `.natural` for the always-on chapter
    /// bilingual mode. Scope item (4)'s re-translate picker is the
    /// only path that overrides this; it goes through a different
    /// path (`ChapterReTranslateViewModel`, WI-15).
    let style: TranslationStyle

    /// Bug #343: when true, the cache-first read also serves a fresh row
    /// whose stored count differs from the live segmenter count — the row may
    /// carry the DOM-enumerate contract written by the divergence fallback,
    /// which pairs 1:1 at inject time. ONLY hosts with the inject-time
    /// divergence fallback (legacy EPUB + Readium) opt in; formats without a
    /// self-heal (TXT/MD/PDF/Foliate) keep the strict staleness guard.
    var acceptsCountMismatchedRows: Bool = false

    /// Bug #344: when true, a `.sentence` granularity request is honored —
    /// the format's renderer can hold the 1:1 inject contract at sentence
    /// level (TXT/MD: both sides segment through `ChapterSegmenter`, so the
    /// counts agree by construction). Default false: formats whose render
    /// side enumerates DOM blocks (legacy EPUB, Readium, Foliate) force
    /// `.paragraph` — sentence segments would outnumber blocks and the
    /// inject would mispair. Those formats render the setup sheet's
    /// Sentence segment in the DESIGNED dimmed state instead of silently
    /// ignoring the pick (design #1646, S-C fallback).
    var supportsSentenceGranularity: Bool = false

    /// Bug #344: the granularity actually sent to the service — `.sentence`
    /// only when BOTH requested and supported; everything else degrades to
    /// `.paragraph` (the DOM-enumerate formats' safe default).
    static func effectiveGranularity(
        requested: TranslationGranularity,
        supportsSentenceGranularity: Bool
    ) -> TranslationGranularity {
        (supportsSentenceGranularity && requested == .sentence) ? .sentence : .paragraph
    }

    func translatedSegments(
        for unit: TranslationUnitID,
        targetLanguage: String,
        granularity: TranslationGranularity
    ) async throws -> [String] {
        // Codex Gate-4 audit finding [2] — for EPUB, the renderer
        // walks DOM block elements (`<p>` / `<li>` / `<blockquote>`)
        // and injects one translation per block. Sentence granularity
        // would produce MORE segments than blocks, so the inject path
        // would mispair. Bug #344: formats whose render side segments
        // through `ChapterSegmenter` (TXT/MD) hold the 1:1 contract at
        // sentence level by construction and opt in via
        // `supportsSentenceGranularity`; DOM-enumerating formats keep
        // forcing `.paragraph` and dim the control instead (#1646 S-C).
        let effectiveGranularity = Self.effectiveGranularity(
            requested: granularity,
            supportsSentenceGranularity: supportsSentenceGranularity)
        Self.log.debug("prefetch start: unit \(String(describing: unit), privacy: .public)")

        // Source text for the unit (needed for the cache count check + the
        // translate). A missing unit throws `ChapterTextProviderError.unknownUnit`
        // — the VM swallows it as a transient failure. Fetched BEFORE the provider
        // gate so the cache check below can run without a config.
        let sourceText: String
        do {
            sourceText = try await textProvider.sourceText(for: unit)
        } catch {
            Self.log.error("prefetch sourceText failed for unit \(String(describing: unit), privacy: .public): \(String(describing: error), privacy: .private)")
            throw ChapterTranslationError.providerFailed("chapter text unavailable")
        }

        // Bug #306: consult the disk cache BEFORE the provider gate. An
        // already-translated chapter must render even when AI is later disabled /
        // unconfigured / key-less — previously `resolveProviderConfig` threw first
        // and the cache (inside `translate`) was never reached. Bug #342: the
        // canonical key is profile-agnostic, so this now runs even before the
        // active-profile guard — a cached chapter renders with NO profile at all
        // (and regardless of which profile produced it).
        if let cached = await translationService.cachedTranslation(
            bookFingerprintKey: bookFingerprintKey,
            unit: unit,
            sourceText: sourceText,
            targetLanguage: targetLanguage,
            granularity: effectiveGranularity,
            acceptCountMismatch: acceptsCountMismatchedRows
        ) {
            Self.log.debug("prefetch cache HIT (pre-gate) for unit \(String(describing: unit), privacy: .public)")
            return cached.segments
        }

        // Cache miss → snapshot the active profile, then resolve its config by
        // ID, so the row provenance and the resolved config come from the same
        // point in time (Codex Gate-4 audit finding [4] — no straddle where
        // config=A but row metadata=B if the user switches mid-flight).
        guard let activeProfile = await ProviderProfileStore.shared
            .activeProfileSnapshot() else {
            Self.log.error("prefetch: no active provider profile")
            throw ChapterTranslationError.providerFailed("no active provider profile")
        }
        let providerProfileID = activeProfile.id
        let config: ResolvedAIProviderConfig
        do {
            config = try await aiService.resolveProviderConfig(
                profileID: providerProfileID, modelOverride: nil)
        } catch {
            // `apiKeyMissing` etc. surface as `.providerFailed` from the
            // bilingual VM's perspective — a transient failure the VM treats as
            // "retry later", not the offline silent-source-fallback.
            Self.log.error("prefetch resolveProviderConfig failed: \(String(describing: error), privacy: .private)")
            throw ChapterTranslationError.providerFailed("provider config unavailable")
        }

        do {
            let result = try await translationService.translate(
                bookFingerprintKey: bookFingerprintKey,
                unit: unit,
                sourceText: sourceText,
                targetLanguage: targetLanguage,
                providerProfileID: providerProfileID,
                config: config,
                style: style,
                granularity: effectiveGranularity
            )
            return result.segments
        } catch {
            Self.log.error("prefetch translate call failed for unit \(String(describing: unit), privacy: .public): \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    /// Bug #268: translate the render's OWN enumerated block texts directly
    /// (1:1 by construction), bypassing the unit's plain-text segmentation.
    /// Same provider snapshot + resolve + error contract as `translatedSegments`,
    /// then `ChapterTranslationService.translatePreSegmented` (no disk cache).
    func translatedSegmentsDirect(
        for unit: TranslationUnitID,
        sourceSegments: [String],
        targetLanguage: String
    ) async throws -> [String] {
        guard !sourceSegments.isEmpty else { return [] }
        Self.log.debug("prefetchDirect start: unit \(String(describing: unit), privacy: .public), \(sourceSegments.count) segments")
        // Snapshot the active profile + resolve its config (mirrors
        // `translatedSegments` so a provider switch can't straddle).
        guard let activeProfile = await ProviderProfileStore.shared
            .activeProfileSnapshot() else {
            Self.log.error("prefetchDirect: no active provider profile")
            throw ChapterTranslationError.providerFailed("no active provider profile")
        }
        let config: ResolvedAIProviderConfig
        do {
            config = try await aiService.resolveProviderConfig(
                profileID: activeProfile.id, modelOverride: nil)
        } catch {
            Self.log.error("prefetchDirect resolveProviderConfig failed: \(String(describing: error), privacy: .private)")
            throw ChapterTranslationError.providerFailed("provider config unavailable")
        }
        do {
            let out = try await translationService.translatePreSegmented(
                bookFingerprintKey: bookFingerprintKey,
                unit: unit,
                segments: sourceSegments,
                targetLanguage: targetLanguage,
                providerProfileID: activeProfile.id,
                config: config,
                style: style)
            Self.log.debug("prefetchDirect ok: \(out.count) translated segments")
            return out
        } catch {
            Self.log.error("prefetchDirect translatePreSegmented failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    /// Bug #343: cache-only restore for the divergence fallback — serves the
    /// canonical row when its stored contract matches the enumerate's own
    /// block count. Needs no provider config (the #306 pre-gate precedent).
    func cachedSegmentsDirect(
        for unit: TranslationUnitID,
        expectedCount: Int,
        targetLanguage: String
    ) async -> [String]? {
        await translationService.cachedTranslation(
            bookFingerprintKey: bookFingerprintKey,
            unit: unit,
            expectedSegmentCount: expectedCount,
            targetLanguage: targetLanguage)?.segments
    }
}
