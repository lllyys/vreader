// Purpose: feature #134 WI-4 — the Book Details sheet's individual pieces (design
// `vreader-book-details.jsx` `DetailsStacked`): the centered title/author block, the tag chips (wrapping),
// the `MetaList` card (`Format/Size/Pages/Fingerprint/Location`), and the `ActionList`. Each
// meta/optional row is ABSENT when its model value is null/empty — no invented/dead rows (§details-source,
// §page-count, §location; Design-gate #1: no cover art / placeholder / cover-edit). The copy mini-action
// carries the FULL canonical key (§fingerprint); Location is a read-only label. Reuses the [ReaderTheme]
// token map (ink/accent/isDark → the design's ink/sub/rule/mono), same posture as MorePopup /
// AnnotationsReviewSheet. Pure function of state (rule 50 §4).
//
// feature #165 WI-6 — the `ActionList` now carries Share + an OPTIONAL accent `Import annotations…` row
// (design `vreader-annotation-import.jsx` `BookDetailsActionsCard` variant `B1-paired`) plus that
// variant's merge-policy footnote, both gated on a nullable `onImportAnnotations` (null → neither, no
// dead no-op). The design's paired `Export annotations…` row is still ABSENT: it is
// `BLOCKED: needs-design (#2085)` — export FAILURE feedback has no depicted surface and no shipped
// string that fits (all three of MainActivity's describe import) — and lands in WI-8, which flips
// `AnnotationsIoEntryTest`'s `assertDoesNotExist("details-export-annotations")` in the same commit that
// adds the row. Both rows share the private [ActionRow] geometry so they cannot drift apart.
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
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
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

/**
 * The `ActionList` card. Ships **Share + Import annotations…**; the design's `Replace cover…` row is
 * omitted (Design-gate #1) and its `Export annotations…` row is `BLOCKED: needs-design (#2085)` — no
 * shipped string describes an export *failure*, so WI-8 builds that row once the design lands.
 *
 * [onImportAnnotations] is capability-gated (#134's nullable-callback pattern): null renders **no Import
 * row and no footnote** rather than a dead no-op, so a host that has not wired annotation import shows
 * exactly the Share-only card #134 shipped. When non-null the card renders the accent Import row
 * (`vreader-annotation-import.jsx:321-323`, variant `B1-paired`) plus that variant's merge-policy
 * footnote (`:332-339`) verbatim beneath the card.
 */
@Composable
internal fun BookActionList(
    theme: ReaderTheme,
    onShare: () -> Unit,
    onImportAnnotations: (() -> Unit)? = null,
) {
    Column(Modifier.fillMaxWidth().padding(top = 22.dp)) {
        SectionLabel(theme, "Actions")
        Column(
            Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(theme.cardColor()),
        ) {
            ActionRow(
                theme = theme,
                icon = Icons.Filled.Share,
                label = "Share book…",
                tag = "details-share",
                accessibilityLabel = "Share book",
                accent = false,
                // The design's `last` row carries no bottom rule — Share is last only without Import.
                showDivider = onImportAnnotations != null,
                onClick = onShare,
            )
            if (onImportAnnotations != null) {
                ActionRow(
                    theme = theme,
                    icon = Icons.Outlined.FileUpload,
                    label = "Import annotations…",
                    tag = "details-import-annotations",
                    accessibilityLabel = "Import annotations",
                    accent = true,
                    showDivider = false,
                    onClick = onImportAnnotations,
                )
            }
        }
        if (onImportAnnotations != null) {
            // B1-paired's merge-policy caption, verbatim. It states the non-interactive merge policy the
            // design chose to declare in copy INSTEAD of asking the user, so it ships with the row.
            Text(
                "Imports merge into this book by passage match; existing notes are not overwritten.",
                modifier = Modifier
                    .padding(top = 8.dp, start = 4.dp, end = 4.dp)
                    .testTag("details-annotations-footnote"),
                // The design's `color: t.sub, opacity: 0.7` — t.sub is ink@0.62, so 0.62 × 0.7.
                color = theme.ink.copy(alpha = 0.62f * 0.7f),
                fontFamily = VReaderFonts.Sans,
                fontSize = 11.sp,
                lineHeight = 15.4.sp,
            )
        }
    }
}

/**
 * One `ActionList` row (design `BDRow`): an icon tile + label + the trailing chevron accessory. [accent]
 * tints the tile background and the label with [ReaderTheme.accent] (the design's `accent` BDRow, tile
 * `${t.accent}1a` ≈ 10% alpha). No `sub` line is ever rendered — §3.3 A-1/A-2 record the design's
 * sub-lines as deliberate ABSENCES (Android ships one export format and no Readwise/Apple-Books
 * importer; rendering those subtitles would be a false affordance).
 */
@Composable
private fun ActionRow(
    theme: ReaderTheme,
    icon: ImageVector,
    label: String,
    tag: String,
    accessibilityLabel: String,
    accent: Boolean,
    showDivider: Boolean,
    onClick: () -> Unit,
) {
    val foreground = if (accent) theme.accent else theme.ink
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .testTag(tag)
                .semantics { contentDescription = accessibilityLabel }
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier
                    .size(28.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(
                        if (accent) theme.accent.copy(alpha = 0.10f)
                        else theme.ink.copy(alpha = if (theme.isDark) 0.05f else 0.04f),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(15.dp))
            }
            Text(
                label,
                modifier = Modifier.weight(1f),
                color = foreground,
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
