// Purpose: feature #142 WI-3, Gate-4 round 1 (M3) — closes the gap between "the builders emit the
// right JS" (FoliateAnnotationJsTest) and "the bridge injects the builders' output". Those are
// different claims, and only the second one is what the WebView actually runs: with the builders
// pinned but the bridge untested, `addAnnotation(cfi, cssColor) = eval(foliateAddAnnotationJs(cssColor,
// cfi))` — arguments swapped — passed the entire suite. The auditor named exactly that mutation.
//
// Robolectric's ShadowWebView records the last evaluated JS, so this runs on the JVM with no emulator.
package com.vreader.app.reader.foliate

import android.webkit.WebView
import androidx.test.core.app.ApplicationProvider
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class FoliateBridgeAnnotationCallsTest {

    private lateinit var webView: WebView
    private lateinit var scope: CoroutineScope
    private lateinit var bridge: FoliateBridge

    @Before
    fun setUp() {
        webView = WebView(ApplicationProvider.getApplicationContext())
        // A virtual-time dispatcher: the bridge's goTo collector starts eagerly, and no probe timeout
        // fires unless a test advances the scheduler (none does).
        scope = CoroutineScope(UnconfinedTestDispatcher())
        bridge = FoliateBridge(
            webView = webView,
            assetLoader = WebViewAssetLoader.Builder().build(),
            scope = scope,
        )
    }

    @After
    fun tearDown() {
        scope.cancel()
    }

    private fun lastJs(): String? = shadowOf(webView).lastEvaluatedJavascript

    /** A CFI and a colour that are impossible to confuse for one another — the whole point. */
    private val cfi = "epubcfi(/6/12!/4/2,/1:0,/1:9)"
    private val color = "#5c8fc4"

    @Test
    fun addAnnotation_injectsExactlyTheBuilderOutput_withTheArgumentsInThatOrder() {
        bridge.addAnnotation(cfi, color)
        assertEquals(foliateAddAnnotationJs(cfi, color), lastJs())
        // Explicit anti-mutation guard: the swapped call is a DIFFERENT string, so the equality above
        // genuinely discriminates argument order rather than merely "some builder was called".
        assertNotEquals(foliateAddAnnotationJs(color, cfi), lastJs())
    }

    @Test
    fun deleteAnnotation_injectsExactlyTheBuilderOutput() {
        bridge.deleteAnnotation(cfi)
        assertEquals(foliateDeleteAnnotationJs(cfi), lastJs())
        // …and not the ADD builder, which is the neighbouring copy-paste mistake.
        assertNotEquals(foliateAddAnnotationJs(cfi, color), lastJs())
    }

    @Test
    fun deselect_injectsExactlyTheBuilderOutput() {
        bridge.deselect()
        assertEquals(foliateDeselectJs(), lastJs())
    }

    @Test
    fun setStyles_stillInjectsItsOwnBuilder_afterTheEscaperWasConsolidated() {
        // #142 WI-3 pointed foliateSetStylesJs at the shared foliateJsString seam; this pins that the
        // #129 behaviour is unchanged at the bridge boundary.
        val css = "html, body { font-size: 18px !important; }"
        bridge.setStyles(css)
        assertEquals(foliateSetStylesJs(css), lastJs())
    }

    @Test
    fun aHostileCfi_reachesTheWebViewEscaped_notRaw() {
        // The end-to-end statement of this WI's security claim, asserted at the boundary that matters.
        val hostile = """x"});readerAPI.destroy();({"value":"y"""
        bridge.addAnnotation(hostile, color)
        val js = requireNotNull(lastJs())
        assertEquals(foliateAddAnnotationJs(hostile, color), js)
        // Exactly four unescaped delimiters (value open/close, color open/close): every interior quote
        // is backslash-prefixed, so the hostile payload never becomes syntax.
        val unescaped = js.withIndex().count { (i, c) -> c == '"' && (i == 0 || js[i - 1] != '\\') }
        assertEquals("hostile CFI broke out of its literal:\n$js", 4, unescaped)
    }

    @Test
    fun evalForResult_injectsTheJs_andDropsItsCallbackAfterDestroy() {
        // The lifecycle contract at the real boundary: destroy() tears the dispatcher down, so a result
        // the WebView delivers afterwards must not reach the caller (the #165 WI-7 class).
        val results = mutableListOf<String?>()
        val probe = "(function(){return 1})()"
        bridge.evalForResult(probe, timeoutMs = 60_000) { results += it }
        assertEquals(probe, lastJs())

        bridge.destroy()
        // ShadowWebView never invokes the ValueCallback on its own; a post-destroy probe must also be
        // refused outright, which is the observable half here.
        bridge.evalForResult("(function(){return 2})()", timeoutMs = 60_000) { results += it }
        assertEquals("no JS may be injected after destroy()", probe, lastJs())
        assertEquals(emptyList<String?>(), results)
    }
}
