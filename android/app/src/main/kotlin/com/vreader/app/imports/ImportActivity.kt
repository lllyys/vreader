// Purpose: feature #155 — the app's single exported inbound-document entry point.
// "Open with VReader" / "Share to VReader" resolve HERE, not to MainActivity: every
// activity is launchMode `standard`, so a VIEW filter on MainActivity would stack a
// second MainActivity over an open reader (plan D2).
//
// Task model: the activity is declared `taskAffinity=""` + `noHistory` +
// `excludeFromRecents`, and is themed TRANSLUCENT (never `Theme.NoDisplay` — a
// no-display activity must finish before it would become visible, but this one must
// stay alive long enough to open the incoming streams while its read grant is still
// valid; plan D6). Nothing is ever drawn.
//
// SCOPE — WI-2 ships the declaration plus the pure payload extractor only. The
// resolve → open → enqueue body, and the MainActivity hand-off, land in WI-5.
//
// @coordinates-with: AndroidManifest.xml (the four intent filters — MIME matching and
//   pathPattern matching live in SEPARATE filters because <data> elements merge into a
//   cross-product within one filter), res/values/themes.xml (Theme.VReader.Import)
package com.vreader.app.imports

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.core.content.IntentCompat

class ImportActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // WI-2 skeleton: prove the OS can route a document here. WI-5 replaces this
        // with the resolve/open/enqueue body (and only then calls finish()).
        finish()
    }

    companion object {
        /**
         * The most URIs a single inbound intent may contribute. A share sheet can hand
         * over an arbitrarily large selection; the cap bounds the work an untrusted
         * sender can queue.
         */
        const val MAX_BATCH = 20

        /**
         * Every URI an inbound intent carries, in sender order, capped at [MAX_BATCH].
         *
         * `VIEW` carries its payload in `intent.data`; `SEND` / `SEND_MULTIPLE` carry it
         * in `EXTRA_STREAM`, falling back to `ClipData` (some senders populate only the
         * clip). Returns an empty list for a missing, empty, or wrongly-typed payload —
         * this NEVER throws, because an exported entry point must survive anything a
         * hostile or merely sloppy sender puts in the intent.
         */
        fun urisFrom(intent: Intent?): List<Uri> {
            if (intent == null) return emptyList()
            val found = when (intent.action) {
                Intent.ACTION_VIEW -> listOfNotNull(intent.data)
                Intent.ACTION_SEND -> singleStreamUri(intent)?.let { listOf(it) } ?: clipUris(intent)
                Intent.ACTION_SEND_MULTIPLE -> multiStreamUris(intent).ifEmpty { clipUris(intent) }
                else -> emptyList()
            }
            return found.take(MAX_BATCH)
        }

        /** `EXTRA_STREAM` as a single Uri; null when absent OR present with another type. */
        private fun singleStreamUri(intent: Intent): Uri? = runCatching {
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
        }.getOrNull()

        /** `EXTRA_STREAM` as a list; non-Uri members are dropped rather than fatal. */
        private fun multiStreamUris(intent: Intent): List<Uri> = runCatching {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                ?.filterIsInstance<Uri>()
                .orEmpty()
        }.getOrElse { emptyList() }

        /** ClipData items that actually carry a Uri (a text item contributes nothing). */
        private fun clipUris(intent: Intent): List<Uri> = runCatching {
            val clip = intent.clipData ?: return@runCatching emptyList()
            (0 until clip.itemCount).mapNotNull { clip.getItemAt(it)?.uri }
        }.getOrElse { emptyList() }
    }
}
