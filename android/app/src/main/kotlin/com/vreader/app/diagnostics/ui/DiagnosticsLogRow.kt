package com.vreader.app.diagnostics.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.diagnostics.DiagnosticsCategoryBounding
import com.vreader.app.diagnostics.DiagnosticsLogEntry
import com.vreader.app.diagnostics.DiagnosticsRedactor
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Purpose: Feature #164 WI-6a — the designed log row and day header (`DiagLogRow` / `DiagDayHeader`,
 * `vreader-diagnostics.jsx:249-301`, artboards A1/A2).
 *
 * Key decisions:
 * - **The clipboard write lives HERE, and there is no API to bypass it.** "Copy entry" is an EGRESS
 *   point (plan section 6.1; iOS parity `DiagnosticsLogView.swift:173`), so the row itself puts
 *   `DiagnosticsRedactor.redact(message)` on the clipboard rather than handing the raw message to a
 *   caller-supplied callback. A hoisted `onCopy(String)` would make the sole security barrier on the
 *   most sensitive screen in the app a matter of every future caller remembering to redact.
 * - **Display is NOT egress.** The expanded row shows the message verbatim — redacting the screen
 *   would defeat the viewer's entire purpose, and the bytes are already on the device. The
 *   asymmetry is asserted in ONE connected test so swapping the two paths cannot pass.
 * - **The category pill renders the BOUNDED chip**, not the raw logcat tag: the design draws one of
 *   `DIAG_CATEGORIES`, and an unbounded pill would print `SQLiteLog` / `cr_Ime` in a slot drawn for
 *   seven names. The raw tag is not lost — `DiagnosticsLogStore.exportText` carries it verbatim.
 * - **The timestamp's zone is injected** so the meta line is reproducible in a test; production
 *   passes the device zone, which is what a user reading their own log expects.
 * - **`maxLines` IS the design's 3-line clamp** (`WebkitLineClamp: 3`); expansion lifts it. The
 *   collapsed height is asserted against the line height rather than trusted.
 *
 * Accepted, NOT mitigated (Gate-4 round 1, both are design-owned decisions this WI may not make):
 * - The design's `Icons.Copy` is REFERENCED at `vreader-diagnostics.jsx:295` but is not defined in
 *   the committed icon set, so no committed glyph path exists to transcribe. The affordance itself
 *   IS designed (position, 11px size, accent color, "Copy entry" label); only the glyph outline is
 *   missing, and the platform copy glyph is what this app already ships for a copy affordance
 *   (`SelectionPopover`, `BookDetailsRows`). Substituting it renders LESS invention than omitting a
 *   depicted element; flagged for the design bundle to close.
 * - The designed control heights (a ~26dp chip, a ~25dp Copy pill) are below the 48dp accessibility
 *   touch-target guidance. Growing them would change the depicted geometry and the row's vertical
 *   rhythm, which is exactly what rule 51 reserves to the design; the whole row is a large tap
 *   target for the expand/collapse gesture, so only the Copy pill is small.
 *
 * @coordinates-with DiagnosticsLevelStyle.kt, DiagnosticsRedactor.kt, DiagnosticsCategoryBounding.kt,
 *   DiagnosticsDayGrouper.kt, `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */

/** Stable test handles for the row's parts (the house `testTag` convention). */
object DiagnosticsRowTags {
    const val ROW = "diag-log-row"
    const val TIME = "diag-row-time"
    const val LEVEL = "diag-row-level"
    const val CATEGORY = "diag-row-category"
    const val MESSAGE = "diag-row-message"
    const val COPY = "diag-row-copy"
    const val DIVIDER = "diag-row-divider"
    const val DAY_HEADER = "diag-day-header"
}

/** The design's row typography, exposed so a test can reason about the 3-line clamp. */
object DiagnosticsRowMetrics {
    /** `fontSize: 12, lineHeight: 1.5` → 18sp per message line. */
    val MESSAGE_LINE_HEIGHT = 18.sp
    val MESSAGE_SIZE = 12.sp
    const val COLLAPSED_MAX_LINES = 3
}

private val TIME_FORMAT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("HH:mm:ss.SSS", Locale.ROOT)

/** The clipboard entry's label — what a clipboard manager UI shows as the source of the paste. */
private const val CLIP_LABEL = "vreader diagnostics"

/**
 * The design's day divider — `"TODAY · 10 JUNE"`. [header] is
 * `DiagnosticsDaySection.header` as WI-5 composed it; the uppercasing is the design's
 * `textTransform`, applied here because Compose has no such text property.
 */
@Composable
fun DiagnosticsDayHeader(header: String, modifier: Modifier = Modifier) {
    val tokens = LocalDiagnosticsTokens.current
    Text(
        header.uppercase(Locale.ROOT),
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 18.dp, end = 18.dp, top = 10.dp, bottom = 4.dp)
            .testTag(DiagnosticsRowTags.DAY_HEADER),
        color = tokens.sub,
        fontFamily = DiagnosticsFonts.Sans,
        fontSize = 10.5.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.6.sp,
    )
}

/**
 * One log row. Collapsed it shows the meta line plus a 3-line-clamped message; [expanded] lifts the
 * clamp and reveals "Copy entry", which puts the REDACTED message on the clipboard. Tapping the row
 * calls [onToggleExpanded]; [isLast] drops the trailing hairline (the design's `last` prop);
 * [zone] renders the timestamp.
 */
@Composable
fun DiagnosticsLogRow(
    entry: DiagnosticsLogEntry,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    modifier: Modifier = Modifier,
    isLast: Boolean = false,
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val tokens = LocalDiagnosticsTokens.current
    val levelColor = tokens.levelColor(entry.level)
    val time = remember(entry.timeMillis, zone) {
        TIME_FORMAT.format(Instant.ofEpochMilli(entry.timeMillis).atZone(zone))
    }
    val category = remember(entry.category) { DiagnosticsCategoryBounding.chipFor(entry.category) }

    Column(
        modifier
            .fillMaxWidth()
            .background(if (expanded) tokens.expandedRow else Color.Transparent)
            .clickable(onClick = onToggleExpanded)
            .testTag(DiagnosticsRowTags.ROW),
    ) {
        Column(Modifier.padding(start = 18.dp, end = 18.dp, top = 9.dp, bottom = 10.dp)) {
            // The design aligns the meta line on the TEXT BASELINE (`alignItems: 'baseline'`), which
            // matters here because its three elements are three different sizes (10.5 / 10 / 9.5sp);
            // centering them would leave the timestamp and the level token visibly astride.
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    time,
                    modifier = Modifier
                        .alignByBaseline()
                        .testTag(DiagnosticsRowTags.TIME),
                    color = tokens.sub,
                    fontFamily = DiagnosticsFonts.Mono,
                    fontSize = 10.5.sp,
                )
                Text(
                    levelToken(entry.level),
                    modifier = Modifier
                        .alignByBaseline()
                        .testTag(DiagnosticsRowTags.LEVEL)
                        .semantics { diagnosticsColor = levelColor.toArgb() },
                    color = levelColor,
                    fontFamily = DiagnosticsFonts.Sans,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.8.sp,
                )
                Text(
                    category,
                    modifier = Modifier
                        .alignByBaseline()
                        .clip(RoundedCornerShape(4.dp))
                        .background(tokens.pill)
                        .padding(horizontal = 6.dp, vertical = 1.5.dp)
                        .testTag(DiagnosticsRowTags.CATEGORY),
                    color = tokens.sub,
                    fontFamily = DiagnosticsFonts.Mono,
                    fontSize = 9.5.sp,
                )
            }
            Text(
                entry.message,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp)
                    .testTag(DiagnosticsRowTags.MESSAGE),
                color = tokens.ink,
                fontFamily = DiagnosticsFonts.Mono,
                fontSize = DiagnosticsRowMetrics.MESSAGE_SIZE,
                lineHeight = DiagnosticsRowMetrics.MESSAGE_LINE_HEIGHT,
                maxLines = if (expanded) Int.MAX_VALUE else DiagnosticsRowMetrics.COLLAPSED_MAX_LINES,
                overflow = TextOverflow.Ellipsis,
            )
            if (expanded) {
                CopyEntryButton(message = entry.message, tokens = tokens)
            }
        }
        if (!isLast) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(tokens.rule)
                    .testTag(DiagnosticsRowTags.DIVIDER),
            )
        }
    }
}

/**
 * The expanded row's single action. It writes `redact(message)` — never [message] itself — and
 * exposes no callback through which a caller could substitute the payload, so the redaction cannot
 * be bypassed through this component's API. (It is NOT, and cannot be, a guarantee about code that
 * does not exist yet: a future share/upload path is a NEW egress and owes its own redaction —
 * Gate-4 round 1 was right that the earlier wording overstated this.)
 *
 * Uses the platform [ClipboardManager] (the house pattern — `ReaderActivity.copyFingerprint`) rather
 * than Compose's `LocalClipboardManager`, which is deprecated on the resolved Compose classpath.
 * No confirmation toast: the OS shows its own copy confirmation, and inventing one is rule-51 UI.
 */
@Composable
private fun CopyEntryButton(message: String, tokens: DiagnosticsTokens) {
    val context = LocalContext.current
    Row(
        Modifier
            .padding(top = 9.dp)
            .clip(RoundedCornerShape(percent = 50))
            .border(0.5.dp, tokens.rule, RoundedCornerShape(percent = 50))
            .clickable {
                val clipboard =
                    context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(
                    ClipData.newPlainText(
                        CLIP_LABEL,
                        DiagnosticsRedactor.redact(message),
                    ),
                )
            }
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .testTag(DiagnosticsRowTags.COPY),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(
            Icons.Outlined.ContentCopy,
            contentDescription = null,
            tint = tokens.accent,
            modifier = Modifier.size(11.dp),
        )
        Text(
            "Copy entry",
            color = tokens.accent,
            fontFamily = DiagnosticsFonts.Sans,
            fontSize = 11.5.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
