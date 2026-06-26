// Purpose: feature #121 WI-2 (#110 Phase 3) — the production TtsEngine over android.speech.tts.
// TextToSpeech. Built with the APPLICATION context (no Activity leak). Init bridges the OnInitListener
// to a suspend; progress callbacks (not guaranteed on main) forward into a thread-safe SharedFlow that
// the ViewModel collects on main. Engine SWITCHING is recreate-via-factory, not the deprecated setter.
package com.vreader.app.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.merge
import java.util.Locale

class AndroidTtsEngine(
    context: Context,
    private val enginePackage: String? = null,
) : TtsEngine {

    private val appContext = context.applicationContext
    private val lifecycle = Any()                 // guards tts / closed / initDeferred transitions
    @Volatile private var tts: TextToSpeech? = null
    @Volatile private var closed = false
    private var initDeferred: CompletableDeferred<TtsInitResult>? = null  // single-flight init

    // TYPE-AWARE buffering so a Range burst can NEVER evict a terminal event: terminals (Started/Done/
    // Failed — one per sentence, trivial rate) go to a large buffer; ranges (hundreds per utterance,
    // highlight-only, lossy by design) to a small DROP_OLDEST one. The two are isolated, then merged.
    private val _terminal = MutableSharedFlow<TtsProgress>(extraBufferCapacity = 1024, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    private val _range = MutableSharedFlow<TtsProgress>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    // CONTRACT: `merge` does NOT guarantee cross-flow ordering — a Range may arrive before its
    // Started or after its Done. The CONSUMER (TtsViewModel, WI-3) gates Range by the CURRENT sentence:
    // a Range is applied only while `currentSentence.index == range.index` (the Started→Done window), so
    // an out-of-order Range (before Started / after a terminal, or for a stale index) is ignored. Range
    // is highlight-refinement only — losing/ignoring one never affects sentence advance (Started-keyed).
    override val progress: Flow<TtsProgress> = merge(_terminal, _range)

    private val progressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = emitTerminal(utteranceId) { g, i -> TtsProgress.Started(g, i) }
        override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
            val (g, i) = TtsUtterance.parse(utteranceId) ?: return
            _range.tryEmit(TtsProgress.Range(g, i, start, end))
        }
        override fun onDone(utteranceId: String?) = emitTerminal(utteranceId) { g, i -> TtsProgress.Done(g, i) }
        @Deprecated("deprecated base method", ReplaceWith(""))
        override fun onError(utteranceId: String?) = emitTerminal(utteranceId) { g, i -> TtsProgress.Failed(g, i, TtsErrorKind.speakFailed) }
        override fun onError(utteranceId: String?, errorCode: Int) = emitTerminal(utteranceId) { g, i -> TtsProgress.Failed(g, i, TtsErrorKind.speakFailed) }
    }

    override suspend fun awaitInit(): TtsInitResult {
        val deferred: CompletableDeferred<TtsInitResult>
        val isFirst: Boolean
        synchronized(lifecycle) {
            if (closed) return TtsInitResult.failed             // single-use: shut down, don't revive
            tts?.let { return TtsInitResult.ok }                // idempotent: already initialized
            val existing = initDeferred
            if (existing != null) { deferred = existing; isFirst = false }  // join the in-flight init
            else { deferred = CompletableDeferred(); initDeferred = deferred; isFirst = true }
        }
        // Only the FIRST caller constructs the (single) TextToSpeech; others await the same deferred,
        // so two concurrent awaitInit()s can never construct two engines.
        if (isFirst) constructEngine(deferred)
        return deferred.await()
    }

    /** Construct the one engine; resolve [deferred] from the init callback — re-entrancy-safe (if the
     *  OnInitListener fires synchronously during construction, before `holder[0]` is set, the status is
     *  stashed and processed right after assignment, never dropping/orphaning the engine). */
    private fun constructEngine(deferred: CompletableDeferred<TtsInitResult>) {
        val holder = arrayOfNulls<TextToSpeech>(1)
        var earlyStatus: Int? = null
        val engine = TextToSpeech(appContext, { status ->
            synchronized(lifecycle) {
                val e = holder[0]
                if (e == null) earlyStatus = status            // re-entrant: defer until assigned
                else finishInit(status, e, deferred)
            }
        }, enginePackage)
        synchronized(lifecycle) {
            holder[0] = engine
            earlyStatus?.let { finishInit(it, engine, deferred) }
        }
    }

    /** Caller holds [lifecycle]. Publishes a clean success or tears the engine down + reports failed.
     *  `CompletableDeferred.complete` is idempotent, so a double-fire is harmless. */
    private fun finishInit(status: Int, engine: TextToSpeech, deferred: CompletableDeferred<TtsInitResult>) {
        if (status == TextToSpeech.SUCCESS && !closed) {
            engine.setOnUtteranceProgressListener(progressListener)
            tts = engine
            deferred.complete(TtsInitResult.ok)
        } else {
            runCatching { engine.stop(); engine.shutdown() }
            deferred.complete(TtsInitResult.failed)
        }
    }

    override fun speak(utterance: TtsUtterance): Boolean {
        val t = tts ?: return false
        return t.speak(utterance.text, TextToSpeech.QUEUE_ADD, null, utterance.utteranceId) == TextToSpeech.SUCCESS
    }

    override fun stop() { tts?.stop() }

    override fun setRate(rate: Float): Boolean = tts?.setSpeechRate(rate) == TextToSpeech.SUCCESS

    /** Select a voice by name. `null` = leave the engine's current/default voice unchanged (NOT a
     *  reset — the VM picks an explicit embedded voice on start, so a null here is a documented no-op). */
    override fun setVoice(name: String?): Boolean {
        val t = tts ?: return false
        if (name == null) return true
        val v = t.voices?.firstOrNull { it.name == name } ?: return false
        return t.setVoice(v) == TextToSpeech.SUCCESS
    }

    override fun engines(): List<TtsEngineOption> =
        tts?.engines?.map { TtsEngineOption(it.name, it.label) } ?: emptyList()

    override fun voices(locale: Locale?): List<TtsVoiceOption> {
        val all = tts?.voices ?: return emptyList()
        val candidates = all.map { v ->
            TtsVoiceFilter.Candidate(
                name = v.name, locale = v.locale, quality = v.quality,
                networkRequired = v.isNetworkConnectionRequired,
                notInstalled = v.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) == true,
            )
        }
        return TtsVoiceFilter.filter(candidates, locale)   // deprioritizes very-low, never drops all
    }

    override fun isLanguageAvailable(locale: Locale): TtsLanguageAvailability =
        when (tts?.isLanguageAvailable(locale)) {
            TextToSpeech.LANG_MISSING_DATA -> TtsLanguageAvailability.missingData
            TextToSpeech.LANG_NOT_SUPPORTED, null -> TtsLanguageAvailability.notSupported
            else -> TtsLanguageAvailability.available  // LANG_AVAILABLE / COUNTRY_(VAR_)AVAILABLE
        }

    override fun shutdown() {
        val pending: CompletableDeferred<TtsInitResult>?
        synchronized(lifecycle) {
            closed = true
            runCatching { tts?.stop(); tts?.shutdown() }
            tts = null
            pending = initDeferred
            initDeferred = null
        }
        pending?.complete(TtsInitResult.failed)  // unblock an in-flight awaitInit (outside the lock)
    }

    /** Emit a terminal event (Started/Done/Failed), dropping an UNATTRIBUTABLE one (no parseable id) —
     *  never fabricate generation 0, which the VM would mistake for the first generation's utterance. */
    private inline fun emitTerminal(id: String?, make: (Long, Int) -> TtsProgress) {
        val (g, i) = TtsUtterance.parse(id) ?: return
        _terminal.tryEmit(make(g, i))
    }
}

/** Builds an [AndroidTtsEngine] (optionally for a specific engine package). Engine switching is a
 *  shutdown + recreate of the engine via this factory, NOT the deprecated `setEngineByPackageName`. */
class AndroidTtsEngineFactory(context: Context) : TtsEngineFactory {
    private val appContext = context.applicationContext
    override suspend fun create(enginePackage: String?): TtsEngine = AndroidTtsEngine(appContext, enginePackage)
}
