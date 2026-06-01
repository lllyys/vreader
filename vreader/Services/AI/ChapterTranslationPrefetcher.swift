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

    func translatedSegments(
        for unit: TranslationUnitID,
        targetLanguage: String,
        granularity: TranslationGranularity
    ) async throws -> [String] {
        // Codex Gate-4 audit finding [2] — for EPUB, the renderer
        // walks DOM block elements (`<p>` / `<li>` / `<blockquote>`)
        // and injects one translation per block. Sentence granularity
        // would produce MORE segments than blocks, so the inject
        // path would map the first sentences as if they were full
        // paragraphs and drop the rest. Force `.paragraph` regardless
        // of the VM's granularity setting — the setup sheet's
        // sentence option becomes meaningful only when a per-format
        // sentence-aware enumerator lands (currently no format has
        // one). Until then, EPUB stays paragraph-aligned so the
        // 1:1 block↔segment contract holds.
        _ = granularity  // explicitly ignored
        let effectiveGranularity: TranslationGranularity = .paragraph
        Self.log.debug("prefetch start: unit \(String(describing: unit), privacy: .public)")

        // Snapshot the active profile FIRST so the cache `lookupKey`
        // and the resolved config below come from the same point in
        // time. If the user changes provider between this snapshot
        // and the by-ID resolve below, the cache row + the resolved
        // config both stay on the original profile — no straddle,
        // no cache-identity poisoning where (config=A, lookupKey=B).
        // Codex Gate-4 audit finding [4].
        guard let activeProfile = await ProviderProfileStore.shared
            .activeProfileSnapshot() else {
            Self.log.error("prefetch: no active provider profile")
            throw ChapterTranslationError.providerFailed("no active provider profile")
        }
        let providerProfileID = activeProfile.id

        // Resolve the config by ID for the profile we just snapshotted.
        // `AIService.resolveProviderConfig(profileID:modelOverride:)`
        // is the by-named-id seam (originally added for the
        // re-translate picker), so passing the active profile's id
        // through it gives us a deterministic config-snapshot tied
        // to the same id we cache under.
        let config: ResolvedAIProviderConfig
        do {
            config = try await aiService.resolveProviderConfig(
                profileID: providerProfileID, modelOverride: nil)
        } catch {
            // `apiKeyMissing` etc. surface as `.providerFailed` from
            // the bilingual VM's perspective — a transient failure
            // the VM treats as "retry later", not as the offline
            // silent-source-fallback (that's `URLError.notConnected`
            // territory, handled below by the service).
            Self.log.error("prefetch resolveProviderConfig failed: \(String(describing: error), privacy: .private)")
            throw ChapterTranslationError.providerFailed("provider config unavailable")
        }

        // Source text for the unit. A missing unit throws
        // `ChapterTextProviderError.unknownUnit` — the VM swallows
        // it as a transient failure.
        let sourceText: String
        do {
            sourceText = try await textProvider.sourceText(for: unit)
        } catch {
            Self.log.error("prefetch sourceText failed for unit \(String(describing: unit), privacy: .public): \(String(describing: error), privacy: .private)")
            throw ChapterTranslationError.providerFailed("chapter text unavailable")
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
                segments: sourceSegments,
                targetLanguage: targetLanguage,
                config: config,
                style: style)
            Self.log.debug("prefetchDirect ok: \(out.count) translated segments")
            return out
        } catch {
            Self.log.error("prefetchDirect translatePreSegmented failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }
}
