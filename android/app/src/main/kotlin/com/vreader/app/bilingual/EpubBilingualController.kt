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
// RE-CHECKED after EVERY suspended step (style-inject, enumerate, cachedDirect, prefetchDirect,
// commit). A stale token discards silently — no commit, no inject, and NEVER an `errorUnit` (a
// superseded apply is not a failure). `bumpSession()` is called on navigator-recreate /
// language-change / bilingual-off; `shutdown()` (a bump + a mutex-held clear) runs BEFORE
// publication teardown so no late apply reaches a torn-down navigator. `reconcileLanguageChange`
// (WI-9) is the mid-book language-switch entry: a bump + a full re-enumerate/re-inject of the
// CURRENT resource so a language change on a STATIONARY EPUB reconciles the visible DOM (not just
// future resources) — the enumerate's all-block-ids reconcile set reaps stale-language decorations.
//
// ALL `evaluateJavascript` runs on the main thread — the caller wraps the navigator eval in
// `withContext(Dispatchers.Main.immediate)` so R2BasicWebView.checkThread does not throw
// off-main (spike binding constraint), and a cooperative CancellationException propagates.
//
// The controller tracks the last-applied NONBLANK decoration count per unit ([expectedCountFor])
// so the host's probe-gated re-apply compares against the count actually injected (not the VM's
// translationsByUnit, which the render doesn't drive) — a blank translation is source-only for
// that block and is excluded from the expected count.
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
 *   result. The caller MUST dispatch this on the main thread ([org.readium] `R2BasicWebView`
 *   throws off-main) and rethrow cancellation. A null result is tolerated at every call site.
 * @param prefetcher the WI-4a cache-first translator (its direct-block `cachedDirect` /
 *   `prefetchDirect` paths — the controller owns the EPUB unit's canonical cache row).
 * @param onEpubBlocksEnumerated publishes the committed translation for a unit into VM render
 *   state (the single writer of an EPUB unit's `translationsByUnit` entry). Called only after
 *   a non-stale commit; the visible render is the injected DOM, this keeps the VM state honest.
 * @param css the interlinear CSS injected via [EpubBilingualJs.styleScript] on every reinject.
 * @param targetIsCjk reports whether the CURRENT target language is CJK (read fresh per apply so
 *   a language change is reflected — drives the heading tracking modifier class).
 * @param targetIsRtl reports whether the CURRENT target language is RTL (Arabic) — read fresh per
 *   apply so the injected translation nodes get `dir="rtl"` (LTR EPUBs otherwise render RTL text
 *   incorrectly). Default false → `dir="auto"`.
 */
class EpubBilingualController(
    private val evaluateJavascript: suspend (String) -> String?,
    private val prefetcher: ChapterTranslationPrefetcher,
    private val onEpubBlocksEnumerated: (TranslationUnitId, List<String>) -> Unit,
    private val css: String = DEFAULT_BILINGUAL_CSS,
    private val targetIsCjk: () -> Boolean = { false },
    private val targetIsRtl: () -> Boolean = { false },
) {

    /** Serializes every enumerate→commit→inject / clear sequence against the navigator, so
     *  two applies (e.g. a scroll re-apply racing an activity-recreate re-apply) never
     *  interleave JS against the DOM. */
    private val mutex = Mutex()

    /** The monotonic session token. Captured before an apply and re-checked after every
     *  suspension; a change (navigator-recreate / language change / disable) makes the in-flight
     *  apply discard silently. `@Volatile` — read across the suspending steps + from a bump. */
    @Volatile
    private var session: Long = 0L

    /** The last-applied NONBLANK decoration count per unit — the host's probe-gated re-apply
     *  compares the live DOM count against this. Written only under the mutex after an inject. */
    private val appliedCount = HashMap<TranslationUnitId, Int>()

    /** The current session token (test seam + the re-apply guard). */
    val currentSession: Long get() = session

    /** The last-applied nonblank decoration count for [unit] (0 = never applied / cleared). */
    fun expectedCountFor(unit: TranslationUnitId): Int = appliedCount[unit] ?: 0

    /**
     * Invalidate the current session: a later apply for the OLD token no-ops at its next
     * token re-check. Called on navigator-recreate, language change, and bilingual-off.
     * Cheap + non-suspending so it can run from a lifecycle callback. Drops the applied-count
     * anchors — a bumped session's DOM is stale (the caller [clear]s/re-[apply]s), so a fresh
     * apply must re-inject rather than let a probe accept the old (now wrong-language) count.
     */
    fun bumpSession() {
        session += 1
        appliedCount.clear()
    }

    /**
     * Apply bilingual decorations for the current resource [unit]. Under the mutex + the
     * captured session token, the single-owner sequence — every suspended step re-checks the
     * captured token, so a stale token discards silently (no commit, no inject, NO errorUnit):
     *   1. inject the style (idempotent — always ensured on a reinject so a reflow that dropped
     *      the `<style>` is restored),
     *   2. enumerate the current resource's leaf blocks (re-check token),
     *   3. `cachedDirect(unit, expectedCount = blocks.size)` — a ZERO-PROVIDER restore (re-check),
     *   4. on a miss, `prefetchDirect(unit, blocks.texts)` (the direct path; re-check),
     *   5. publish the committed translation into VM render state (single writer),
     *   6. inject the id→translation decorations, record the nonblank count.
     * Empty enumeration → source-only (no crash, no inject). A cooperative [CancellationException]
     * propagates.
     */
    suspend fun apply(unit: TranslationUnitId, targetLanguage: String) {
        val token = session
        mutex.withLock { applyLocked(unit, targetLanguage, token) }
    }

    /**
     * Probe-gated re-apply for the reader's `currentLocator` re-apply signal (scroll round-trip,
     * href change, `submitPreferences` reflow, activity recreate). Runs the cheap decoration-count
     * probe first and re-injects [unit] ONLY when the resource DOM is missing decorations (a
     * scroll-mode DOM often survives a round-trip / a reflow, so an unconditional re-inject is
     * wasteful — spike finding c-i/c-ii). [expectedCount] is the block count of the last apply for
     * this unit (0/unknown → always re-apply). The probe's captured token is preserved through the
     * re-inject so a session change between the probe and the inject discards. No-op while stale.
     */
    suspend fun reapplyIfNeeded(unit: TranslationUnitId, targetLanguage: String, expectedCount: Int) {
        val token = session
        mutex.withLock {
            if (session != token) return
            val probeRaw = evaluateJavascript(EpubBilingualJs.decorationCountScript)
            if (session != token) return
            val current = EpubBilingualJs.parseCountResult(probeRaw, default = 0)
            // Re-apply when the DOM has FEWER decorations than expected (a recreate/href-change
            // lost them). An unknown expected (<=0) always re-applies; a satisfied DOM is skipped.
            if (expectedCount > 0 && current >= expectedCount) return
            applyLocked(unit, targetLanguage, token)
        }
    }

    /**
     * feature #131 WI-9 — reconcile the CURRENT resource's DOM after a language (or provider) change while
     * an EPUB is open + STATIONARY. The reader's position/display re-apply signals fire only on scroll /
     * settings changes, so a mid-book language switch would otherwise leave the visible resource showing
     * the OLD language until the user scrolls (the deferred WI-7b finding b). This is the single entry the
     * reader calls on a VM language change: it bumps the session (invalidating any in-flight apply for the
     * old language + dropping the applied-count anchors so the fresh apply re-injects rather than accepting
     * a stale probe count), then — for the NEW captured session — runs a full [applyLocked]. `applyLocked`
     * re-enumerates the live resource and passes EVERY enumerated block id to the inject, so a shorter new
     * translation set REAPS the old-language decorations of blocks not re-translated (no stale-language
     * decoration leak — the same reconcile-set contract [apply] uses). Race-safe: the bump makes any
     * concurrent old-session apply discard at its next token re-check, and the mutex serializes this
     * reconcile against a racing scroll re-apply. A [CancellationException] propagates.
     */
    suspend fun reconcileLanguageChange(unit: TranslationUnitId, targetLanguage: String) {
        bumpSession()
        val token = session
        mutex.withLock { applyLocked(unit, targetLanguage, token) }
    }

    /** Remove every decoration node from the CURRENT resource DOM (under the mutex). Idempotent — a
     *  repeat clear on a clean DOM is a no-op. Drops the applied-count anchors (a subsequent apply
     *  re-injects fresh). Returns true when the clear script verified 0 remaining decorations
     *  (`clearScript` returns the remaining count); a null/failed eval (-1) returns false so the
     *  caller can treat the language transition as unfinished (Gate-4 High). */
    suspend fun clear(): Boolean =
        mutex.withLock {
            val remaining = EpubBilingualJs.parseCountResult(evaluateJavascript(EpubBilingualJs.clearScript), default = -1)
            appliedCount.clear()
            remaining == 0
        }

    /**
     * The atomic teardown path — call BEFORE publication/fragment teardown. Bumps the session (so
     * any in-flight apply's next token re-check discards) THEN clears under the mutex (which waits
     * for a live apply to release the lock, so no eval races the teardown). Returns the verified
     * clear result. A cooperative [CancellationException] PROPAGATES (a cancelled clear did NOT
     * finish — the caller must not treat the language transition as complete; Gate-4 High); any
     * other eval failure against an already-detaching navigator returns false (best-effort).
     */
    suspend fun shutdown(): Boolean {
        bumpSession()
        return try {
            clear()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            false
        }
    }

    // ── internals ──────────────────────────────────────────────

    /** The single-owner apply sequence, run WHILE HOLDING the mutex, guarded by [token]. */
    private suspend fun applyLocked(unit: TranslationUnitId, targetLanguage: String, token: Long) {
        if (session != token) return
        // Always (re)ensure the style — a same-session reflow can drop the injected <style>, so a
        // reinject must restore it (Gate-4 Medium: no per-session skip that survives a reflow).
        evaluateJavascript(EpubBilingualJs.styleScript(css))
        if (session != token) return
        val enumRaw = evaluateJavascript(EpubBilingualJs.enumScript)
        if (session != token) return
        val enumResult = EpubBilingualJs.parseEnumResult(enumRaw)
        val blocks = enumResult.blocks
        if (blocks.isEmpty()) return   // source-only: nothing translatable on this resource

        val texts = blocks.map { it.text }
        val segments = translate(unit, targetLanguage, texts, token) ?: return
        if (session != token) return   // superseded after translate — discard silently

        // Commit into VM render state (single writer), then inject the DOM.
        onEpubBlocksEnumerated(unit, segments)
        val idToSegment = pair(blocks, segments)
        // The reconcile set is EVERY enumerated block id — the inject removes the owned decoration
        // of any enumerated block that is NOT translated this pass (a now-blank/absent block, or a
        // language switch to a shorter set — Gate-4 High). So we still inject even for an empty map
        // when there may be stale decorations to reap. The enumerate's docId is carried into the
        // inject so a slow apply that enumerated resource A cannot inject into a now-different B.
        val allBlockIds = blocks.map { it.id }
        val injected = EpubBilingualJs.parseCountResult(
            evaluateJavascript(
                EpubBilingualJs.injectScript(idToSegment, allBlockIds, enumResult.docId, targetIsCjk(), targetIsRtl()),
            ),
            default = -1,
        )
        if (session != token) return   // superseded during inject — don't publish stale probe state
        if (injected < 0) return       // the DOM changed under the apply (doc mismatch) — abort, no probe update
        // Record the NONBLANK count actually injected (blank translations are source-only for
        // their block — excluded here so the probe's expected count matches the live DOM).
        appliedCount[unit] = idToSegment.size
    }

    /** Cache-first translate for [unit]: a zero-provider `cachedDirect` restore keyed on the
     *  enumerate's block count, falling back to the direct-block `prefetchDirect`. The captured
     *  [token] is re-checked between the cache read and the (provider) translate so a stale token
     *  never starts a provider translation. Returns the translated segments (length == [texts].size
     *  on the direct path), or null on a translate failure / a stale token (source-only — never a
     *  crash, never an errorUnit). A [CancellationException] propagates. */
    private suspend fun translate(
        unit: TranslationUnitId,
        targetLanguage: String,
        texts: List<String>,
        token: Long,
    ): List<String>? {
        val restore = try {
            prefetcher.cachedDirect(unit, expectedCount = texts.size, targetLanguage = targetLanguage)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        }
        restore?.segments?.let { return it }
        if (session != token) return null   // superseded before the provider translate — discard
        return try {
            prefetcher.prefetchDirect(unit, sourceSegments = texts, targetLanguage = targetLanguage)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        }
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
         * rows, and a centered echo treatment for heading rows. Injected on every reinject via
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
