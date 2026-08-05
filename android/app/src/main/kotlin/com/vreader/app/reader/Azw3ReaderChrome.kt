// Purpose: the AZW3/MOBI/KF8 reader host's CHROME + pure jump helpers, extracted verbatim from
// Azw3ReaderActivity.kt (feature #140 WI-5 — a behaviour-preserving split; the activity was past the
// ~300-line guideline). Same package `com.vreader.app.reader`, so no call site or test import changed:
//   • [Azw3ReaderChrome]      — the shared ReaderChromeScaffold wiring for the AZW3 host (feature #132
//                               WI-7-hosts + #134 WI-5 More/Details + #135 WI-7 bookmarks + #140 WI-6
//                               Contents).
//   • Azw3BottomChrome        — the Contents · Notes bottom toolbar (private), each slot rendered only
//                               when the scaffold supplies its callback.
//   • [azw3JumpResult] / [azw3JumpDecision] — the pure, JVM-testable jump helpers (shared by the
//                               bookmark rows and, since #140 WI-6, the Contents rows).
// The activity (Azw3ReaderActivity.kt) keeps the lifecycle, the WebView body host, and the plain
// loading/error ReaderScaffold.
//
// feature #140 WI-6 — AZW3 now HAS a table of contents (FoliateTocProvider over the tree the bundle
// already posts on book-ready), so this file makes it REACHABLE. Two independent gates had to open:
// the scaffold's `tocEntries.isEmpty()` show/hide rule (fed by the host's real entries) AND the
// bottom-chrome slot, which used to discard the scaffold's Contents open-callback outright — a
// non-empty TOC alone would have lit up nothing. The sheet, the rows, and the indentation are #132's,
// reused unchanged (rule 51: no new visible element).
package com.vreader.app.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.chrome.ReaderChromeScaffold
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ToolbarIconButton
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.foliate.Azw3GoToResult
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator

// ---- feature #135 WI-7 — AZW3 pure host wiring helpers ----

/**
 * feature #135 WI-7 — map an awaited [Azw3GoToResult] (the settled outcome of [Azw3Document.goTo]) to the
 * sheet's [JumpResult]. [Azw3GoToResult.Succeeded] — the bundle ACKNOWLEDGED the jump — →
 * [JumpResult.Succeeded]; Timeout / Failed (unresolvable target or dead bundle) / Superseded (a newer jump
 * replaced this one) all → [JumpResult.Failed] (no invented error surface — rule 51). Pure/JVM-testable.
 * Used to surface the awaited outcome off the background jump (the SYNCHRONOUS sheet-dismiss decision is
 * [azw3JumpDecision], since the awaited goTo cannot run on the tap thread).
 *
 * A `Succeeded` here means ACKNOWLEDGED, NOT MOVED (Gate-4 R1): foliate's `view.goTo` catches a failed
 * resolution and settles anyway, so the shim can ack `ok:true` on a jump that changed nothing. Only an
 * observed change in a later relocate's reported position proves motion — see WI-7's connected round-trip.
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
 * (dismiss; the awaited goTo is then ISSUED off-thread, and re-issued once on render death). "Jumpable"
 * means a target could be DERIVED — not that the reader will move; see [azw3JumpResult].
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
 * feature #140 WI-6 — the SYNCHRONOUS dismiss decision for a tapped Contents row, i.e. [azw3JumpDecision]
 * with the row-selection boundary folded in. [JumpResult.Failed] (the sheet stays open — rule 51) when:
 *  - [index] is outside [entries] (a stale tap against a TOC that has since changed), or
 *  - [document] is null — the window right after a render-process death, before the replacement document
 *    is hoisted back up. The rows themselves stay on screen (the host never clears them), so the user can
 *    simply tap again once the reader has recovered.
 * Otherwise it delegates to [azw3JumpDecision], which reports Succeeded iff the row's canonical locator
 * yields a jump target at all.
 *
 * It decides only whether to DISMISS THE SHEET. It is not, and must not be read as, evidence that the
 * reader moved: foliate's `view.goTo` swallows a failed resolution and acks anyway, so even the awaited
 * result that follows proves only that the round-trip completed. Actual motion is observed by WI-7's
 * real-book connected round-trip, against the position a later relocate reports. Pure/JVM-testable
 * ([document] is only null-checked).
 */
fun azw3TocJumpDecision(document: Azw3Document?, entries: List<TocEntry>, index: Int): JumpResult {
    val entry = entries.getOrNull(index) ?: return JumpResult.Failed
    return azw3JumpDecision(document, entry.canonicalLocator)
}

