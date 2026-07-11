// Purpose: feature #134 WI-4 — the Book Details sheet's individual pieces (design
// `vreader-book-details.jsx` `DetailsStacked`): the centered title/author block, the tag chips (wrapping),
// the `MetaList` card (`Format/Size/Pages/Fingerprint/Location`), and the `ActionList` (Share only). Each
// meta/optional row is ABSENT when its model value is null/empty — no invented/dead rows (§details-source,
// §page-count, §location; Design-gate #1: no cover art / placeholder / Export). The copy mini-action
// carries the FULL canonical key (§fingerprint); Location is a read-only label. Reuses the [ReaderTheme]
// token map (ink/accent/isDark → the design's ink/sub/rule/mono), same posture as MorePopup /
// AnnotationsReviewSheet. Pure function of state (rule 50 §4).
package com.vreader.app.reader.details

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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

/** The centered title/author block (design `DetailsStacked` head). The [author] line is OMITTED when null. */
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

/** The tag-chip row (design `book.tags` = collection names). OMITTED when [tags] is empty; chips wrap. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BookTagChips(theme: ReaderTheme, tags: List<String>) {
    if (tags.isEmpty()) return
    // FlowRow so multiple/long chips wrap onto new lines (the design's `flexWrap: 'wrap'`), never overflow.
    FlowRow(
        Modifier
            .fillMaxWidth()
            .padding(top = 4.dp)
            .testTag("details-tags"),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(6.dp),
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
 * The `MetaList` card. [pagesLabel]/[locationLabel] rows are omitted when null. The Fingerprint row copies
 * [fingerprintFull] (the FULL key — §fingerprint); the Location row is a read-only label (§location).
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
    // The rows in design order; absent optionals (Pages/Location) are filtered out.
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

/** One meta row: label + monospace value (+ a copy mini-action when [copyPayload] is non-null). */
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

/** The `ActionList` card (Share ONLY — Export + cover-edit omitted): icon tile + label + chevron. */
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
                // The design's trailing chevron accessory (`ActionList` `Icons.Chevron`).
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = theme.subColor(),
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

/** A section header (design `SectionLabel`): small, muted, semibold label. */
@Composable
private fun SectionLabel(theme: ReaderTheme, text: String) {
    Text(
        text,
        modifier = Modifier.padding(start = 2.dp),
        color = theme.subColor(),
        fontFamily = VReaderFonts.Sans,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
    )
}
