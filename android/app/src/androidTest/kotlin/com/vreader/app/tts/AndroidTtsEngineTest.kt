package com.vreader.app.tts

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

/**
 * Feature #121 WI-2 — AndroidTtsEngine instrumented smoke: drives the REAL TextToSpeech on the
 * emulator. Audible output is NOT asserted (unobservable headless, like iOS TTS verification); this
 * proves init bridges to a result, enumeration is callable, and language availability maps to a
 * domain value — whether or not the emulator ships voice data.
 */
@RunWith(AndroidJUnit4::class)
class AndroidTtsEngineTest {

    private val ctx get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun init_returnsAResult_andEnumerationIsCallable() = runBlocking<Unit> {
        val engine = AndroidTtsEngine(ctx.applicationContext)
        try {
            // init must RESOLVE (ok or failed) within a bounded time — never hang.
            val result = withTimeout(15_000) { engine.awaitInit() }
            assertNotNull(result)

            if (result == TtsInitResult.ok) {
                // enumeration + language check are callable without throwing
                val engines = engine.engines()
                val voices = engine.voices(Locale.US)
                val avail = engine.isLanguageAvailable(Locale.US)
                assertNotNull(avail)
                assertTrue("engines list is non-null", engines.size >= 0)
                assertTrue("voices list is non-null", voices.size >= 0)
                // setRate is accepted (pre-clamped value)
                engine.setRate(1.0f)
            }
        } finally {
            engine.shutdown()
        }
    }

    @Test fun factory_createsEngine() = runBlocking<Unit> {
        val factory = AndroidTtsEngineFactory(ctx.applicationContext)
        val engine = factory.create()
        try {
            assertNotNull(engine)
            withTimeout(15_000) { engine.awaitInit() }
        } finally {
            engine.shutdown()
        }
    }

    @Test fun doubleInitIsIdempotent_andShutdownThenSpeakIsSafe() = runBlocking<Unit> {
        val engine = AndroidTtsEngine(ctx.applicationContext)
        try {
            val first = withTimeout(15_000) { engine.awaitInit() }
            val second = withTimeout(15_000) { engine.awaitInit() }  // must NOT re-construct / hang
            assertTrue("double init agrees", first == second)
        } finally {
            engine.shutdown()
        }
        // after shutdown the engine is single-use: speak is a safe no-op (false), awaitInit → failed
        assertTrue("speak after shutdown is a safe no-op", !engine.speak(TtsUtterance(0, 0, "hi")))
        assertTrue("re-init after shutdown fails (single-use)", engine.awaitInit() == TtsInitResult.failed)
    }
}
