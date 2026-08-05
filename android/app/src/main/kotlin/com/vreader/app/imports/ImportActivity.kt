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
import android.os.Parcelable
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
         * over an arbitrarily large selection; every extractor below stops COLLECTING at
         * this many rather than materialising the sender's whole payload and truncating
         * afterwards, so a hostile batch costs at most 20 references.
         */
        const val MAX_BATCH = 20

        /**
         * The most payload entries any extractor will LOOK AT, whether or not they turn
         * out to be URIs.
         *
         * [MAX_BATCH] alone bounds a dense payload but not a sparse one: 100 000
         * URI-less `ClipData` items would still be walked one by one. This is the
         * separate work bound for that case. It is 10x [MAX_BATCH] so a legitimately
         * mixed share (URIs interleaved with text items) still finds its books, while a
         * hostile sender's cost stays constant.
         */
        const val MAX_SCANNED_ITEMS = 200

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
            return when (intent.action) {
                Intent.ACTION_VIEW -> listOfNotNull(intent.data)
                Intent.ACTION_SEND -> singleStreamUri(intent)?.let { listOf(it) } ?: clipUris(intent)
                Intent.ACTION_SEND_MULTIPLE -> multiStreamUris(intent).ifEmpty { clipUris(intent) }
                else -> emptyList()
            }
        }

        /** `EXTRA_STREAM` as a single Uri; null when absent OR present with another type. */
        private fun singleStreamUri(intent: Intent): Uri? = runCatching {
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
        }.getOrNull()

        /**
         * `EXTRA_STREAM` as a list of at most [MAX_BATCH] URIs.
         *
         * The list is requested as `Parcelable`, not `Uri`, on purpose: `IntentCompat`
         * has two implementations (a plain unchecked cast below API 34, the type-checked
         * platform call above it), and asking for `Uri` lets the newer one reject a
         * mixed-type list wholesale. Asking for the base type makes both behave alike and
         * leaves the per-element filtering here, where a stray member is skipped rather
         * than fatal. Iterating as `Any?` also avoids a per-element checked cast.
         */
        private fun multiStreamUris(intent: Intent): List<Uri> {
            val raw: List<Any?> = runCatching {
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Parcelable::class.java)
            }.getOrNull() ?: return emptyList()
            val out = ArrayList<Uri>()
            var scanned = 0
            for (item in raw) {
                if (out.size >= MAX_BATCH || scanned >= MAX_SCANNED_ITEMS) break
                scanned++
                if (item is Uri) out.add(item)
            }
            return out
        }

        /**
         * ClipData items that actually carry a Uri (a text item contributes nothing).
         *
         * Each item is read under its own guard so one malformed entry skips itself
         * instead of discarding the valid URIs around it.
         */
        private fun clipUris(intent: Intent): List<Uri> {
            val clip = runCatching { intent.clipData }.getOrNull() ?: return emptyList()
            val count = runCatching { clip.itemCount }.getOrNull() ?: return emptyList()
            val out = ArrayList<Uri>()
            var index = 0
            while (index < count && index < MAX_SCANNED_ITEMS && out.size < MAX_BATCH) {
                runCatching { clip.getItemAt(index)?.uri }.getOrNull()?.let { out.add(it) }
                index++
            }
            return out
        }
    }
}