/**
 * The AZW3 reader host chrome — feature #132 WI-7-hosts (mirror of WI-6's [TxtReaderChrome]). Renders the
 * shared [ReaderChromeScaffold] (top bar + the Contents|Bookmarks and Notes sheets) over the AZW3 [body]
 * (the WebView). It has no Display control (the #129 CSS applies live from the store with no control
 * surface); the bottom chrome is the Contents · Notes toolbar (Azw3BottomChrome). The top bar's Search
 * slot is omitted (null — #133; no dead controls). [onJumpToAnnotation] is NULL — AZW3 annotation review
 * is review-only (the card is non-clickable, a capability gate). Wrapped in a `systemBarsPadding()`
 * Column so the chrome clears the status/nav bars. Extracted (internal) so the host wiring is directly
 * testable.
 *
 * feature #140 WI-6 — the table of contents: [tocEntries] are the book's chapters as
 * [com.vreader.app.reader.nav.FoliateTocProvider] flattened them, [currentTocIndex] the row to
 * highlight (`foliateTocIndexFor` over the live `relocate.tocHref`), and [onJumpToc] the row jump
 * (`true` → the sheet dismisses, `false` → it stays open with no invented error surface — rule 51). All
 * three are DEFAULTED to the pre-#140 posture (empty / 0 / always-false), so an omitting caller still
 * hides the Contents control and compiles unchanged. An empty list is the scaffold's documented
 * hide-the-control signal — a Kindle book with no usable TOC behaves exactly as it did before #140.
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
    tocEntries: List<TocEntry> = emptyList(),
    currentTocIndex: Int = 0,
    onJumpToc: (Int) -> Boolean = { false },
) {
    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
        ReaderChromeScaffold(
            theme = theme,
            title = title,
            chromeState = chromeState,
            onBack = onBack,
            tocEntries = tocEntries,
            currentTocIndex = currentTocIndex,
            annotations = annotations,
            onJumpToc = onJumpToc,
            // AZW3 tap-to-jump is NULL — review-only capability gate (no goTo until #135); cards non-clickable.
            onJumpToAnnotation = null,
            onShareAnnotations = onShareAnnotations,
            // Search top-bar slot stays null (#133 — no dead control). feature #134 WI-5:
            // the More button + Book Details / Share are wired through the scaffold's More menu below.
            // feature #140 WI-6 — the Contents open-callback is now PASSED IN, not discarded. Before
            // this WI the slot read `{ _, onOpenNotes -> … }`, so a non-empty [tocEntries] would have
            // lit up nothing: the scaffold's show/hide rule and the host's use of the callback are two
            // independent gates and BOTH have to open. The scaffold still hands a NULL callback when
            // [tocEntries] is empty, so a book with no TOC keeps today's Notes-only toolbar exactly.
            bottomChrome = { onOpenContents, onOpenNotes ->
                Azw3BottomChrome(theme = theme, onOpenContents = onOpenContents, onOpenNotes = onOpenNotes)
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
 * The AZW3 host's bottom chrome — the designed reader toolbar's Contents · Notes subset (feature #132
 * WI-7-hosts, extended by feature #140 WI-6). Of the design's Contents · Notes · Display · AI toolbar
 * this host renders Contents (once the book HAS a TOC — #140) and Notes; it has no Display control
 * surface (#129 applies the CSS live from the store) and no scrubber (foliate owns pagination), so
 * those two stay omitted. Both slots come from [ToolbarIconButton], the SAME composable
 * `ReaderBottomChrome` uses on EPUB/TXT/MD, so the treatment cannot drift between hosts.
 *
 * Each slot renders ONLY when its callback is non-null (the no-dead-controls rule): the scaffold passes
 * a null [onOpenContents] exactly when `tocEntries` is empty, which is how a Kindle book with no usable
 * TOC keeps the pre-#140 Notes-only toolbar.
 */
@Composable
private fun Azw3BottomChrome(
    theme: ReaderTheme,
    onOpenContents: (() -> Unit)?,
    onOpenNotes: (() -> Unit)?,
) {
    if (onOpenContents == null && onOpenNotes == null) return
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
            // The design order: Contents before Notes.
            if (onOpenContents != null) {
                ToolbarIconButton(
                    tag = "chrome-contents", label = "Contents",
                    icon = Icons.AutoMirrored.Filled.FormatListBulleted,
                    ink = ink, sub = sub, onClick = onOpenContents,
                )
            }
            if (onOpenNotes != null) {
                ToolbarIconButton(
                    tag = "chrome-notes", label = "Notes", icon = Icons.Outlined.BorderColor,
                    ink = ink, sub = sub, onClick = onOpenNotes,
                )
            }
        }
    }
}
