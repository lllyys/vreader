// Purpose: feature #137 WI-6b + WI-7a (#110 Phase 3, box E) — the designed page-turn AFFORDANCES for the
// paged TXT/MD body (TxtPagedBody): the 30/40/30 tap-zones + the first-open discoverability hint, faithful
// to the committed design (dev-docs/designs/vreader-fidelity-v1/project/vreader-tap-zones.jsx +
// vreader-reader.jsx `handleTap`). Two pieces:
//
//   • [Modifier.pagedTapZones] — ONE awaitEachGesture classifier over the pager that owns the page-turn
//     tap-zones, the pager swipe coexistence, AND (WI-7a) the paged text-selection long-press-drag — a
//     single recognizer, never two racing ones (Gate-4 R1 Critical). Per gesture exactly one branch wins:
//     LONG-PRESS → source selection (begin+drag+finalize, never a page turn); SWIPE → the HorizontalPager
//     turns the page natively; SETTLED TAP → tap-to-edit first (suppresses navigation iff a highlight is
//     hit), else the zones — LEFT 30% → prev, RIGHT 30% → next (RTL swaps), CENTER 40% → the host's chrome
//     toggle. The tap's up is CONSUMED so the pager does not re-process it as a zero-distance drag.
//
//   • [TapZoneHint] — the first-open overlay (vreader-tap-zones.jsx:11 `TapZoneHint`): three zones
//     (flex 3/4/3 = 30/40/30) with a chevron-back "TAP TO GO BACK", a dot "TAP TO TOGGLE CONTROLS", and a
//     chevron-forward "TAP TO ADVANCE". It is a pointerEvents:none overlay (no pointerInput → never steals
//     a tap), fades in ~220ms, holds ~2.5s, fades out ~400ms, then fires [onDone]. Shown ONCE per install
//     (the persisted `ReaderSettingsStore.tapHintSeen` gate lives in the caller); dismissed on the first
//     interaction (the caller lowers `visible` + persists on any tap).
//
// @coordinates-with: TxtReaderBody.kt (TxtPagedBody applies [pagedTapZones] to the pager + wires the
//   selection callbacks to its TxtSelectionController + renders [TapZoneHint] gated by the persisted flag),
//   TxtSelectionController.kt (the source-range selection this classifier's long-press-drag drives),
//   reader/settings/ReaderSettingsStore.kt (tapHintSeen/markTapHintSeen — the persistence). NO invented UI
//   — every visual mirrors vreader-tap-zones.jsx (rule 51).
package com.vreader.app.reader.paged

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

/** The 30/40/30 split (vreader-tap-zones.jsx flex 3/4/3, vreader-reader.jsx `x < w*0.3 / x > w*0.7`). */
private const val LEFT_ZONE_FRACTION = 0.30f
private const val RIGHT_ZONE_FRACTION = 0.70f

/**
 * Attach the designed 30/40/30 tap-zone page-turn gesture (feature #137 WI-6b) + the WI-7a paged
 * text-selection classifier as ONE `awaitEachGesture` recognizer (Gate-4 R1 Critical: two nested
 * recognizers race + double-fire). Per gesture, exactly one branch wins:
 *
 *   • LONG-PRESS → SELECTION. [onSelectLongPress] begins a source selection at the press point, then the
 *     drag stream extends it via [onSelectDragTo]; a completed drag/up calls [onSelectFinalize], a cancel
 *     calls [onSelectCancel]. A long-press NEVER turns a page or toggles chrome.
 *   • SWIPE (a horizontal drag before the long-press timeout) → the HorizontalPager turns the page
 *     natively: `awaitLongPressOrCancellation` returns null WITHOUT this recognizer consuming, so the
 *     pager's own drag handling wins. No zone action fires.
 *   • SETTLED TAP → tap-to-edit FIRST ([onTapForEdit] returns true iff a highlight handled it) — if
 *     handled, NO zone navigation runs. Otherwise the tap resolves to a zone by its x fraction:
 *       – LEFT 30%  → [onPrevPage],  RIGHT 30% → [onNextPage]  (RTL swaps prev/next),
 *       – CENTER 40% → [onToggleChrome] (the host's EXISTING chrome toggle — no new chrome).
 *
 * ANY down first fires [onFirstInteraction] so the first-open hint dismisses on the first touch.
 * Keyed on [isRtl] only (the pointerInput does not restart on recomposition); the caller hands STABLE
 * trampolines to the live closures (rememberUpdatedState).
 */
