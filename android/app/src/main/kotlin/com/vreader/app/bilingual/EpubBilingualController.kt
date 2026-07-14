// Purpose: feature #131 WI-7b — THE single owner of an EPUB book's bilingual DOM state
// (plan §"EPUB direct-block flow", Medium-1). Serializes the enumerate → cache-restore |
// translate → guarded-commit → inject sequence against the live Readium navigator using a
// Mutex + a monotonic session token, so a late/stale apply can never duplicate nodes or
// clobber a newer session. The controller is the SOLE writer of an EPUB unit's canonical
// cache row (via the prefetcher's direct-block path) AND its VM render-state entry (via the
// injected onEpubBlocksEnumerated callback) — the VM's position-driven regular `prefetch`
// dispatches only TXT/MD units, so the two paths never write the same row (Medium-1).
//
// Race contract (spike-proven): the session token S is captured before the enumerate JS and
// RE-CHECKED after EVERY suspended step (enumerate, cachedDirect, prefetchDirect). A stale
// token discards silently — no commit, no inject, and NEVER an `errorUnit` (a superseded
// apply is not a failure). `bumpSession()` is called on navigator-recreate / language-change
// / bilingual-off; `clear()` runs (under the mutex, after a bump) BEFORE publication teardown.
//
// ALL `evaluateJavascript` runs on the main thread — the caller wraps the navigator eval so
// R2BasicWebView.checkThread does not throw off-main (spike binding constraint).
//
// @coordinates-with: EpubBilingualJs.kt, EpubChapterTextProvider.kt,
//   ChapterTranslationPrefetcher.kt, BilingualViewModel.kt (onEpubBlocksEnumerated),
//   reader/ReaderActivity.kt (the wiring),
//   iOS vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-7b, Medium-1)
package com.vreader.app.bilingual

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The runtime single owner of one open EPUB book's bilingual DOM decorations.
 *
 * @param evaluateJavascript runs a JS string against the live navigator and returns its raw
 *   result (the caller dispatches this on the main thread — [org.readium] `R2BasicWebView`
 *   throws off-main). A null result is tolerated at every call site.
 * @param prefetcher the WI-4a cache-first translator (its direct-block `cachedDirect` /
 *   `prefetchDirect` paths — the controller owns the EPUB unit's canonical cache row).
 * @param onEpubBlocksEnumerated publishes the committed translation for a unit into VM render
 *   state (the single writer of an EPUB unit's `translationsByUnit` entry). Called only after
 *   a non-stale commit; the visible render is the injected DOM, this keeps the VM state honest.
 * @param css the interlinear CSS injected once via [EpubBilingualJs.styleScript].
 * @param targetIsCjk reports whether the CURRENT target language is CJK (read fresh per apply so
 *   a language change is reflected — drives the heading tracking modifier class).
 */
class EpubBilingualController(
    private val evaluateJavascript: suspend (String) -> String?,
    private val prefetcher: ChapterTranslationPrefetcher,
    private val onEpubBlocksEnumerated: (TranslationUnitId, List<String>) -> Unit,
    private val css: String = DEFAULT_BILINGUAL_CSS,
    private val targetIsCjk: () -> Boolean = { false },
) {

    /** Serializes every enumerate→commit→inject / clear sequence against the navigator, so
     *  two applies (e.g. a scroll re-apply racing an activity-recreate re-apply) never
     *  interleave JS against the DOM. */
    private val mutex = Mutex()

    /** The monotonic session token. Captured before an apply's enumerate and re-checked after
     *  every suspension; a change (navigator-recreate / language change / disable) makes the
     *  in-flight apply discard silently. `@Volatile` — read across the suspending steps. */
    @Volatile
    private var session: Long = 0L

    /** The style injection is idempotent per session, but we only need to (re)inject it once
     *  per token — a scroll re-apply skips it. Reset on [bumpSession]. */
    @Volatile
    private var styleInjectedForSession: Long = -1L

    /** The current session token (test seam + the re-apply guard). */
    val currentSession: Long get() = session

    /**
     * Invalidate the current session: a later apply for the OLD token no-ops at its next
     * token re-check. Called on navigator-recreate, language change, and bilingual-off.
     * Cheap + non-suspending so it can run from a lifecycle callback.
     */
    fun bumpSession() {
        session += 1
        styleInjectedForSession = -1L
    }

    /**
     * Apply bilingual decorations for the current resource [unit]. Under the mutex + the
     * captured session token, the single-owner sequence:
     *   1. inject the style once for this token,
     *   2. enumerate the current resource's leaf blocks,
     *   3. re-check the token,
     *   4. `cachedDirect(unit, expectedCount = blocks.size)` — a ZERO-PROVIDER restore,
     *   5. on a miss, `prefetchDirect(unit, blocks.texts)` (the count-divergence direct path),
     *   6. re-check the token — stale → discard (no commit, no inject, NO errorUnit),
     *   7. publish the committed translation into VM render state (single writer),
     *   8. inject the id→translation decorations.
     * Empty enumeration → source-only (no crash, no inject). Every step tolerates a null JS
     * result. A cooperative [CancellationException] propagates.
     */
    suspend fun apply(unit: TranslationUnitId, targetLanguage: String) {
        val token = session
        mutex.withLock {
            if (session != token) return
            ensureStyle(token)
            val enumRaw = evaluateJavascript(EpubBilingualJs.enumScript)
            if (session != token) return
            val blocks = EpubBilingualJs.parseEnumResult(enumRaw)
            if (blocks.isEmpty()) return   // source-only: nothing translatable on this resource

            val texts = blocks.map { it.text }
            val segments = translate(unit, targetLanguage, texts) ?: return
            if (session != token) return   // superseded after translate — discard silently

            // Commit into VM render state (single writer), then inject the DOM.
            onEpubBlocksEnumerated(unit, segments)
            val idToSegment = pair(blocks, segments)
            if (idToSegment.isEmpty()) return
            val injectRaw = evaluateJavascript(EpubBilingualJs.injectScript(idToSegment, targetIsCjk()))
            // The inject count is advisory (a probe uses decorationCountScript); no assertion here.
            @Suppress("UNUSED_EXPRESSION") injectRaw
        }
    }

    /**
     * Probe-gated re-apply for the reader's `currentLocator` re-apply signal (scroll round-trip,
     * href change, `submitPreferences` reflow, activity recreate). Runs the cheap decoration-count
     * probe first and re-injects [unit] ONLY when the resource DOM is missing decorations (a
     * scroll-mode DOM often survives a round-trip / a reflow, so an unconditional re-inject is
     * wasteful — spike finding c-i/c-ii). [expectedCount] is the block count of the last apply for
     * this unit (0/unknown → always re-apply). No-op while the token is stale.
     */
    suspend fun reapplyIfNeeded(unit: TranslationUnitId, targetLanguage: String, expectedCount: Int) {
        val token = session
        val probeRaw = mutex.withLock {
            if (session != token) return
            evaluateJavascript(EpubBilingualJs.decorationCountScript)
        }
        if (session != token) return
        val current = EpubBilingualJs.parseCountResult(probeRaw, default = 0)
        // Re-apply when the DOM has FEWER decorations than expected (a recreate/href-change lost
        // them). An unknown expected (<=0) always re-applies; a satisfied DOM is skipped.
        if (expectedCount > 0 && current >= expectedCount) return
        apply(unit, targetLanguage)
    }

    /** Remove every decoration node (under the mutex). Called BEFORE publication teardown and on
     *  disable. Idempotent — a repeat clear on a clean DOM is a no-op. */
    suspend fun clear() {
        mutex.withLock {
            evaluateJavascript(EpubBilingualJs.clearScript)
        }
    }

    // ── internals ──────────────────────────────────────────────

    /** Cache-first translate for [unit]: a zero-provider `cachedDirect` restore keyed on the
     *  enumerate's block count, falling back to the direct-block `prefetchDirect`. Returns the
     *  translated segments (length == [texts].size on the direct path), or null on a translate
     *  failure (source-only — never a crash, never an errorUnit here). A [CancellationException]
     *  propagates (cooperative cancellation is not a failure). */
    private suspend fun translate(
        unit: TranslationUnitId,
        targetLanguage: String,
        texts: List<String>,
    ): List<String>? {
        val restore = try {
            prefetcher.cachedDirect(unit, expectedCount = texts.size, targetLanguage = targetLanguage)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        }
        restore?.segments?.let { return it }
        return try {
            prefetcher.prefetchDirect(unit, sourceSegments = texts, targetLanguage = targetLanguage)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        }
    }

    /** Inject the single interlinear `<style>` once per session token (a scroll re-apply for the
     *  same token skips it). */
    private suspend fun ensureStyle(token: Long) {
        if (styleInjectedForSession == token) return
        evaluateJavascript(EpubBilingualJs.styleScript(css))
        styleInjectedForSession = token
    }

    /** Pair the enumerated block ids with the translated segments 1:1 (the direct-block contract).
     *  A shorter/longer segment list pairs only the overlap (defensive; the direct path returns a
     *  1:1 list). A blank translation is skipped (source-only for that block — iOS Decision 2). */
    private fun pair(blocks: List<EpubBilingualJs.Block>, segments: List<String>): Map<String, String> {
        val n = minOf(blocks.size, segments.size)
        val out = LinkedHashMap<String, String>(n)
        for (i in 0 until n) {
            val seg = segments[i]
            if (seg.isNotBlank()) out[blocks[i].id] = seg
        }
        return out
    }

    companion object {
        /**
         * The default interlinear CSS (parity with the iOS bilingual theme intent): a muted,
         * non-selectable translation row under each source block, a left border for paragraph
         * rows, and a centered echo treatment for heading rows. Injected ONCE per session via
         * [EpubBilingualJs.styleScript] (Bug #304 — the Readium spine does not thread
         * epubOverrideCSS, so the decorations otherwise render as plain body text).
         */
        const val DEFAULT_BILINGUAL_CSS =
            ".vreader-bilingual{display:block;margin:0.35em 0 0.6em;padding-left:0.8em;" +
                "border-left:3px solid rgba(127,127,127,0.4);color:rgba(127,127,127,0.95);" +
                "font-size:0.92em;line-height:1.5;user-select:none;-webkit-user-select:none;}" +
                ".vreader-bilingual--heading{border-left:none;padding-left:0;text-align:center;" +
                "font-weight:600;}" +
                ".vreader-bilingual--cjk{letter-spacing:0.05em;}"
    }
}
