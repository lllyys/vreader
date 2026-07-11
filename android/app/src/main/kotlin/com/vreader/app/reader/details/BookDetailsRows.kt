// Purpose: feature #134 WI-4 — the Book Details sheet's individual pieces (design
// `vreader-book-details.jsx` `DetailsStacked`): the centered title/author block, the tag chips, the
// `MetaList` card of `Format/Size/Pages/Fingerprint/Location` rows, and the `ActionList` (Share only).
// Each meta row is ABSENT when its model value is null/empty — no invented/dead rows (§details-source,
// §page-count, §location; Design-gate #1: no cover art / placeholder / Export). The copy-fingerprint
// mini-action carries the FULL canonical key (§fingerprint); Location is a read-only label with no
// mini-action. Reuses the [ReaderTheme] token map (ink/accent/isDark → the design's ink/sub/rule/mono
// tokens), the same posture as MorePopup / AnnotationsReviewSheet. Pure function of state (rule 50 §4).
package com.vreader.app.reader.details

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/** The design's secondary-text token (`t.sub`) derived from [ReaderTheme.ink]. */
internal fun ReaderTheme.subColor(): Color = ink.copy(alpha = 0.62f)

/** The design's hairline divider token (`t.rule`) derived from [ReaderTheme.ink]. */
internal fun ReaderTheme.ruleColor(): Color = ink.copy(alpha = if (isDark) 0.10f else 0.08f)

/** The `MetaList`/`ActionList` card surface (`t.isDark ? rgba(255,255,255,0.04) : #fff`). */
internal fun ReaderTheme.cardColor(): Color =
    if (isDark) Color(0x0AFFFFFF) else Color(0xFFFFFFFF)

/**
 * The centered title/author block (design `DetailsStacked` head). The title is a serif italic; the
 * [author] line is OMITTED entirely when null (no dangling `·` separator / placeholder — §details-source).
 */
@Composable
internal fun BookTitleBlock(theme: ReaderTheme, title: String, author: String?) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            title,
            modifier = Modifier.padding(bottom = 6.dp).testTag("details-title"),
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontStyle = FontStyle.Italic,
            fontWeight = FontWeight.SemiBold,
            fontSize = 22.sp,
            textAlign = TextAlign.Center,
        )
        if (author != null) {
            Text(
                author,
                modifier = Modifier.testTag("details-author"),
                color = theme.subColor(),
                fontFamily = VReaderFonts.Sans,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * The tag-chip row (design `book.tags`) = collection names. The whole row is OMITTED when [tags] is empty
 * (§details-source). Each chip is a rounded, tinted pill.
 */
@Composable
internal fun BookTagChips(theme: ReaderTheme, tags: List<String>) {
    if (tags.isEmpty()) return
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 4.dp)
            .testTag("details-tags"),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        tags.forEach { tag ->
            Text(
                tag,
                modifier = Modifier
                    .clip(RoundedCornerShape(100))
                    .background(theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f))
                    .padding(horizontal = 10.dp, vertical = 3.dp),
                color = theme.ink,
                fontFamily = VReaderFonts.Sans,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * The `MetaList` card (design `Format/Size/Pages/Fingerprint/Location`). Each row is present ONLY when its
 * model value is non-null: [pagesLabel]/[locationLabel] may be null → those rows are omitted. The
 * Fingerprint row carries the copy mini-action (payload = [fingerprintFull], the FULL key — §fingerprint);
 * the Location row is a plain read-only label (no reveal/download mini-action — §location).
 */
@Composable
internal fun BookMetaList(
    theme: ReaderTheme,
    formatLabel: String,
    sizeLabel: String,
    pagesLabel: String?,
    fingerprintDisplay: String,
    fingerprintFull: String,
    locationLabel: String?,
    onCopyFingerprint: (String) -> Unit,
) {
    // The rows to render, in design order, filtering out the absent optionals.
    data class Meta(val label: String, val value: String, val copyPayload: String?)
    val rows = buildList {
        add(Meta("Format", formatLabel, null))
        add(Meta("Size", sizeLabel, null))
        if (pagesLabel != null) add(Meta("Pages", pagesLabel, null))
        add(Meta("Fingerprint", fingerprintDisplay, fingerprintFull))
        if (locationLabel != null) add(Meta("Location", locationLabel, null))
    }

    Column(Modifier.fillMaxWidth().padding(top = 22.dp)) {
        SectionLabel(theme, "Metadata")
        Column(
            Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(theme.cardColor()),
        ) {
            rows.forEachIndexed { index, meta ->
                MetaRow(
                    theme = theme,
                    label = meta.label,
                    value = meta.value,
                    copyPayload = meta.copyPayload,
                    onCopyFingerprint = onCopyFingerprint,
                    showDivider = index != rows.lastIndex,
                )
            }
        }
    }
}

/**
 * One meta row: a fixed-width label + a monospace value (+ an optional copy mini-action when
 * [copyPayload] is non-null → the Fingerprint row). testTag `details-meta-<label-lowercased>`.
 */
@Composable
private fun MetaRow(
    theme: ReaderTheme,
    label: String,
    value: String,
    copyPayload: String?,
    onCopyFingerprint: (String) -> Unit,
    showDivider: Boolean,
) {
    val slug = label.lowercase()
    Column(Modifier.fillMaxWidth().testTag("details-meta-$slug")) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                label,
                modifier = Modifier.width(96.dp),
                color = theme.subColor(),
                fontFamily = VReaderFonts.Sans,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            )
            Text(
                value,
                modifier = Modifier.weight(1f),
                color = theme.ink,
                fontFamily = FontFamily.Monospace,
                fontSize = 13.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (copyPayload != null) {
                Box(
                    Modifier
                        .size(26.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f))
                        .clickable { onCopyFingerprint(copyPayload) }
                        .testTag("details-copy-fingerprint")
                        .semantics { contentDescription = "Copy fingerprint" },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Outlined.ContentCopy,
                        contentDescription = null,
                        tint = theme.subColor(),
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
        if (showDivider) {
            Spacer(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 14.dp)
                    .height(0.5.dp)
                    .background(theme.ruleColor()),
            )
        }
    }
}

/**
 * The `ActionList` card (design `ActionList`, Share ONLY — Export + cover-edit omitted). One tappable
 * row: an icon tile + label + chevron. testTag `details-share`.
 */
@Composable
internal fun BookActionList(theme: ReaderTheme, onShare: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 22.dp)) {
        SectionLabel(theme, "Actions")
        Column(
            Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(theme.cardColor()),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onShare)
                    .testTag("details-share")
                    .semantics { contentDescription = "Share book" }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    Modifier
                        .size(28.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(theme.ink.copy(alpha = if (theme.isDark) 0.05f else 0.04f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.Share,
                        contentDescription = null,
                        tint = theme.ink,
                        modifier = Modifier.size(15.dp),
                    )
                }
                Text(
                    "Share book…",
                    modifier = Modifier.weight(1f),
                    color = theme.ink,
                    fontFamily = VReaderFonts.Sans,
                    fontSize = 14.5.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}

/** A section header (design `SectionLabel`): small, tracked, muted uppercase-ish label. */
@Composable
private fun SectionLabel(theme: ReaderTheme, text: String) {
    Text(
        text,
        modifier = Modifier.widthIn().padding(start = 2.dp),
        color = theme.subColor(),
        fontFamily = VReaderFonts.Sans,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
    )
}
