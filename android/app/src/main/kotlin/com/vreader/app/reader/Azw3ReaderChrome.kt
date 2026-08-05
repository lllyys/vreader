// Purpose: the AZW3/MOBI/KF8 reader host's CHROME + pure jump helpers, extracted verbatim from
// Azw3ReaderActivity.kt (feature #140 WI-5 — a behaviour-preserving split; the activity was past the
// ~300-line guideline). Same package `com.vreader.app.reader`, so no call site or test import changed:
//   • [Azw3ReaderChrome]      — the shared ReaderChromeScaffold wiring for the AZW3 host (feature #132
//                               WI-7-hosts + #134 WI-5 More/Details + #135 WI-7 bookmarks).
//   • Azw3NotesBottomChrome   — the Notes-only bottom toolbar (private; AZW3 has no Contents/Display).
//   • [azw3JumpResult] / [azw3JumpDecision] — the pure, JVM-testable bookmark-jump helpers.
// The activity (Azw3ReaderActivity.kt) keeps the lifecycle, the WebView body host, and the plain
// loading/error ReaderScaffold. Nothing here changed behaviour, visibility, defaults, or order.
package com.vreader.app.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.chrome.ReaderChromeScaffold
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.foliate.Azw3GoToResult
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator

// ---- feature #135 WI-7 — AZW3 pure host wiring helpers ----

/**
 * feature #135 WI-7 — map an awaited [Azw3GoToResult] (the settled outcome of [Azw3Document.goTo]) to the
 * sheet's [JumpResult]. [Azw3GoToResult.Succeeded] landed → [JumpResult.Succeeded]; Timeout / Failed
 * (unresolvable target or dead bundle) / Superseded (a newer jump replaced this one) are all NON-landings
 * → [JumpResult.Failed] (no invented error surface — rule 51). Pure/JVM-testable. Used to surface the
 * awaited landing outcome off the background jump (the SYNCHRONOUS sheet-dismiss decision is
 * [azw3JumpDecision], since the awaited goTo cannot run on the tap thread).
 */
fun azw3JumpResult(result: Azw3GoToResult): JumpResult = when (result) {
    is Azw3GoToResult.Succeeded -> JumpResult.Succeeded
    Azw3GoToResult.Timeout, Azw3GoToResult.Failed, Azw3GoToResult.Superseded -> JumpResult.Failed
}

/**
 * feature #135 WI-7 — the SYNCHRONOUS dismiss decision for an AZW3 bookmark jump. Because the actual
 * [Azw3Document.goTo] is awaited (~3s on the bundle relocate ack — it cannot run on the tap thread), the
 * sheet decides dismiss-vs-stay up front from target validity: a null document (nothing loaded) OR a
 * canonical with no jumpable target (no cfi + no finite progression, per [FoliateGoToTarget.from]) →
 * [JumpResult.Failed] (the sheet stays open — rule 51); an otherwise-jumpable target → [JumpResult.Succeeded]
 * (dismiss; the awaited goTo then lands the position off-thread, re-issued once on render death).
 * Pure/JVM-testable ([document] is only null-checked).
 */
fun azw3JumpDecision(document: Azw3Document?, canonical: Locator): JumpResult {
    if (document == null) return JumpResult.Failed
    return if (com.vreader.app.reader.foliate.FoliateGoToTarget.from(canonical) != null) {
        JumpResult.Succeeded
    } else {
        JumpResult.Failed
    }
}

/**
 * The AZW3 reader host chrome — feature #132 WI-7-hosts (mirror of WI-6's [TxtReaderChrome]). Renders the
 * shared [ReaderChromeScaffold] (top bar + the Notes review sheet) over the AZW3 [body] (the WebView). AZW3
 * has no reader TOC → `tocEntries` is EMPTY (the EmptyTocProvider posture) → the scaffold hides the Contents
 * control. It has no Display control (the #129 CSS applies live from the store with no control surface); the
 * bottom chrome is a Notes-only toolbar ([Azw3NotesBottomChrome]). The top bar's Search/More/bookmark slots
 * are omitted (null — #133/#134/#135; no dead controls). [onJumpToAnnotation] is NULL — AZW3 review is
 * review-only (no in-session goTo until #135; the card is non-clickable, a capability gate — FoliateBridge/
 * Azw3Document/foliate-js stay untouched). Wrapped in a `systemBarsPadding()` Column so the chrome clears
 * the status/nav bars. Extracted (internal) so the host wiring is directly testable.
 */
