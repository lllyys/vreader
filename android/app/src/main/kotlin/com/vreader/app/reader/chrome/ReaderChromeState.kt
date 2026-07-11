// Purpose: feature #132 WI-5 (#110 Phase 3) — the host-agnostic reader chrome state consumed by
// [ReaderChromeScaffold]: whether the top/bottom chrome is visible, and which modal sheet (if any) is
// open. #132 ships the Contents + Notes sheet routes only; the `Bookmarks` route arrives with #135 (the
// no-dead-route rule). Persisted across rotation / process death via [ReaderChromeStateSaver] — a custom
// `Saver<ReaderChromeState, String>` mirroring #127's `SheetRouteSaver` (library/CollectionSheets.kt),
// because `rememberSaveable` cannot auto-persist an arbitrary class. Any unrecognized/malformed token
// restores to the safe fallback (`chromeVisible=false`, `sheet=None`) and NEVER throws.
package com.vreader.app.reader.chrome

import androidx.compose.runtime.saveable.Saver

/**
 * Which modal sheet the reader chrome currently shows. #132 has Contents ([Toc]) and Notes; the
 * `Bookmarks` route is added by #135 (documented handoff — no dead route until it has a data source).
 */
sealed interface ReaderSheet {
    data object None : ReaderSheet
    data object Toc : ReaderSheet
    data object Notes : ReaderSheet
}

/**
 * Hoisted reader-chrome UI state. [chromeVisible] toggles the top/bottom bars (a center-tap on the body
 * flips it); [sheet] names the open modal sheet (default [ReaderSheet.None]). Defaults to chrome VISIBLE
 * with no sheet — the reader opens with its chrome shown.
 */
data class ReaderChromeState(
    val chromeVisible: Boolean = true,
    val sheet: ReaderSheet = ReaderSheet.None,
)

/** The stable token for a [ReaderSheet] (used by [ReaderChromeStateSaver]; `None` never appears in a token). */
private fun ReaderSheet.token(): String = when (this) {
    ReaderSheet.None -> "none"
    ReaderSheet.Toc -> "toc"
    ReaderSheet.Notes -> "notes"
}

/** Parses a sheet token; any unknown value falls back to [ReaderSheet.None] (never throws). */
private fun sheetFromToken(token: String): ReaderSheet = when (token) {
    "toc" -> ReaderSheet.Toc
    "notes" -> ReaderSheet.Notes
    else -> ReaderSheet.None
}

/**
 * Serializes [ReaderChromeState] to a `"<visible>|<sheet>"` String so `rememberSaveable` survives
 * process death — the #127 `SheetRouteSaver` pattern. Restore is total: a malformed/empty/unknown token
 * (wrong separator, non-boolean flag, unknown sheet name) restores to the safe fallback
 * (`chromeVisible=false`, `sheet=None`) rather than throwing.
 */
val ReaderChromeStateSaver: Saver<ReaderChromeState, String> = Saver(
    save = { "${it.chromeVisible}|${it.sheet.token()}" },
    restore = { token ->
        val parts = token.split("|")
        if (parts.size != 2) {
            ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.None)
        } else {
            val visible = parts[0].toBooleanStrictOrNull() ?: false
            ReaderChromeState(chromeVisible = visible, sheet = sheetFromToken(parts[1]))
        }
    },
)
