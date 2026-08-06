package com.vreader.app.annotations

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #165 WI-7 — a stand-in for the system document picker, so a connected test can drive the
 * REAL production `ACTION_OPEN_DOCUMENT` launcher without a human tapping DocumentsUI.
 *
 * Why an `ActivityMonitor` and not an `Intent` handed to the reader: the point of criterion A-10a is
 * that the launcher is *registered and reachable from the designed row*. A test that constructed the
 * picked `Uri` itself and called the controller would prove the controller works and nothing about
 * whether a user can get there — exactly the hole rule 47's Gate-5 exists to close. This intercepts
 * the app's own `startActivityForResult`, so the assertion is "the app really launched a document
 * picker", and the stubbed result travels back through the app's own
 * `ActivityResultLauncher` callback.
 *
 * The no-argument `ActivityMonitor()` constructor is the one that sets
 * `ignoreMatchingSpecificIntents`, which is what lets [onStartActivity] see the intent: it is
 * consulted BEFORE the `IntentFilter` path, so the intent itself is captured (action + the MIME
 * hint) rather than merely counted, and a null return lets every unrelated activity start proceed
 * untouched.
 */
class AnnotationImportPickerMonitor private constructor(
    private val result: Instrumentation.ActivityResult,
) : Instrumentation.ActivityMonitor() {

    private val captured = AtomicReference<Intent?>(null)

    @Volatile
    var launchCount: Int = 0
        private set

    /** The intent the app actually started, or null when it never launched a picker. */
    val launchedIntent: Intent? get() = captured.get()

    override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
        if (intent.action != Intent.ACTION_OPEN_DOCUMENT) return null
        captured.set(Intent(intent))
        launchCount += 1
        return result
    }

    companion object {
        /** Installs a picker that answers with [uri]; a null [uri] answers `RESULT_CANCELED`. */
        fun install(uri: Uri?): AnnotationImportPickerMonitor {
            val result = if (uri == null) {
                Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            } else {
                Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(uri))
            }
            val monitor = AnnotationImportPickerMonitor(result)
            InstrumentationRegistry.getInstrumentation().addMonitor(monitor)
            return monitor
        }
    }

    fun remove() {
        InstrumentationRegistry.getInstrumentation().removeMonitor(this)
    }
}