fun Modifier.pagedTapZones(
    onPrevPage: () -> Unit,
    onNextPage: () -> Unit,
    onToggleChrome: () -> Unit,
    onFirstInteraction: () -> Unit,
    isRtl: Boolean = false,
    // feature #137 WI-7a — the unified selection branch (defaulted to no-ops so a caller without a
    // selection controller behaves exactly like the WI-6b tap-only classifier).
    onSelectLongPress: (Offset) -> Unit = {},
    onSelectDragTo: (Offset) -> Unit = {},
    onSelectFinalize: () -> Unit = {},
    onSelectCancel: () -> Unit = {},
    // Returns true iff the tap landed on an existing highlight (tap-to-edit) → suppress zone navigation.
    onTapForEdit: (Offset) -> Boolean = { false },
): Modifier = this.pointerInput(isRtl) {
    val longPressTimeout = viewConfiguration.longPressTimeoutMillis
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        onFirstInteraction()
        // Race the long-press timeout against a pointer up/cancel: a fast up = TAP (zones/edit); the timeout
        // firing (null) = LONG-PRESS (selection); a cancel (swipe → the pager consumed the drag) = null with
        // the pointer gone → the pager already turned, so do nothing.
        val up = withTimeoutOrNull(longPressTimeout) { waitForUpOrCancellation() }
        if (up == null) {
            // Either the LONG-PRESS timeout elapsed (a real long-press) or a swipe cancelled. Distinguish:
            // a still-pressed pointer means a long-press → begin selection + drag; a cancelled pointer means
            // the swipe won (pager handles it) → no-op.
            val current = currentEvent.changes.firstOrNull { it.id == down.id }
            if (current != null && current.pressed && !current.isConsumed) {
                onSelectLongPress(current.position)
                val completed = drag(down.id) { change -> onSelectDragTo(change.position); change.consume() }
                if (completed) onSelectFinalize() else onSelectCancel()
            }
            return@awaitEachGesture
        }
        // A settled TAP. CONSUME its up so the HorizontalPager does not also process the down+up as a
        // zero-distance drag that snaps back to the current page and overrides animateScrollToPage (Gate-4
        // regression: the old detectTapGestures consumed the tap; awaitEachGesture must too).
        up.consume()
        // Tap-to-edit first; if a highlight handled the tap, suppress navigation.
        if (onTapForEdit(down.position)) return@awaitEachGesture
        val w = size.width.toFloat()
        if (w <= 0f) return@awaitEachGesture
        when {
            down.position.x < w * LEFT_ZONE_FRACTION -> (if (isRtl) onNextPage else onPrevPage)()
            down.position.x > w * RIGHT_ZONE_FRACTION -> (if (isRtl) onPrevPage else onNextPage)()
            else -> onToggleChrome()   // center 40% → reuse the host's existing chrome toggle
        }
    }
}

/** The hint's animation timeline (vreader-tap-zones.jsx:14 — enter 220ms, hold 2500ms, exit 400ms). */
private const val HINT_ENTER_MS = 220
private const val HINT_HOLD_MS = 2500L
private const val HINT_EXIT_MS = 400

/**
 * The first-open tap-zone discoverability hint (feature #137 WI-6b), faithful to vreader-tap-zones.jsx
 * `TapZoneHint`: three flex 3/4/3 zones — a chevron-back "TAP TO GO BACK" (accent), a dot
 * "TAP TO TOGGLE CONTROLS" (muted), a chevron-forward "TAP TO ADVANCE" (accent). A NON-interactive overlay
 * (no pointerInput → the design's `pointerEvents: none`, so it never steals a tap). While [visible] it
 * fades in, holds ~2.5s, fades out, then fires [onDone] (the auto-dismiss). The caller ALSO lowers
 * [visible] on the first interaction (both paths converge on [onDone], which persists the seen flag).
 */
