package com.vreader.app.reader

import android.util.Log
import android.view.View
import android.webkit.WebView
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.Azw3DocState
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.nav.FoliateTocProvider
import com.vreader.app.reader.nav.TocEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File
import java.security.MessageDigest

/**
 * Feature #140 WI-8 — the Gate-5b ACCEPTANCE suite: the AZW3/MOBI/KF8 table of contents exercised on
 * the REAL Kindle book, through the PRODUCTION entry point, with every criterion assertion made only
 * after the reader has been observed in [Azw3DocState.Loaded].
 *
 * ## The production path (rule 47 Gate 5 — production reachability)
 *
 * **app launch → `MainActivity` (the manifest LAUNCHER activity) → Library grid → tap the book's tile
 * → `Azw3ReaderActivity` → bottom-chrome "Contents" → tap a chapter row → the reader moves and that
 * chapter becomes the highlighted row.**
 *
 * No `Azw3ReaderActivity.intent(...)`, no `src/debug` launcher, no composable invoked directly — the
 * mirror of `dev-docs/verification/feature-139-20260805.md`'s wording. The reader that the tap opens is
 * additionally required to carry this book's fingerprint in the PRODUCTION intent extra
 * ([Azw3ReaderActivity.EXTRA_FINGERPRINT_KEY]), so tapping the wrong tile fails loudly rather than
 * quietly asserting against another book. Every file on that path lives in `android/app/src/main`
 * (`MainActivity`, `LibraryScreen`, `Azw3ReaderActivity`, `Azw3ReaderChrome`, `ReaderChromeScaffold`,
 * `TocBookmarksSheet`, `TocContentsSheetContent`, `FoliateTocProvider`); `android/app/src/debug` holds
 * only a manifest, a `res/` tree, `BackupDebugActivity.kt` and `PreviewBackupService.kt` — none of them
 * on this path.
 *
 * Two bounds on that claim, stated rather than glossed (Gate-4 R1):
 *  - `ActivityScenario.launch(MainActivity::class.java)` starts the LAUNCHER activity **class**
 *    directly; it is not literally an `ACTION_MAIN`/`CATEGORY_LAUNCHER` intent. That `MainActivity` is
 *    the launcher, and that `Azw3ReaderActivity` is not exported, are STATIC facts from
 *    `AndroidManifest.xml` — this suite does not dynamically exercise launcher-filter dispatch. Same
 *    posture as the #139 precedent.
 *  - No instrumentable release variant exists (the module declares no `buildTypes` block, so `release`
 *    is unsigned), so this runs on `debug`, which shares `src/main` with release. The static-release +
 *    dynamic-debug split this project settled on.
 *
 * ## No CRITERION is asserted before the book is ready (the #139 lesson, made structural)
 *
 * A "the control is hidden" check taken while the pipeline is still loading — or wedged — passes
 * trivially and forever. So [bookReadyObserved] is set by exactly one place ([awaitBookReady]) and
 * every criterion assertion is wrapped in [afterBookReady], which throws when it has not been set.
 * The gate is not a comment; an edit that asserts a criterion too early fails on the spot.
 *
 * **Precisely which assertions that covers** (Gate-4 R1 Medium — an earlier revision of this comment
 * said "every assertion", which was false): every assertion ABOUT THE READER — the Contents control,
 * the sheet, the rows, the indentation, the jump, the highlight. It deliberately does NOT cover the
 * PRECONDITIONS that must hold before a reader can exist at all, which are inputs rather than
 * criteria: the fixture's presence and content digest ([importRealBook]), the pinned-TOC-content and
 * structure checks over the oracle ([assertPinnedTocContent]), and the reader-stack drain + intent
 * identity check inside [openThroughLibrary]. A stuck production pipeline cannot green either test,
 * because both call [awaitBookReady] before any criterion assertion.
 *
 * The observation itself is the host's own [Azw3DocState.Loaded] branch, read through production UI:
 * the page-turn tap zones (`azw3-prev-zone` / `azw3-next-zone`) are composed **only** inside
 * `if (state is Azw3DocState.Loaded)`, so their presence in the semantics tree IS the Loaded state.
 * Their EXISTENCE is what is checked, never `assertIsDisplayed` — bug **#369** (GH #2080) is an open,
 * pre-existing failure of `Azw3ReaderActivityTest.tappingNext_turnsThePage_advancesPosition` on exactly
 * that displayed-ness assertion, and this suite must not inherit an unrelated defect's failure mode.
 * [awaitBookReady] then additionally waits for a PERSISTED position, i.e. for a relocate to have
 * round-tripped from the bundle — a strictly stronger "the pipeline ran" signal than book-ready alone.
 *
 * ## Ack is never evidence; ONE href-bound observation is
 *
 * foliate's `view.goTo` catches a failed resolution and settles anyway (`foliate-bundle.js:6874-6884`),
 * so the shell shim acks `ok:true` on a jump that moved nothing — WI-7 logged exactly that on its bogus
 * href. No assertion here inspects a jump result. Motion is established inside ONE window in which the
 * reader consistently reports the TAPPED chapter (Gate-4 R1 High — an earlier revision asserted "it
 * moved" and "it landed there" in two independent waits, which drift plus a later unrelated relocate
 * could have satisfied between them):
 *
 *  1. the Contents highlight reaches the tapped chapter's row. That row index is
 *     `foliateTocIndexFor(relocate.tocHref, rowHrefs)`, so it can only be reached if foliate REPORTED
 *     the tapped href — drift to anywhere else in the book cannot produce it;
 *  2. with that highlight still standing, the PERSISTED reading position (written by the production
 *     relocate → `Azw3LocatorBridge` → `savePosition` path) is read and must have advanced past a
 *     pre-jump baseline that was required both to hold still and to STILL BE CURRENT at the instant of
 *     the tap.
 *
 * ## The fixture — required, never assumed, never skipped
 *
 * `androidTest/assets/foliate-spike/book.azw3` is gitignored and absent from a fresh worktree. Every
 * other AZW3 connected test `assumeTrue`-SKIPS without it, and **a skip exits 0 exactly like a pass** —
 * the precedent is bug #369, a connected test that was failing on-device while silently skipping in
 * every ordinary run. This class therefore FAILS LOUDLY instead: the asset must be present and the
 * imported artifact's content digest must be the real book's ([REAL_BOOK_SHA256]), so a truncated
 * push, a different novel or a same-sized stand-in all fail here rather than false-greening. Stage it:
 *
 * ```
 * cp /Users/ll/workspace/vreader/android/app/src/androidTest/assets/foliate-spike/book.azw3 \
 *    <worktree>/android/app/src/androidTest/assets/foliate-spike/
 * ```
 *
 * ## What the real book does and does NOT cover
 *
 * Its NCX is [EXPECTED_ROOT_NODES] roots → [EXPECTED_ROWS] rows, depths [EXPECTED_DEPTH_HISTOGRAM],
 * **maxDepth [EXPECTED_MAX_DEPTH]** — hierarchical, but only ONE level deep. So this suite evidences
 * nested real-book data **at depth 1 only**; depth ≥ 2 is not present in the fixture and rests on the
 * JVM suites (`FoliateTocParserTest` / `FoliateTocProviderTest`, over synthetic deep trees) plus #139's
 * on-screen depth-3 indentation verification of the SAME rows, sheet and `depth` field. There is also
 * exactly one real AZW3 in `test-books/books/azw3/`, and it HAS a TOC — so criterion 7's no-TOC book
 * has no real fixture and is covered at the chrome level by
 * `Azw3ReaderChromeUiTest.emptyToc_hidesContents_notesStillPresent` (the real chrome stack, empty
 * entries → no Contents control, Notes still present). Stated, not implied.
 *
 * Run ONE class per connected invocation, and never drive the emulator while it runs (rule 52).
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class Azw3TocAcceptanceTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val inst get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = inst.targetContext.applicationContext as VReaderApp

    /**
     * Whether THIS test method has observed [Azw3DocState.Loaded]. Set by [awaitBookReady] and by
     * nothing else; read by [afterBookReady], which every criterion assertion goes through. Per-method
     * (the field is on the test instance, and JUnit builds a fresh one per method), so one method's
     * observation can never license another's assertion.
     */
    private var bookReadyObserved = false

    @After fun closeAnyReader() { finishAnyReader() }

    // ---- the acceptance-bar constants ------------------------------------------------------------

    private companion object {
        const val TAG = "WI140-ACCEPT"

        const val FIXTURE_ASSET = "foliate-spike/book.azw3"
        const val DISPLAY_NAME = "Bei Tao Yan De Yong Qi - Zi Wo.azw3"
        /** What the Library tile shows — `BookImporter.titleFromDisplayName` strips the extension. */
        const val BOOK_TITLE = "Bei Tao Yan De Yong Qi - Zi Wo"

        /**
         * Identity by CONTENT DIGEST, not by size. `BookImporter` hashes exactly the bytes it stores,
         * so its own `contentSHA256` is a free, exact check on the artifact the reader then opens; a
         * same-sized synthetic stand-in sails through a byte-count check but not through this.
         */
        const val REAL_BOOK_SHA256 = "39826bfdbcd776ce3a6bc512158f6a5240aefadb188e07b0d86a996489c01c95"
        const val REAL_BOOK_BYTES = 6_288_371L

        /**
         * The real book's TOC shape as WI-7 measured it on this emulator. Hardcoded ON PURPOSE (the
         * #139 `EXPECTED_CHAPTER_COUNT = 1859` precedent): re-deriving the expectation from the same
         * run would assert the pipeline against itself, whereas a pinned number turns any regression
         * in the bundle → parser → provider chain into a red test with a readable diff.
         */
        const val EXPECTED_ROOT_NODES = 15
        const val EXPECTED_ROWS = 71
        const val EXPECTED_MAX_DEPTH = 1
        val EXPECTED_DEPTH_HISTOGRAM = sortedMapOf(0 to 15, 1 to 56)

        /**
         * CONTENT pins — the book's own NCX strings, not just its shape (Gate-4 R1 High: counts alone
         * would let a parser that emitted 71 rows of *wrong* non-blank titles pass, because the row
         * text is otherwise checked against the very provider run that produced it).
         *
         * Only whitespace-free titles are pinned, deliberately: the sheet normalizes a title's
         * whitespace before rendering it, so pinning a title with an interior space would be pinning
         * the normalizer as much as the NCX — and this book's remaining labels mix ASCII and
         * ideographic spaces. The five strings below are pure CJK and unambiguous.
         */
        const val EXPECTED_FIRST_TITLE = "原书信息"
        const val EXPECTED_SECOND_TITLE = "相关内容"
        const val EXPECTED_THIRD_TITLE = "本书的赞誉"
        const val EXPECTED_LAST_TITLE = "作译者简介"

        /**
         * A digest over the WHOLE flattened TOC — every row's `depth`, `title` and `href`, in order
         * (see [tocDigest]). This is the pin that closes the same-run circularity for the rows the
         * named constants above do not cover (Gate-4 R2 High): pinning only rows 0, 1, 2, 35 and 70
         * would still let a regression that corrupts or reorders the other 66 rows pass, because the
         * on-screen titles are otherwise compared against the very provider run that produced them.
         * With this digest fixed, "the UI matches the provider" IS "the UI matches the pin".
         *
         * A golden value: recorded once from this immutable local fixture, then held. If it changes,
         * either the bundle/parser/provider changed behaviour or the fixture is not the same book —
         * both are things this suite exists to catch, and the failure message prints the new value.
         */
        const val EXPECTED_TOC_DIGEST = "68e9168ce19f869d43aa9cf5ab6d2dd84487d4e2c758b69352641e94fb970556"

        /**
         * The chapter this suite taps: a MIDDLE row (criterion 4 — chapter 1 would be reachable by
         * doing nothing) whose href is a real KF8 position URI and is UNIQUE in the list, so the
         * expected highlight is the tapped row itself. Pinned rather than computed, so the jump target
         * cannot silently drift to a different chapter between runs.
         */
        const val TARGET_ROW_INDEX = 35
        const val TARGET_TITLE = "要不要活在别人的期待中？"
        const val TARGET_HREF = "kindle:pos:fid:001C:off:0000000000"
        /** `foliateTocIndexFor` is last-match-wins; [TARGET_HREF] is unique, so this is the tapped row. */
        const val EXPECTED_HIGHLIGHT_ROW = 35

        /**
         * Where each plan §11 acceptance criterion is asserted. This is bookkeeping with a consistency
         * check, not a proof: it makes the split explicit and fails if the four sets ever stop
         * partitioning 1..10, so "the sibling covers it" can never quietly become "nobody covers it".
         * The delegated criteria are asserted by REAL tests re-run in the same Gate-5b pass, and their
         * results are recorded in the evidence file.
         */
        val CRITERIA_HERE = setOf(1, 2, 3, 7)                       // everyAcceptanceCriterionIsAsserted_afterBookReady
        val CRITERIA_SIBLING = setOf(4, 5)                          // productionPath_libraryTapToContentsToChapterJump
        val CRITERIA_WI7 = setOf(6, 8, 10)                          // Azw3TocConnectedTest (re-run)
        val CRITERIA_SUITE_RERUNS = setOf(9)                        // Azw3TocConnectedTest + Azw3ReaderChromeUiTest + JVM suites

        /** A 6 MB import + a WebView + the foliate bundle + first paint on a loaded emulator is slow, not hung. */
        const val UI_TIMEOUT_MS = 120_000L
        const val OPEN_TIMEOUT_MS = 120_000L
        /** How long the pre-jump position must hold still before it is taken as the "before" reading. */
        const val SETTLE_HOLD_MS = 3_000L
        const val SETTLE_TIMEOUT_MS = 60_000L
        const val POLL_MS = 200L

        /** The oracle rows for one book key, computed once per class run (both tests need them). */
        @Volatile var cachedOracle: Pair<String, Oracle>? = null
    }

    /** The pipeline's own answer for this book: the `book-ready` tree size + the flattened rows. */
    private class Oracle(val rootNodes: Int, val rows: List<TocEntry>)

    /** The persisted reading position as a comparable sample: the production save path writes both. */
    private data class Position(val cfi: String?, val progression: Double?)

    // ---- criteria 1, 2, 3, 7 ----------------------------------------------------------------------

    /**
     * The per-criterion pass, every reader claim made AFTER [Azw3DocState.Loaded] is observed.
     *
     * Asserted here, on the real book through the production path: **1** (the Contents control appears),
     * **2** (the sheet lists the book's real chapters — the list's declared length, the row order, and
     * the pinned NCX titles), **3** (nesting is INDENTED on screen, measured, not read off the `depth`
     * field), and criterion **7**'s observable half (the chrome rendered at all — `chrome-notes` is
     * present, so a "Contents is hidden" check on a no-TOC book would have teeth rather than passing on
     * an empty screen).
     *
     * **The method name is the dispatched contract's, and it is broader than what this ONE method
     * asserts** (Gate-4 R1 Medium). The plan's ten criteria are partitioned across four places by
     * [CRITERIA_HERE] / [CRITERIA_SIBLING] / [CRITERIA_WI7] / [CRITERIA_SUITE_RERUNS], and that
     * partition is checked below so a criterion cannot fall between them. Criteria 4 and 5 belong to
     * [productionPath_libraryTapToContentsToChapterJump] (they need a jump, and doing it twice would
     * double the slowest part of this run for no new evidence); 6, 8 and 10 belong to
     * `Azw3TocConnectedTest`, whose bogus-href negative control and hostile-payload injection are not
     * expressible through a production Contents sheet at all — a real TOC contains no unresolvable row.
     * Those suites are re-run unchanged in this same Gate-5b pass; this method does not restate their
     * outcomes, because a test that "records" another test's result asserts nothing.
     */
    @Test
    fun everyAcceptanceCriterionIsAsserted_afterBookReady() {
        assertEquals(
            "the §11 criteria are no longer partitioned across the four places that assert them",
            (1..10).toSet(),
            CRITERIA_HERE + CRITERIA_SIBLING + CRITERIA_WI7 + CRITERIA_SUITE_RERUNS,
        )
        assertEquals(
            "a criterion is claimed by more than one place — the accounting is ambiguous",
            10,
            CRITERIA_HERE.size + CRITERIA_SIBLING.size + CRITERIA_WI7.size + CRITERIA_SUITE_RERUNS.size,
        )

        val book = importRealBook()
        val oracle = oracleFor(book)
        val rows = oracle.rows
        assertPinnedTocContent(oracle)

        // An adjacent parent/child pair for criterion 3, deliberately away from row 0: the current row
        // carries a zero-size marker child that still consumes the row's arrangement spacing and would
        // shift its title by more than a depth step (the #139 finding).
        val parentIndex = (1 until rows.size - 1)
            .firstOrNull { rows[it].depth == 0 && rows[it + 1].depth == 1 }
            ?: throw AssertionError("the fixture has no depth-0 row followed by a depth-1 child away from row 0")

        runBlocking { app.container.repository.clearPosition(book.fingerprintKey) }

        openThroughLibrary(book) {
            awaitBookReady(book)

            // ---- criterion 1: the Contents control appears on an AZW3 with a TOC --------------------
            afterBookReady("1 — Contents control appears") {
                compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("chrome-contents") > 0 }
                assertEquals("the AZW3 bottom chrome did not render", 1, nodeCount("azw3-bottom-chrome"))
                assertTrue("no Contents control on a book that HAS a TOC", nodeCount("chrome-contents") > 0)
                assertTrue("the designed 'Contents' label is missing", textExists("Contents"))
            }

            // ---- criterion 7 (observable half): the chrome rendered at all --------------------------
            // Without this, a "Contents is hidden" check could pass on a blank screen.
            afterBookReady("7 — the chrome is really on screen") {
                assertTrue("the Notes control is missing — the bottom chrome is not really up", nodeCount("chrome-notes") > 0)
            }

            openContentsSheet()

            // ---- criterion 2: the sheet lists the book's real chapters ------------------------------
            afterBookReady("2 — the sheet lists the real chapters") {
                assertEquals("an empty state on a book that HAS a TOC", 0, nodeCount("toc-empty"))

                // The list's OWN length, EXACTLY, squeezed from two sides (Gate-4 R1 Medium: counting
                // composed nodes depends on what happens to be scrolled into view). The lazy list
                // validates a ScrollToIndex against its REAL item count, so:
                //   index rows.size - 1 is ACCEPTED  ⇒ itemCount >= rows.size
                //   index rows.size     is REJECTED  ⇒ itemCount <= rows.size
                // together ⇒ itemCount == rows.size. The exception's MESSAGE is only logged, never
                // asserted on (Gate-4 R2 Low — the proof must not hinge on Compose's wording).
                // Its accessibility `CollectionInfo` is NOT usable here: the lazy list publishes
                // `rowCount = -1` (measured on this emulator), i.e. "unknown".
                scrollTocTo(rows.size - 1)
                val outOfRange = runCatching {
                    compose.onNodeWithTag("toc-list", useUnmergedTree = true).performScrollToIndex(rows.size)
                }.exceptionOrNull()
                Log.i(TAG, "LIST BOUND scrollToIndex(${rows.size}) rejected with: ${outOfRange?.message}")
                assertTrue(
                    "scrolling one past the last row was ACCEPTED — the Contents list is longer than " +
                        "the ${rows.size} rows the pipeline produced (or its lazy semantics stopped " +
                        "bounding the index, in which case this check needs rewriting)",
                    outOfRange is IllegalArgumentException,
                )

                assertEquals(
                    "a row exists one past the last one the pipeline produced",
                    0, nodeCount("toc-row-${rows.size}"),
                )

                // EVERY row renders ITS OWN title, at its own index — the whole list, not a sample
                // (Gate-4 R2 High). Comparing the screen against the provider is not circular here,
                // because the provider's entire (depth, title, href) sequence is pinned by
                // EXPECTED_TOC_DIGEST above: "the UI matches the provider" therefore IS "the UI matches
                // the pin". Walking all of them also demonstrates every chapter is reachable in the
                // lazy list, not merely the first screenful.
                for (i in rows.indices) {
                    scrollTocTo(i)
                    assertRowShowsPipelineTitle(i, rows)
                }
                // The two named NCX strings, checked on screen by their literal value.
                scrollTocTo(0)
                assertRowShowsExactly(0, EXPECTED_FIRST_TITLE)
                scrollTocTo(rows.size - 1)
                assertRowShowsExactly(rows.size - 1, EXPECTED_LAST_TITLE)
            }

            // ---- criterion 3: nested entries are INDENTED on screen ---------------------------------
            afterBookReady("3 — depth-1 indents past depth-0") {
                scrollTocTo(parentIndex)
                val parentLeft = titleLeftInRow(parentIndex, rows)
                val childLeft = titleLeftInRow(parentIndex + 1, rows)
                Log.i(
                    TAG,
                    "INDENTATION depth0_row=$parentIndex left=$parentLeft " +
                        "depth1_row=${parentIndex + 1} left=$childLeft delta=${childLeft - parentLeft}",
                )
                assertTrue(
                    "the depth-1 row '${rows[parentIndex + 1].title}' is not indented past its depth-0 " +
                        "parent '${rows[parentIndex].title}' (child=$childLeft parent=$parentLeft)",
                    childLeft > parentLeft,
                )
            }
        }
        Log.i(TAG, "CRITERIA $CRITERIA_HERE PASSED on the real book through the production path")
    }

    // ---- criteria 4 + 5 ---------------------------------------------------------------------------

    /**
     * The headline user journey, end to end: **Library → tap the book → reader → Contents → tap a
     * middle chapter → the reader moves there and that row becomes the highlighted one.**
     *
     * Criteria 4 and 5 are established as ONE claim inside ONE observation window, not as two
     * independent waits (Gate-4 R1 High). The href-bound fact comes first: the Contents highlight is
     * `foliateTocIndexFor` over the `tocHref` foliate itself reports, so the marker can reach
     * [EXPECTED_HIGHLIGHT_ROW] only if foliate reported the TAPPED chapter's href — settle drift, a
     * delayed layout relocate or a restore-from-saved-position cannot put it there. With that highlight
     * still standing, the persisted position is read and must have advanced past a baseline that was
     * required both to hold still AND to still be the current position at the instant of the tap.
     *
     * A non-zero highlight row is load-bearing: index 0 is both the pre-jump state and
     * `foliateTocIndexFor`'s no-match fallback, so a row-0 target could not tell a working highlight
     * from a broken one. The expected row is `indexOfLast { it == TARGET_HREF }` because the contract is
     * last-match-wins (a part and its first chapter legitimately share an href); [TARGET_HREF] is
     * unique in this book, which [assertPinnedTocContent] re-checks rather than assumes.
     */
    @Test
    fun productionPath_libraryTapToContentsToChapterJump() {
        val book = importRealBook()
        val oracle = oracleFor(book)
        val rows = oracle.rows
        assertPinnedTocContent(oracle)

        // Start at the top of the book, so the opening chapter is genuinely a different chapter from
        // the middle one this test taps.
        runBlocking { app.container.repository.clearPosition(book.fingerprintKey) }

        openThroughLibrary(book) {
            awaitBookReady(book)

            val baseline = settledPosition(book)
            Log.i(
                TAG,
                "JUMP target row=$TARGET_ROW_INDEX title='$TARGET_TITLE' href=$TARGET_HREF " +
                    "expected_highlight_row=$EXPECTED_HIGHLIGHT_ROW from $baseline",
            )

            openContentsSheet()

            afterBookReady("5 — the highlight is NOT already on the target before the jump") {
                scrollTocTo(EXPECTED_HIGHLIGHT_ROW)
                assertFalse(
                    "the Contents highlight is already on row $EXPECTED_HIGHLIGHT_ROW before the jump " +
                        "— the post-jump assertion would prove nothing",
                    rowIsCurrent(EXPECTED_HIGHLIGHT_ROW),
                )
            }

            afterBookReady("4 + 5 — the tapped middle chapter is where the reader goes") {
                scrollTocTo(TARGET_ROW_INDEX)
                assertRowShowsExactly(TARGET_ROW_INDEX, TARGET_TITLE)
                // The baseline must still be the CURRENT position at the instant of the tap: a relocate
                // that arrived between the settle and the tap would otherwise be free to masquerade as
                // the jump's own motion.
                assertEquals(
                    "the reader moved between the settle and the tap — the baseline is stale",
                    baseline, persistedPosition(book),
                )

                compose.onNodeWithTag("toc-row-$TARGET_ROW_INDEX", useUnmergedTree = true).performClick()
                // Dismiss-on-success is the designed sheet behaviour; it is a UI fact, NOT motion.
                compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("toc-sheet-content") == 0 }

                // (1) THE href-BOUND OBSERVATION — the highlight can only land here if foliate reported
                // the tapped chapter's href back to the host.
                openContentsSheet()
                scrollTocTo(EXPECTED_HIGHLIGHT_ROW)
                compose.waitUntil(UI_TIMEOUT_MS) { rowIsCurrent(EXPECTED_HIGHLIGHT_ROW) }

                // (2) …and, read INSIDE the window in which that href-bound report still holds, the
                // persisted position has advanced. Sampling it here rather than in its own earlier wait
                // is what ties "it moved" to "it moved INTO the tapped chapter".
                val after = persistedPosition(book)
                assertTrue(
                    "the highlight left the tapped chapter while its position was being read — the two " +
                        "observations are not from the same window",
                    rowIsCurrent(EXPECTED_HIGHLIGHT_ROW),
                )
                Log.i(TAG, "MOVED $baseline -> $after (row=$TARGET_ROW_INDEX '$TARGET_TITLE')")

                assertEquals("more than one row claims to be current", 1, nodeCount("toc-current-marker"))
                assertFalse("row 0 is still marked current after a mid-book jump", rowIsCurrent(0))
                assertNotEquals(
                    "the persisted cfi did not change — the chapter tap moved nothing. An ack is not motion.",
                    baseline.cfi, after.cfi,
                )
                val beforeProgression = requireNotNull(baseline.progression) { "no pre-jump progression" }
                val afterProgression = requireNotNull(after.progression) { "no post-jump progression" }
                assertTrue(
                    "the reader did not move FORWARD into the middle chapter — a landing at or behind " +
                        "the opening position is the Fraction(0.0) failure shape " +
                        "(before=$beforeProgression after=$afterProgression)",
                    afterProgression > beforeProgression,
                )
            }
        }
        Log.i(TAG, "CRITERIA $CRITERIA_SIBLING PASSED on the real book through the production path")
    }

    // ---- the fixture + the oracle -----------------------------------------------------------------

    /**
     * Import the REAL local-only AZW3 through the production importer, and prove by content digest
     * that it IS that book. A missing fixture is a hard FAILURE, never an `assumeTrue` skip: a skip
     * exits 0 exactly like a pass, which is how bug #369 stayed invisible while failing on-device.
     */
    private fun importRealBook(): Book {
        val present = inst.context.assets.list("foliate-spike")?.contains("book.azw3") == true
        assertTrue(
            "Gate-5b acceptance requires the local-only real AZW3 at androidTest assets " +
                "`$FIXTURE_ASSET`. It is gitignored, so a fresh worktree does NOT have it — stage it " +
                "before the run: cp /Users/ll/workspace/vreader/android/app/src/androidTest/assets/" +
                "foliate-spike/book.azw3 <worktree>/android/app/src/androidTest/assets/foliate-spike/",
            present,
        )
        val staged = File(inst.targetContext.cacheDir, "wi8-acceptance.azw3")
        inst.context.assets.open(FIXTURE_ASSET).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$DISPLAY_NAME", DISPLAY_NAME, staged.inputStream())
        }
        assertEquals("the imported artifact is not the real AZW3 (content digest)", REAL_BOOK_SHA256, book.contentSHA256)
        assertEquals("the imported artifact is not the real AZW3 (byte count)", REAL_BOOK_BYTES, book.fileByteCount)
        return book
    }

    /**
     * The pipeline's own Contents rows for [book], obtained by driving a HEADLESS [Azw3Document] over
     * the very artifact the reader opens and flattening its `book-ready` tree with the production
     * [FoliateTocProvider]. Computed once per class run and cached.
     *
     * **What this is and is not.** It is not an independent implementation, so it is not a correctness
     * oracle: it is the same production code driven without a UI, waiting on ITS OWN document's Loaded
     * state (never the reader Activity's). Its job is to make the UI checkable — to supply the row
     * count, order and titles the on-screen list is matched against. The CORRECTNESS pins are the
     * hardcoded structure and NCX-content constants, which come from the recorded measurement of this
     * fixture rather than from this run, and which [assertPinnedTocContent] applies.
     *
     * It is built and destroyed BEFORE the reader Activity launches, so two foliate WebViews never
     * coexist on a 2.5 GB emulator.
     */
    private fun oracleFor(book: Book): Oracle {
        cachedOracle?.let { (key, oracle) -> if (key == book.fingerprintKey) return oracle }
        val file = File(requireNotNull(book.localFilePath) { "the imported book has no local artifact" })
        lateinit var doc: Azw3Document
        inst.runOnMainSync {
            val webView = WebView(inst.targetContext).also(::forceViewport)
            doc = Azw3Document(webView, file, inst.targetContext)
        }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        try {
            scope.launch { doc.run(restore = null) }
            awaitUntil(OPEN_TIMEOUT_MS, "the oracle document to reach Azw3DocState.Loaded") {
                doc.state.value is Azw3DocState.Loaded
            }
            val loaded = doc.state.value as Azw3DocState.Loaded
            val rows = runBlocking { FoliateTocProvider(loaded.toc, book, Dispatchers.Default).toc() }
            val oracle = Oracle(rootNodes = loaded.toc.size, rows = rows)
            cachedOracle = book.fingerprintKey to oracle
            return oracle
        } finally {
            scope.cancel()
            inst.runOnMainSync { runCatching { doc.destroy() } }
        }
    }

    /**
     * The pinned SHAPE and CONTENT of this fixture's table of contents, plus the pinned jump target.
     * Everything here is an expectation recorded from the fixture, not derived from this run, so a
     * regression anywhere in bundle → parser → provider is a red test with a readable diff rather than
     * a silently re-derived "expectation".
     */
    private fun assertPinnedTocContent(oracle: Oracle) {
        val rows = oracle.rows
        val hrefs = rows.map { it.canonicalLocator.href }
        val histogram = rows.groupingBy { it.depth }.eachCount().toSortedMap()
        Log.i(
            TAG,
            "TOC STRUCTURE roots=${oracle.rootNodes} rows=${rows.size} histogram=$histogram " +
                "maxDepth=${rows.maxOf { it.depth }} first='${rows.first().title}' last='${rows.last().title}'",
        )
        assertEquals("the real book's book-ready tree changed root-node count", EXPECTED_ROOT_NODES, oracle.rootNodes)
        assertEquals("the real book's flattened Contents row count changed", EXPECTED_ROWS, rows.size)
        assertEquals("the real book's depth distribution changed", EXPECTED_DEPTH_HISTOGRAM, histogram)
        assertEquals("the real book's TOC is no longer hierarchical", EXPECTED_MAX_DEPTH, rows.maxOf { it.depth })
        assertTrue(
            "every row must be displayable AND navigable (trimmed non-blank title + non-blank href)",
            rows.all { !it.title.isNullOrBlank() && !it.canonicalLocator.href.isNullOrBlank() },
        )

        // Content, not just shape.
        assertEquals("the first Contents row is no longer the book's first NCX label", EXPECTED_FIRST_TITLE, rows[0].title)
        assertEquals("the second Contents row changed", EXPECTED_SECOND_TITLE, rows[1].title)
        assertEquals("the third Contents row changed", EXPECTED_THIRD_TITLE, rows[2].title)
        assertEquals("the last Contents row changed", EXPECTED_LAST_TITLE, rows[rows.size - 1].title)

        // EVERY row, not just the named ones — the pin that makes the on-screen title checks
        // non-circular (Gate-4 R2 High).
        val digest = tocDigest(rows)
        Log.i(TAG, "TOC DIGEST (depth|title|href over all ${rows.size} rows) = $digest")
        assertEquals(
            "the flattened TOC changed: some row's depth, title, href or position is not what this " +
                "fixture pins. If the change is intentional, update EXPECTED_TOC_DIGEST to the value " +
                "printed here",
            EXPECTED_TOC_DIGEST, digest,
        )

        // The pinned jump target, and the three properties the criterion-4/5 assertions rely on.
        assertEquals("the pinned target row's title moved", TARGET_TITLE, rows[TARGET_ROW_INDEX].title)
        assertEquals("the pinned target row's href moved", TARGET_HREF, hrefs[TARGET_ROW_INDEX])
        // UNIQUENESS, not merely "no LATER duplicate" (Gate-4 R2 Medium): an EARLIER row sharing this
        // href would let the highlight reach row 35 on a report that does not uniquely name the tapped
        // chapter, which is precisely the inference criterion 5 makes.
        assertEquals(
            "the pinned target href is no longer unique in this TOC — the highlight could then be " +
                "explained by a report naming a different row",
            1, hrefs.count { it == TARGET_HREF },
        )
        assertEquals(
            "the expected highlight row must BE the tapped row for a unique href",
            TARGET_ROW_INDEX, EXPECTED_HIGHLIGHT_ROW,
        )
        assertEquals(
            "the pinned target href is no longer the LAST row carrying it — foliateTocIndexFor is " +
                "last-match-wins, so the expected highlight row would be a different one",
            EXPECTED_HIGHLIGHT_ROW, hrefs.indexOfLast { it == TARGET_HREF },
        )
        assertNotEquals(
            "the pinned target shares the opening chapter's href — the jump would be a no-op",
            hrefs.first(), hrefs[TARGET_ROW_INDEX],
        )
    }

    /**
     * A stable digest of the whole flattened TOC: every row's `depth`, `title` and `href`, in order.
     * Reordering two rows, dropping one, changing a title's whitespace or re-encoding an href all
     * change it.
     *
     * The separators are the literal control characters **U+0001** (between a row's three fields) and
     * **U+0002** (between rows) — invisible in this source, so they are named here rather than left to
     * be discovered. They are chosen because neither can occur in an NCX label or in a KF8/MOBI6/EPUB
     * href, which is what makes the encoding injective: no two different TOCs can serialize alike.
     */
    private fun tocDigest(rows: List<TocEntry>): String {
        val canonical = rows.joinToString("") { row ->
            "${row.depth}${row.title}${row.canonicalLocator.href}"
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(canonical.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    private fun forceViewport(webView: WebView) {
        val metrics = inst.targetContext.resources.displayMetrics
        val width = if (metrics.widthPixels > 0) metrics.widthPixels else 1080
        val height = if (metrics.heightPixels > 0) metrics.heightPixels else 1920
        webView.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
        )
        webView.layout(0, 0, width, height)
    }

    // ---- the production entry point ---------------------------------------------------------------

    /**
     * THE PRODUCTION ENTRY POINT: launch the manifest LAUNCHER activity, find [book] in the Library
     * grid by its visible title, tap it, and run [block] with the reader that tap opened.
     *
     * Identity is checked twice, because "an AZW3 reader is resumed" is not the same claim as "the tap
     * I just made opened THIS book": the reader stack is drained first (a survivor from an earlier
     * method would otherwise be mistaken for this one's), and the reader that appears must carry
     * [book]'s fingerprint in the production intent extra.
     */
    private fun openThroughLibrary(book: Book, block: (Azw3ReaderActivity) -> Unit) {
        assertTrue(
            "a reader from an earlier test is still on the stack — this test's lookup would be ambiguous",
            finishAnyReader(),
        )
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(BOOK_TITLE, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(BOOK_TITLE, substring = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { resumedReader() != null }
            val reader = requireNotNull(resumedReader())
            try {
                assertEquals(
                    "the Library tap must have opened THIS book (production intent extra)",
                    book.fingerprintKey,
                    reader.readOnMain { it.intent.getStringExtra(Azw3ReaderActivity.EXTRA_FINGERPRINT_KEY) },
                )
                block(reader)
            } finally {
                finishAnyReader()
            }
        }
    }

    /**
     * Wait until the host is in [Azw3DocState.Loaded] — observed through the page-turn tap zones, which
     * the host composes ONLY inside its `is Azw3DocState.Loaded` branch — and then until a relocate has
     * round-tripped from the bundle and been PERSISTED by the production save path. The second wait is
     * what makes this a "the pipeline actually ran" gate rather than a "the state flipped" one; the
     * caller cleared the position first, so a non-null position can only be this session's.
     *
     * Existence, never `assertIsDisplayed`: bug #369 (GH #2080) is an open pre-existing failure of that
     * exact displayed-ness assertion on `azw3-next-zone`, and this suite must not inherit it.
     *
     * This is the ONLY place [bookReadyObserved] is set.
     */
    private fun awaitBookReady(book: Book) {
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("azw3-next-zone") > 0 && nodeCount("azw3-prev-zone") > 0 }
        compose.waitUntil(UI_TIMEOUT_MS) {
            runBlocking { app.container.repository.loadPosition(book.fingerprintKey) != null }
        }
        bookReadyObserved = true
        Log.i(TAG, "BOOK READY observed (Azw3DocState.Loaded + a persisted relocate) for ${book.fingerprintKey}")
    }

    /**
     * Run [block] only once [Azw3DocState.Loaded] has been observed. This is the #139 lesson made
     * structural rather than conventional: a criterion asserted while the pipeline is still loading —
     * or wedged — would pass trivially, so asserting early is a HARD failure here, not a review comment.
     */
    private fun <T> afterBookReady(criterion: String, block: () -> T): T {
        if (!bookReadyObserved) {
            throw AssertionError(
                "criterion '$criterion' was asserted BEFORE Azw3DocState.Loaded was observed — a " +
                    "stuck pipeline would pass it. Call awaitBookReady() first.",
            )
        }
        return block()
    }

    // ---- reader-stack helpers ---------------------------------------------------------------------

    /** Every [Azw3ReaderActivity] that is not yet DESTROYED — a reader parked in CREATED or STOPPED is
     *  still on the stack and would still be found by a later lookup. */
    private fun liveReaders(): List<Azw3ReaderActivity> {
        var found: List<Azw3ReaderActivity> = emptyList()
        inst.runOnMainSync {
            val monitor = ActivityLifecycleMonitorRegistry.getInstance()
            found = listOf(
                Stage.PRE_ON_CREATE, Stage.CREATED, Stage.STARTED,
                Stage.RESUMED, Stage.PAUSED, Stage.STOPPED, Stage.RESTARTED,
            ).flatMap { monitor.getActivitiesInStage(it) }
                .filterIsInstance<Azw3ReaderActivity>()
                .distinct()
        }
        return found
    }

    private fun resumedReader(): Azw3ReaderActivity? {
        var found: Azw3ReaderActivity? = null
        inst.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED)
                .filterIsInstance<Azw3ReaderActivity>()
                .firstOrNull()
        }
        return found
    }

    /** Finish every live reader and wait for the stack to drain; returns whether it fully drained. */
    private fun finishAnyReader(): Boolean {
        val readers = liveReaders()
        if (readers.isEmpty()) return true
        inst.runOnMainSync { readers.forEach { it.finish() } }
        val deadline = System.currentTimeMillis() + 20_000
        while (liveReaders().isNotEmpty() && System.currentTimeMillis() < deadline) Thread.sleep(POLL_MS)
        return liveReaders().isEmpty()
    }

    private fun <T> Azw3ReaderActivity.readOnMain(block: (Azw3ReaderActivity) -> T): T {
        val activity = this
        var value: Any? = null
        inst.runOnMainSync { value = block(activity) }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    // ---- position (the production save path is the corroborating motion evidence) -----------------

    private fun persistedPosition(book: Book): Position = runBlocking {
        val locator = app.container.repository.loadPosition(book.fingerprintKey)?.legacyLocator
        Position(cfi = locator?.cfi, progression = locator?.progression)
    }

    /**
     * The persisted position once it has HELD STILL for a continuous [SETTLE_HOLD_MS].
     *
     * What this does and does not establish (Gate-4 R1 Low — an earlier revision claimed more): it
     * shows the reader was not moving across that window, over BOTH persisted fields rather than the
     * progression alone. It cannot rule out a later relocate on its own — that is why the caller
     * re-checks this baseline is still current at the instant of the tap, and why the jump's own
     * evidence is the href-bound highlight rather than a bare position change.
     */
    private fun settledPosition(book: Book): Position = afterBookReady<Position>("4 — settle the pre-jump position") {
        val deadline = System.currentTimeMillis() + SETTLE_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            val candidate = persistedPosition(book)
            val holdUntil = System.currentTimeMillis() + SETTLE_HOLD_MS
            var held = true
            while (System.currentTimeMillis() < holdUntil) {
                Thread.sleep(POLL_MS)
                if (persistedPosition(book) != candidate) { held = false; break }
            }
            if (held) return@afterBookReady candidate
        }
        throw AssertionError(
            "the reported position never held still for ${SETTLE_HOLD_MS}ms within ${SETTLE_TIMEOUT_MS}ms",
        )
    }

    // ---- Contents-sheet helpers -------------------------------------------------------------------

    private fun nodeCount(tag: String) =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    private fun textExists(text: String) =
        compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** Open the Contents sheet the way a user does — the bottom-chrome Contents control. */
    private fun openContentsSheet() = afterBookReady("open the Contents sheet") {
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("chrome-contents") > 0 }
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).performClick()
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("toc-sheet-content") > 0 && nodeCount("toc-list") > 0 }
    }

    /** Bring row [index] into the lazily-composed window (the sheet composes only what is visible). */
    private fun scrollTocTo(index: Int) {
        compose.onNodeWithTag("toc-list", useUnmergedTree = true).performScrollToIndex(index)
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("toc-row-$index") > 0 }
    }

    /** Every text the row at [index] renders (the chapter number, the title, and any page label). */
    private fun rowTexts(index: Int): List<String> {
        val row = compose.onNodeWithTag("toc-row-$index", useUnmergedTree = true).fetchSemanticsNode()
        return row.children.flatMap { child ->
            child.config.getOrNull(SemanticsProperties.Text)?.map { it.text }.orEmpty()
        }
    }

    /**
     * The row at [index] renders the title the pipeline produced for that index — ORDER included, since
     * the assertion is per-index rather than "the title appears somewhere". This checks the sheet
     * against the provider; the NCX strings themselves are pinned separately by
     * [assertPinnedTocContent] and re-checked on screen by [assertRowShowsExactly], so neither rests on
     * the provider agreeing with itself.
     */
    private fun assertRowShowsPipelineTitle(index: Int, rows: List<TocEntry>) =
        assertRowShowsExactly(index, requireNotNull(rows[index].title) { "row $index has no title" })

    /** The row at [index] renders exactly [expected] (after the sheet's own title normalization). */
    private fun assertRowShowsExactly(index: Int, expected: String) {
        val wanted = displayTitle(expected)
        val texts = rowTexts(index)
        assertTrue(
            "Contents row $index shows $texts — expected the title '$wanted'",
            texts.any { it == wanted },
        )
    }

    /** The laid-out left edge of row [index]'s TITLE text — the indentation a reader actually sees, as
     *  opposed to the `depth` field that produced it. */
    private fun titleLeftInRow(index: Int, rows: List<TocEntry>): Float {
        val expected = displayTitle(requireNotNull(rows[index].title) { "row $index has no title" })
        val row = compose.onNodeWithTag("toc-row-$index", useUnmergedTree = true).fetchSemanticsNode()
        val child = row.children.firstOrNull { node ->
            node.config.getOrNull(SemanticsProperties.Text)?.any { it.text == expected } == true
        } ?: throw AssertionError("no '$expected' title text inside toc-row-$index (saw ${rowTexts(index)})")
        return child.positionInRoot.x
    }

    /** Whether the zero-size `toc-current-marker` sits inside row [index] — i.e. whether THAT row is
     *  the current chapter, not merely that some row is. */
    private fun rowIsCurrent(index: Int): Boolean {
        if (nodeCount("toc-row-$index") == 0) return false
        val row = compose.onNodeWithTag("toc-row-$index", useUnmergedTree = true).fetchSemanticsNode()
        fun walk(node: SemanticsNode): Boolean =
            node.config.getOrNull(SemanticsProperties.TestTag) == "toc-current-marker" ||
                node.children.any(::walk)
        return row.children.any(::walk)
    }

    /** The production sheet's per-row title normalization, mirrored (see [assertRowShowsExactly]). */
    private fun displayTitle(raw: String): String {
        fun Char.isBreak() = code in intArrayOf(0x0A, 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029)
        fun Char.isSpaceOrBreak() = isWhitespace() || isBreak()
        if (raw.none { it.isBreak() }) return raw.trim { it.isSpaceOrBreak() }
        val out = StringBuilder(raw.length)
        var i = 0
        while (i < raw.length) {
            if (!raw[i].isSpaceOrBreak()) { out.append(raw[i]); i++; continue }
            var end = i
            var spansBreak = false
            while (end < raw.length && raw[end].isSpaceOrBreak()) {
                if (raw[end].isBreak()) spansBreak = true
                end++
            }
            if (spansBreak) out.append(' ') else out.append(raw, i, end)
            i = end
        }
        return out.toString().trim { it.isSpaceOrBreak() }
    }

    private fun awaitUntil(timeoutMs: Long, what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return
            Thread.sleep(POLL_MS)
        }
        throw AssertionError("timed out after ${timeoutMs}ms waiting for $what")
    }
}
