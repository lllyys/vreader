// Purpose: feature #129 WI-3 (#110 Phase 3) — the designed reader bottom chrome
// (vreader-reader.jsx ReaderBottomChrome): an interactive progress scrubber (track + fill + centered
// thumb + "Page N / M pages left" labels, tap/drag → onScrub) and a toolbar. Per #129 scope (Gate-2 —
// omit non-functional slots, the LibraryScreen precedent, no dead placeholders) the toolbar ships ONLY
// the "Display" (Aa) slot, which opens the WI-2 ReaderSettingsSheet; Contents / Notes / AI are added by
// feature F / D later. Renders in the active [ReaderTheme]'s colors (chrome = the theme background +
// a top rule — a local mapping of the design's chrome/rule tokens). Pure function of state + callbacks.
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The reader bottom chrome. [progress] is 0..1; [displayPage]/[totalPages] drive the scrubber labels
 * (pass totalPages <= 0 to hide them for hosts without paging). [onScrub] is invoked with the tapped/
 * dragged fraction (0..1) — the host WI wires it to the reader's seek. [onOpenDisplay] opens the Display
 * settings sheet. Renders in [theme]'s colors.
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

            // Toolbar — Display only (Contents/Notes/AI omitted until F/D, no dead placeholders).
            Row(Modifier.fillMaxWidth().padding(top = 14.dp, start = 12.dp, end = 12.dp), horizontalArrangement = Arrangement.Center) {
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

@Composable
private fun ChromeLabel(text: String, color: Color) {
    Text(text, color = color, fontSize = 11.sp, fontFamily = VReaderFonts.Sans)
}
