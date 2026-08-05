// Purpose: feature #129 WI-3 (#110 Phase 3), extended by feature #132 WI-5 — the designed reader bottom
// chrome (vreader-reader.jsx ReaderBottomChrome): an interactive progress scrubber (track + fill +
// centered thumb + "Page N / M pages left" labels, tap/drag → onScrub) and a toolbar. #129 shipped the
// "Display" (Aa) slot (opens the WI-2 ReaderSettingsSheet) plus an optional host-provided extraSlot
// (WI-4: the TXT/MD read-aloud entry). #132 WI-5 un-omits the design's "Contents" and "Notes" toolbar
// slots as nullable-default params (onOpenContents / onOpenNotes) — each renders ONLY when non-null, so
// a #129-era Display-only caller stays valid by construction (the no-dead-controls rule). The design
// toolbar order is Contents · Notes · Display · AI; AI stays omitted until feature D. feature #140 WI-6
// promotes [ToolbarIconButton] to `internal` so the AZW3 host's Contents/Notes-only bottom chrome
// (Azw3BottomChrome) renders the SAME designed slot rather than a look-alike copy. Renders in the
// active [ReaderTheme]'s colors (chrome = the theme background + a top rule — a local mapping of the
// design's chrome/rule tokens). Pure function of state + callbacks.
package com.vreader.app.reader.chrome

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The reader bottom chrome. [progress] is 0..1; [displayPage]/[totalPages] drive the scrubber labels
 * (pass totalPages <= 0 to hide them for hosts without paging). [onScrub] is invoked with the tapped/
 * dragged fraction (0..1) — the host WI wires it to the reader's seek. [onOpenContents] opens the
 * Contents (TOC) sheet and [onOpenNotes] the Notes (annotations) sheet — each control renders ONLY when
 * its callback is non-null (a null one is omitted, never a dead control; #132 WI-5). [onOpenDisplay]
 * opens the Display settings sheet. [extraSlot] is an optional host-provided toolbar slot rendered
 * before the design slots (the TXT/MD read-aloud entry — the vreader-tts.jsx TtsEntry toolbar item).
 * Renders in [theme]'s colors.
 */
@Composable
fun ReaderBottomChrome(
    theme: ReaderTheme,
    progress: Float,
    displayPage: Int,
    totalPages: Int,
    onScrub: (Float) -> Unit,
    onOpenDisplay: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenContents: (() -> Unit)? = null,
    onOpenNotes: (() -> Unit)? = null,
    extraSlot: (@Composable () -> Unit)? = null,
) {
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val rule = theme.ink.copy(alpha = 0.10f)
    val accent = theme.accent
    val safeProgress = progress.coerceIn(0f, 1f)

    Column(
        modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("reader-bottom-chrome"),
    ) {
        // Top rule (the design's chrome divider).
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(rule))

        Column(Modifier.padding(top = 14.dp, bottom = 28.dp)) {
            // Scrubber — tap or drag anywhere on the row seeks.
            Column(Modifier.padding(horizontal = 22.dp)) {
                BoxWithConstraints(
                    Modifier
                        .fillMaxWidth()
                        .height(24.dp)
                        .testTag("scrubber-track")
                        .pointerInput(Unit) {
                            detectTapGestures { o -> onScrub((o.x / size.width).coerceIn(0f, 1f)) }
                        }
                        .pointerInput(Unit) {
                            detectHorizontalDragGestures { change, _ -> onScrub((change.position.x / size.width).coerceIn(0f, 1f)) }
                        },
                    contentAlignment = Alignment.CenterStart,
                ) {
                    val trackWidth = maxWidth
                    Box(Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(rule))
                    Box(Modifier.fillMaxWidth(safeProgress).height(3.dp).clip(RoundedCornerShape(2.dp)).background(accent))
                    // Thumb: its CENTER sits at trackWidth * progress (offset by -half the thumb).
                    Box(
                        Modifier
                            .offset(x = trackWidth * safeProgress - 7.dp)
                            .size(14.dp)
                            .clip(CircleShape)
                            .background(accent)
                            .testTag("scrubber-thumb"),
                    )
                }
                if (totalPages > 0) {
                    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        ChromeLabel("Page $displayPage", sub)
                        ChromeLabel("${(totalPages - displayPage).coerceAtLeast(0)} pages left in book", sub)
                    }
                }
            }

            // Toolbar — the design order Contents · Notes · Display · AI. #132 un-omits Contents/Notes
            // (each rendered ONLY when its callback is non-null — no dead controls). AI stays omitted
            // until feature D. [extraSlot] (the TTS entry) precedes the design slots.
            Row(Modifier.fillMaxWidth().padding(top = 14.dp, start = 12.dp, end = 12.dp), horizontalArrangement = Arrangement.Center) {
                extraSlot?.invoke()
                if (onOpenContents != null) {
                    ToolbarIconButton(
                        tag = "chrome-contents", label = "Contents", icon = Icons.AutoMirrored.Filled.FormatListBulleted,
                        ink = ink, sub = sub, onClick = onOpenContents,
                    )
                }
                if (onOpenNotes != null) {
                    ToolbarIconButton(
                        tag = "chrome-notes", label = "Notes", icon = Icons.Outlined.BorderColor,
                        ink = ink, sub = sub, onClick = onOpenNotes,
                    )
                }
                // Display — the #129 slot, rendered with the design's "Aa" serif glyph rather than an icon.
                Column(
                    Modifier.clickable { onOpenDisplay() }.padding(horizontal = 12.dp, vertical = 4.dp).testTag("chrome-display"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text("Aa", color = ink, fontFamily = VReaderFonts.Serif, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    Text("Display", color = sub, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

/**
 * One toolbar slot — the design's icon-above-label button (`vreader-reader.jsx` toolbar `<b.icon/> +
 * <span>`). A 22dp icon over the 10sp label, both tinted from the theme, in a tappable column tagged
 * for tests. The [label] is on the tappable node's semantics so accessibility + tests can target it.
 *
 * `internal` rather than private (feature #140 WI-6): the AZW3 host's own bottom chrome
 * (`Azw3BottomChrome`) renders a Contents/Notes subset of this toolbar without the scrubber or the
 * Display slot, and reuses THIS composable so its slot treatment cannot drift from the EPUB/TXT one.
 * It is not part of any public API — module-visible only, for that one sibling.
 */
@Composable
internal fun ToolbarIconButton(
    tag: String,
    label: String,
    icon: ImageVector,
    ink: Color,
    sub: Color,
    onClick: () -> Unit,
) {
    Column(
        Modifier
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 4.dp)
            .testTag(tag)
            .semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(22.dp))
        Text(label, color = sub, fontSize = 10.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun ChromeLabel(text: String, color: Color) {
    Text(text, color = color, fontSize = 11.sp, fontFamily = VReaderFonts.Sans)
}
