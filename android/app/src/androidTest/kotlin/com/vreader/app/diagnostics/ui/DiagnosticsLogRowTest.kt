package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.sp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.diagnostics.DiagnosticsDayGrouper
import com.vreader.app.diagnostics.DiagnosticsLevel
import com.vreader.app.diagnostics.DiagnosticsLogEntry
import com.vreader.app.diagnostics.DiagnosticsRedactor
import com.vreader.app.diagnostics.IdentifiedDiagnosticsEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.ZoneId

/**
 * Feature #164 WI-6a — the designed log row (`DiagLogRow` / `DiagDayHeader`,
 * `vreader-diagnostics.jsx:249-301`, artboards A1/A2).
 *
 * The load-bearing test here is [copyEntryRedactsTheClipboardWhileTheRowKeepsShowingTheSecret]: the
 * clipboard is an EGRESS (plan section 6.1, iOS parity `DiagnosticsLogView.swift:173`) and must carry
 * `DiagnosticsRedactor.redact(message)`, while the on-screen expansion is NOT egress and must keep
 * showing the message verbatim. Both halves live in ONE method on purpose — as two methods, swapping
 * the two paths would leave both green.
 *
 * Level colors are asserted per level and per theme in SEPARATE methods: `setContent` may be called
 * at most once per test method, so a themed loop throws `IllegalStateException` (#134 precedent, only
 * a connected run catches it).
 */
@RunWith(AndroidJUnit4::class)
class DiagnosticsLogRowTest {

    @get:Rule val compose = createComposeRule()

    private val stamp = Instant.parse("2026-06-10T14:32:07.412Z").toEpochMilli()
    private val utc = ZoneId.of("UTC")

    /**
     * Seeded into the clipboard before every test. A clipboard assertion that only checked "the
     * secret is absent" would pass against a clipboard nothing ever wrote to; the sentinel makes a
     * silently-missing copy fail instead of falsely passing.
     */
    private val sentinel = "SENTINEL-NOTHING-WAS-COPIED"

