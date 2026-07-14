package com.vreader.app.reader

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference

/**
 * feature #131 WI-8 — the TxtSelectionController seams added for the bilingual interlinear host: the
 * translation gesture-EXCLUSION (setExcludedBounds → beginAt short-circuit, round-4 High-2) and the TTS
 * source-VISIBILITY query (isSourceChunkInViewport, round-5/6). Deterministic Compose-rule tests (no
 * gesture recognizer, no emulator timing) that lay out a real source `Text` and register it with the
 * controller, so `hitAt`'s nearest-source-chunk fallback IS reachable — proving the exclusion actually
 * bypasses it (round-4 audit Medium-2), not merely a no-op on an unlaid-out controller.
 */
@RunWith(AndroidJUnit4::class)
class TxtSelectionExclusionTest {

    @get:Rule val compose = createComposeRule()

    /** The FAITHFUL exclusion test (round-4 audit round-2 Medium): the press point is BELOW the source
     *  `Text` bounds — exactly where a translation child would sit — so WITHOUT excluded bounds hitAt's
     *  NEAREST-source-chunk fallback (:47–53) reaches the source and a selection begins; WITH an excluded
     *  rect covering that below-point the begin is a NO-OP. This proves the exclusion bypasses the
     *  fallback, not merely an early return over the source itself. */
    @Test fun setExcludedBounds_suppressesFallbackSelection_belowSource() {
        val doc = TxtDocument.of("Hello world paragraph here.\n")
        val baseline = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val excluded = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val layoutRef = AtomicReference<TextLayoutResult?>(null)
        val srcCoordsRef = AtomicReference<LayoutCoordinates?>(null)
        val rootCoordsRef = AtomicReference<LayoutCoordinates?>(null)

        compose.setContent {
            // A tall root (the "lazy" container) with a short source Text at its TOP; the region BELOW the
            // source (still inside the root) is where a translation child would render. hitAt's fallback
            // resolves a below-source point to the nearest chunk (this one).
            Column(
                Modifier
                    .fillMaxWidth()
                    .height(600.dp)
                    .onGloballyPositioned { rootCoordsRef.set(it) },
            ) {
                Text(
                    text = "Hello world paragraph here.",
                    onTextLayout = { layoutRef.set(it) },
                    modifier = Modifier.onGloballyPositioned { srcCoordsRef.set(it) },
                )
            }
        }
        compose.waitForIdle()
        val layout = requireNotNull(layoutRef.get())
        val srcCoords = requireNotNull(srcCoordsRef.get())
        val rootCoords = requireNotNull(rootCoordsRef.get())
        // A LazyColumn-local point BELOW the source Text (in root-local coords), inside the translation
        // region — outside all source-chunk bounds, so only hitAt's nearest-chunk fallback can hit it.
        val srcBottomLocal = rootCoords.windowToLocal(
            Offset(srcCoords.boundsInWindow().center.x, srcCoords.boundsInWindow().bottom),
        ).y
        val belowPoint = Offset(rootCoords.size.width / 2f, srcBottomLocal + 120f)
        listOf(baseline, excluded).forEach { it.setLazyCoords(rootCoords); it.registerChunk(0, layout, srcCoords) }

        // Baseline: no excluded bounds → the below-source press resolves to the nearest chunk (fallback) + selects.
        baseline.beginAt(belowPoint)
        assertNotNull("baseline: a below-source long-press hits the nearest-chunk fallback + selects", baseline.currentRange())
        // Excluded: a translation rect covering the below region → the begin is a NO-OP (fallback bypassed).
        excluded.setExcludedBounds(
            listOf(
                Rect(
                    left = 0f, top = srcCoords.boundsInWindow().bottom,
                    right = rootCoords.boundsInWindow().right, bottom = rootCoords.boundsInWindow().bottom,
                ),
            ),
        )
        excluded.beginAt(belowPoint)
        assertNull("excluded: a below-source long-press inside a translation rect begins NO selection", excluded.currentRange())
    }

    /** isSourceChunkInViewport returns false for an unregistered/pre-layout chunk (round-6 Low: the safe
     *  default → the host scrolls the source into view rather than falsely believing it visible). */
    @Test fun isSourceChunkInViewport_unregisteredChunk_isNotVisible() {
        val doc = TxtDocument.of("One\nTwo\nThree\n")
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        assertFalse("pre-layout / unregistered chunk counts as not visible", controller.isSourceChunkInViewport(0))
    }

    /** isSourceChunkInViewport returns TRUE for a laid-out chunk whose bounds are inside the lazy
     *  viewport (the positive case the TTS auto-scroll guard relies on). */
    @Test fun isSourceChunkInViewport_laidOutVisibleChunk_isVisible() {
        val doc = TxtDocument.of("Visible source line.\n")
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val layoutRef = AtomicReference<TextLayoutResult?>(null)
        val coordsRef = AtomicReference<LayoutCoordinates?>(null)
        compose.setContent {
            Text(
                text = "Visible source line.",
                onTextLayout = { layoutRef.set(it) },
                modifier = Modifier.onGloballyPositioned { coordsRef.set(it) },
            )
        }
        compose.waitForIdle()
        val layout = requireNotNull(layoutRef.get())
        val coords = requireNotNull(coordsRef.get())
        // Same coords for the lazy root + the chunk → the chunk's bounds intersect the "viewport".
        controller.setLazyCoords(coords)
        controller.registerChunk(0, layout, coords)
        org.junit.Assert.assertTrue("a laid-out chunk inside the viewport is visible", controller.isSourceChunkInViewport(0))
    }
}