@Composable
internal fun Azw3ReaderChrome(
    theme: ReaderTheme,
    title: String,
    chromeState: MutableState<ReaderChromeState>,
    annotations: AnnotationsSnapshot,
    onBack: () -> Unit,
    onShareAnnotations: () -> Unit,
    body: @Composable () -> Unit,
    // feature #134 WI-5 — the More menu's Book-details model + Share/copy actions (null model → no More).
    bookDetails: com.vreader.app.reader.details.BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
    // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + AZW3 jump (all nullable/default
    // so #132/#134 callers stay valid). A non-null onToggleBookmark fills the toggle; onJumpBookmark makes
    // the Bookmarks-tab rows clickable + dismiss-on-Succeeded (null → review-only rows).
    isCurrentBookmarked: Boolean = false,
    onToggleBookmark: (() -> Unit)? = null,
    currentLocator: Locator? = null,
    bookmarks: List<BookmarkRowItem> = emptyList(),
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
) {
    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
        ReaderChromeScaffold(
            theme = theme,
            title = title,
            chromeState = chromeState,
            onBack = onBack,
            tocEntries = emptyList(),           // no TOC → the scaffold hides the Contents control
            currentTocIndex = 0,
            annotations = annotations,
            onJumpToc = { false },              // unreachable: Contents is hidden with an empty TOC
            // AZW3 tap-to-jump is NULL — review-only capability gate (no goTo until #135); cards non-clickable.
            onJumpToAnnotation = null,
            onShareAnnotations = onShareAnnotations,
            // Search top-bar slot stays null (#133 — no dead control). feature #134 WI-5:
            // the More button + Book Details / Share are wired through the scaffold's More menu below.
            bottomChrome = { _, onOpenNotes ->
                // AZW3 has no Contents (empty TOC) + no Display control → Notes only.
                Azw3NotesBottomChrome(theme = theme, onOpenNotes = onOpenNotes)
            },
            body = body,
            bookDetails = bookDetails,
            onShareBook = onShareBook,
            onCopyFingerprint = onCopyFingerprint,
            // feature #135 WI-7 — the bookmark toggle + Bookmarks tab, now lit up for AZW3.
            isCurrentBookmarked = isCurrentBookmarked,
            onToggleBookmark = onToggleBookmark,
            currentLocator = currentLocator,
            bookmarks = bookmarks,
            onJumpBookmark = onJumpBookmark,
        )
    }
}

/**
 * The AZW3 host's bottom chrome — the designed reader-toolbar "Notes" button only (feature #132 WI-7-hosts).
 * AZW3 has no reader TOC (Contents hidden) and no Display control surface (#129 applies CSS live from the
 * store), so of the design's Contents · Notes · Display · AI toolbar only the Notes slot applies. Uses the
 * same designed icon-above-label treatment as ReaderBottomChrome's Notes slot (the Highlighter/BorderColor
 * glyph, `chrome-notes` testTag). Rendered ONLY when [onOpenNotes] is non-null (always so for #132).
 */
@Composable
private fun Azw3NotesBottomChrome(theme: ReaderTheme, onOpenNotes: (() -> Unit)?) {
    if (onOpenNotes == null) return
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val rule = theme.ink.copy(alpha = 0.10f)
    Column(
        Modifier.fillMaxWidth().background(theme.background).testTag("azw3-bottom-chrome"),
    ) {
        Box(Modifier.fillMaxWidth().heightIn(min = 0.5.dp, max = 0.5.dp).background(rule))
        Row(
            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 28.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .clickable(onClick = onOpenNotes)
                    .padding(horizontal = 12.dp, vertical = 4.dp)
                    .testTag("chrome-notes")
                    .semantics { contentDescription = "Notes" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(Icons.Outlined.BorderColor, contentDescription = null, tint = ink, modifier = Modifier.size(22.dp))
                Text("Notes", color = sub, fontSize = 10.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}