    private fun clipboardOf(context: Context): ClipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    @Before fun seedClipboardSentinel() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            clipboardOf(context).setPrimaryClip(ClipData.newPlainText("sentinel", sentinel))
        }
    }

    /** The clipboard's current plain text, read on the main thread (the OS requires window focus). */
    private fun clipText(context: Context): String? = compose.runOnIdle {
        clipboardOf(context).primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(context)
            ?.toString()
    }

    private fun entry(
        level: DiagnosticsLevel = DiagnosticsLevel.ERROR,
        category: String = "Persistence",
        message: String = "Failed to save ReadingSession: CKError 4 (networkUnavailable)",
        timeMillis: Long = stamp,
    ) = DiagnosticsLogEntry(
        timeMillis = timeMillis,
        level = level,
        category = category,
        message = message,
    )

    /** Renders one row under [tokens]; the row is collapsed and inert. */
    private fun showRow(entry: DiagnosticsLogEntry, tokens: DiagnosticsTokens) {
        compose.setContent {
            CompositionLocalProvider(LocalDiagnosticsTokens provides tokens) {
                DiagnosticsLogRow(
                    entry = entry,
                    expanded = false,
                    onToggleExpanded = {},
                    zone = utc,
                )
            }
        }
    }

    private fun assertLevelColor(expected: Int) {
        compose.onNodeWithTag(DiagnosticsRowTags.LEVEL, useUnmergedTree = true)
            .assert(SemanticsMatcher.expectValue(DiagnosticsColorKey, expected))
    }

    private fun messageText(): String =
        compose.onNodeWithTag(DiagnosticsRowTags.MESSAGE, useUnmergedTree = true)
            .fetchSemanticsNode()
            .config[SemanticsProperties.Text]
            .joinToString("") { it.text }

    // ───────────────────────────────────────────────────────── meta line

    @Test fun metaLineRendersTimestampLevelTokenAndCategoryPill() {
        showRow(entry(), DiagnosticsTokens.Light)

        compose.onNodeWithTag(DiagnosticsRowTags.TIME, useUnmergedTree = true).assertExists()
        // The design's mono timestamp is `HH:mm:ss.SSS` in the local zone (here pinned to UTC).
        compose.onNodeWithText("14:32:07.412", useUnmergedTree = true).assertExists()
        // The level token is UPPERCASE (the design applies `textTransform: uppercase`).
        compose.onNodeWithText("ERROR", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag(DiagnosticsRowTags.CATEGORY, useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Persistence", useUnmergedTree = true).assertExists()
    }

    @Test fun categoryPillRendersTheBoundedChipVocabularyNotTheRawTag() {
        // A raw third-party logcat tag files under a designed category; the design's pill draws one
        // of `DIAG_CATEGORIES`, and the RAW tag still travels in the export payload.
        showRow(entry(category = "SQLiteLog"), DiagnosticsTokens.Light)

        compose.onNodeWithText("Persistence", useUnmergedTree = true).assertExists()
    }

    // ───────────────────────────────────────────── level colors (one method per level per theme)

    @Test fun errorLevelUsesTheDesignErrorColorInLight() {
        showRow(entry(level = DiagnosticsLevel.ERROR), DiagnosticsTokens.Light)
        assertLevelColor(0xFFB13E36.toInt())
    }

    @Test fun errorLevelUsesTheDesignErrorColorInDark() {
        showRow(entry(level = DiagnosticsLevel.ERROR), DiagnosticsTokens.Dark)
        assertLevelColor(0xFFE0826F.toInt())
    }

    @Test fun infoLevelUsesTheDesignInfoColorInLight() {
        showRow(entry(level = DiagnosticsLevel.INFO), DiagnosticsTokens.Light)
        assertLevelColor(0xFF3A6F9C.toInt())
    }

    @Test fun infoLevelUsesTheDesignInfoColorInDark() {
        showRow(entry(level = DiagnosticsLevel.INFO), DiagnosticsTokens.Dark)
        assertLevelColor(0xFF7FB2D9.toInt())
    }

    @Test fun debugLevelUsesTheThemeSubColorInLight() {
        showRow(entry(level = DiagnosticsLevel.DEBUG), DiagnosticsTokens.Light)
        assertLevelColor(DiagnosticsTokens.Light.sub.toArgb())
    }

    @Test fun debugLevelUsesTheThemeSubColorInDark() {
        showRow(entry(level = DiagnosticsLevel.DEBUG), DiagnosticsTokens.Dark)
        assertLevelColor(DiagnosticsTokens.Dark.sub.toArgb())
    }

    @Test fun warnRendersWithTheDebugTreatmentInLight() {
        // Plan section 6.3 interim, pending the designed WARN treatment (GH #2021): a warn entry
        // stays inside the design's three-token vocabulary rather than inventing a `WARN` token.
        showRow(entry(level = DiagnosticsLevel.WARN), DiagnosticsTokens.Light)

        compose.onNodeWithText("DEBUG", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("WARN", useUnmergedTree = true).assertDoesNotExist()
        assertLevelColor(DiagnosticsTokens.Light.sub.toArgb())
    }

    @Test fun warnRendersWithTheDebugTreatmentInDark() {
        showRow(entry(level = DiagnosticsLevel.WARN), DiagnosticsTokens.Dark)

        compose.onNodeWithText("DEBUG", useUnmergedTree = true).assertExists()
        assertLevelColor(DiagnosticsTokens.Dark.sub.toArgb())
    }

    @Test fun assertLevelRidesTheErrorTreatmentInDark() {
        showRow(entry(level = DiagnosticsLevel.ASSERT), DiagnosticsTokens.Dark)

        compose.onNodeWithText("ERROR", useUnmergedTree = true).assertExists()
        assertLevelColor(0xFFE0826F.toInt())
    }

    @Test fun verboseFoldsIntoTheDebugTreatment() {
        showRow(entry(level = DiagnosticsLevel.VERBOSE), DiagnosticsTokens.Light)

        compose.onNodeWithText("DEBUG", useUnmergedTree = true).assertExists()
        assertLevelColor(DiagnosticsTokens.Light.sub.toArgb())
    }

    @Test fun assertLevelRidesTheErrorTreatment() {
        // logcat `F` is in the Errors chip's level SET, so it takes the error treatment and the
        // `ERROR` token — the design has no fourth token for it either.
        showRow(entry(level = DiagnosticsLevel.ASSERT), DiagnosticsTokens.Light)

        compose.onNodeWithText("ERROR", useUnmergedTree = true).assertExists()
        assertLevelColor(0xFFB13E36.toInt())
    }

    // ───────────────────────────────────────────────────────── clamp / expand

    @Test fun collapsedLongMessageIsClampedToThreeLinesAndTapExpandsItWithCopyEntry() {
        val long = (1..60).joinToString(" ") { "token$it" }
        compose.setContent {
            var expanded by remember { mutableStateOf(false) }
            DiagnosticsLogRow(
                entry = entry(message = long),
                expanded = expanded,
                onToggleExpanded = { expanded = !expanded },
                zone = utc,
            )
        }

        val lineHeightPx = with(compose.density) { DiagnosticsRowMetrics.MESSAGE_LINE_HEIGHT.toPx() }
        val collapsed = compose.onNodeWithTag(DiagnosticsRowTags.MESSAGE, useUnmergedTree = true)
            .fetchSemanticsNode().size.height
        // Bounded on BOTH sides (Gate-4 round 1): the upper bound rejects a 4-line clamp, the lower
        // bound rejects a 1- or 2-line clamp, which an upper bound alone would have let through.
        assertTrue(
            "collapsed message height ${collapsed}px exceeds the 3-line clamp (${lineHeightPx * 3}px)",
            collapsed <= lineHeightPx * 3.5f,
        )
        assertTrue(
            "collapsed message height ${collapsed}px is short of 3 lines (${lineHeightPx * 3}px)",
            collapsed >= lineHeightPx * 2.5f,
        )
        compose.onNodeWithText("Copy entry", useUnmergedTree = true).assertDoesNotExist()

        compose.onNodeWithTag(DiagnosticsRowTags.ROW).performClick()
        compose.waitForIdle()

        val expandedHeight = compose.onNodeWithTag(DiagnosticsRowTags.MESSAGE, useUnmergedTree = true)
            .fetchSemanticsNode().size.height
        assertTrue(
            "expanded message height ${expandedHeight}px should exceed the 3-line clamp",
            expandedHeight > collapsed,
        )
        compose.onNodeWithText("Copy entry", useUnmergedTree = true).assertExists()
    }

    // ─────────────────────────────────────────── THE clipboard/display asymmetry (Gate-2 CRITICAL)

    @Test fun copyEntryRedactsTheClipboardWhileTheRowKeepsShowingTheSecret() {
        val secret = "sk-live-A1b2C3d4E5f6G7h8J9k0LmN"
        val message =
            "WebDAV sync failed — Authorization: Bearer $secret — HTTP 401 from dav.example.com"
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = message),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        // (1) DISPLAY is not egress — the expanded row shows the message VERBATIM, secret included.
        assertEquals(message, messageText())
        assertTrue(messageText().contains(secret))

        // (2) The CLIPBOARD is egress — it carries the redacted message.
        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true)
            .assertHasClickAction()
            .performClick()
        compose.waitForIdle()
        val clip = clipText(context)

        assertNotNull("nothing reached the clipboard", clip)
        assertNotEquals("the copy action never wrote to the clipboard", sentinel, clip)
        assertFalse("the raw secret reached the clipboard", clip!!.contains(secret))
        assertTrue("no redaction marker in the clip: $clip", clip.contains(DiagnosticsRedactor.PLACEHOLDER))
        // Surrounding diagnostic context survives — a redacted clip is still a usable bug report.
        assertTrue(clip.contains("WebDAV sync failed"))
        assertTrue(clip.contains("HTTP 401"))
        assertTrue(clip.contains("dav.example.com"))

        // (3) …and copying did NOT mutate what the user sees.
        assertEquals(message, messageText())
    }

    @Test fun copyEntryRedactsAnAppPrivatePathButKeepsTheFingerprintKey() {
        val message =
            "import failed: /data/user/0/com.vreader.app/files/books/epub_a1b2c3_4 not readable"
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = message),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true).performClick()
        compose.waitForIdle()
        val clip = clipText(context)

        assertNotNull(clip)
        assertNotEquals(sentinel, clip)
        assertFalse(clip!!.contains("/data/user/0/com.vreader.app"))
        // The fingerprint key is the handle every bug report is filed against — it SURVIVES.
        assertTrue("fingerprint key lost from the clip: $clip", clip.contains("epub_a1b2c3_4"))
    }

    // ───────────────────────────────────────────────────────── day header

    @Test fun dayHeaderRendersTheDesignsUppercaseShape() {
        val today = DiagnosticsDayGrouper.sections(
            entries = listOf(IdentifiedDiagnosticsEntry(0, entry())),
            nowMillis = stamp,
            zone = utc,
            locale = java.util.Locale.UK,
        ).first()
        val yesterday = DiagnosticsDayGrouper.sections(
            entries = listOf(
                IdentifiedDiagnosticsEntry(0, entry(timeMillis = stamp - 24 * 3_600_000L)),
            ),
            nowMillis = stamp,
            zone = utc,
            locale = java.util.Locale.UK,
        ).first()
        val older = DiagnosticsDayGrouper.sections(
            entries = listOf(
                IdentifiedDiagnosticsEntry(0, entry(timeMillis = stamp - 2 * 24 * 3_600_000L)),
            ),
            nowMillis = stamp,
            zone = utc,
            locale = java.util.Locale.UK,
        ).first()

        compose.setContent {
            Column {
                DiagnosticsDayHeader(today.header)
                DiagnosticsDayHeader(yesterday.header)
                DiagnosticsDayHeader(older.header)
            }
        }

        compose.onNodeWithText("TODAY · 10 JUNE", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("YESTERDAY · 9 JUNE", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("8 JUNE", useUnmergedTree = true).assertExists()
    }

    // ───────────────────────────────────────────────────────── edges

    @Test fun anEmptyMessageStillRendersTheMetaLineAndAnUsableCopyAction() {
        compose.setContent {
            DiagnosticsLogRow(
                entry = entry(message = ""),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        compose.onNodeWithText("14:32:07.412", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true)
            .assertHasClickAction()
            .performClick()
        compose.waitForIdle()
        compose.onNodeWithTag(DiagnosticsRowTags.ROW).assertExists()
    }

    @Test fun aMultiLineCjkMessageIsDisplayedAndCopiedIntact() {
        val message = "打开书籍失败：分页缓存损坏\n继续行：第 12 章，共 38 页"
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = message),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        assertEquals(message, messageText())
        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true).performClick()
        compose.waitForIdle()
        // Nothing in this message is a credential, so redaction is a no-op — CJK is not mangled.
        assertEquals(message, clipText(context))
    }

    @Test fun aNewlineOnlyMessageRendersAndCopiesWithoutCrashing() {
        // The logcat parser can hand us continuation-only payloads; a blank body must not take the
        // row down or produce a clipboard write of something other than the message.
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = "\n\n\n"),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertEquals("\n\n\n", clipText(context))
    }

    @Test fun anRtlMessageIsDisplayedAndCopiedIntact() {
        val message = "فشل فتح الكتاب — Authorization: Bearer sk-live-RtlSecret1234567890 — HTTP 401"
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = message),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        assertEquals(message, messageText())
        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true).performClick()
        compose.waitForIdle()
        val clip = clipText(context)

        assertNotNull(clip)
        assertFalse(clip!!.contains("sk-live-RtlSecret1234567890"))
        assertTrue(clip.contains(DiagnosticsRedactor.PLACEHOLDER))
        // The Arabic context survives — redaction is anchored on the credential, not the script.
        assertTrue(clip.contains("فشل فتح الكتاب"))
    }

    @Test fun aTruncationSizedMessageStillRedactsOnCopy() {
        // logd truncates a payload at 4068 bytes; the tail is where a credential can end up sitting.
        val filler = "context ".repeat(500)
        val message = (filler + "Authorization: Bearer sk-live-TailSecret0987654321").take(4068)
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = message),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true).performClick()
        compose.waitForIdle()
        val clip = clipText(context)

        assertNotNull(clip)
        assertFalse(clip!!.contains("sk-live-TailSecret0987654321"))
        assertTrue(clip.contains(DiagnosticsRedactor.PLACEHOLDER))
    }

    @Test fun repeatedCopyTapsLeaveTheRedactedTextOnTheClipboard() {
        val secret = "sk-live-RepeatTap1234567890abc"
        lateinit var context: Context
        compose.setContent {
            context = LocalContext.current
            DiagnosticsLogRow(
                entry = entry(message = "retry — Authorization: Bearer $secret — attempt 3/5"),
                expanded = true,
                onToggleExpanded = {},
                zone = utc,
            )
        }

        repeat(5) {
            compose.onNodeWithTag(DiagnosticsRowTags.COPY, useUnmergedTree = true).performClick()
        }
        compose.waitForIdle()
        val clip = clipText(context)

        assertNotNull(clip)
        assertFalse(clip!!.contains(secret))
        assertTrue(clip.contains(DiagnosticsRedactor.PLACEHOLDER))
        assertTrue(clip.contains("attempt 3/5"))
    }

    @Test fun theLastRowOmitsTheDivider() {
        compose.setContent {
            DiagnosticsLogRow(
                entry = entry(),
                expanded = false,
                onToggleExpanded = {},
                isLast = true,
                zone = utc,
            )
        }

        compose.onNodeWithTag(DiagnosticsRowTags.DIVIDER, useUnmergedTree = true)
            .assertDoesNotExist()
    }
}