@Composable
fun TapZoneHint(
    theme: ReaderTheme,
    visible: Boolean,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Stage timeline mirrors the design: hidden → enter → hold → exit → hidden (+ onDone).
    var stage by remember(visible) { mutableStateOf(if (visible) HintStage.Enter else HintStage.Hidden) }
    LaunchedEffect(visible) {
        if (!visible) { stage = HintStage.Hidden; return@LaunchedEffect }
        stage = HintStage.Enter
        delay(HINT_ENTER_MS.toLong())
        stage = HintStage.Hold
        delay(HINT_HOLD_MS)
        stage = HintStage.Exit
        delay(HINT_EXIT_MS.toLong())
        stage = HintStage.Hidden
        onDone()
    }
    if (stage == HintStage.Hidden) return

    val target = if (stage == HintStage.Enter || stage == HintStage.Hold) 1f else 0f
    val durationMs = if (stage == HintStage.Enter) HINT_ENTER_MS else HINT_EXIT_MS
    val alpha by animateFloatAsState(target, tween(durationMs, easing = LinearEasing), label = "tap-hint-alpha")

    val sub = theme.ink.copy(alpha = 0.6f)
    val baseTint = if (theme.isDark) Color.White.copy(alpha = 0.06f) else Color.Black.copy(alpha = 0.04f)
    val accentTint = theme.accent.copy(alpha = if (theme.isDark) 0.16f else 0.10f)

    // The disc bg (vreader-tap-zones.jsx:53): `t.isDark ? 'rgba(0,0,0,0.45)' : 'rgba(255,255,255,0.65)'`
    // — a DARK disc on a dark theme, a WHITE disc on a light theme.
    val discBg = if (theme.isDark) Color.Black.copy(alpha = 0.45f) else Color.White.copy(alpha = 0.65f)

    Row(
        modifier
            .fillMaxSize()
            .testTag("tap-zone-hint")
            .alpha(alpha),   // the design's non-interactive `opacity` on the pointerEvents:none hint
    ) {
        HintZone(
            weight = 3f, tint = accentTint, discBg = discBg, glyph = {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null, tint = theme.accent, modifier = Modifier.size(30.dp))
            },
            label = "TAP TO GO BACK", labelColor = theme.ink,
        )
        HintZone(
            weight = 4f, tint = baseTint, discBg = discBg, glyph = {
                Box(Modifier.size(8.dp).clip(CircleShape).background(sub))
            },
            label = "TAP TO TOGGLE CONTROLS", labelColor = theme.ink,
        )
        HintZone(
            weight = 3f, tint = accentTint, discBg = discBg, glyph = {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = theme.accent, modifier = Modifier.size(30.dp))
            },
            label = "TAP TO ADVANCE", labelColor = theme.ink,
        )
    }
}

private enum class HintStage { Hidden, Enter, Hold, Exit }

/** One hint zone (vreader-tap-zones.jsx:42 `HintZone`): a tinted column with a glyph disc + an uppercase
 *  centred label. */
@Composable
private fun androidx.compose.foundation.layout.RowScope.HintZone(
    weight: Float,
    tint: Color,
    discBg: Color,
    glyph: @Composable () -> Unit,
    label: String,
    labelColor: Color,
) {
    Column(
        Modifier
            .weight(weight)
            .fillMaxSize()
            .background(tint)
            .padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier.size(56.dp).clip(CircleShape).background(discBg),
            contentAlignment = Alignment.Center,
        ) { glyph() }
        androidx.compose.foundation.layout.Spacer(Modifier.size(12.dp))
        Text(
            text = label,
            color = labelColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.4.sp,
            textAlign = TextAlign.Center,
        )
    }
}
