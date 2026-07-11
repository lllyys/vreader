package com.vreader.app.search

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator

/**
 * Feature #133 WI-9 — the `InBookSearchSheet` (vreader-search.jsx `SearchSheet`, 'This book' scope):
 * a `ModalBottomSheet` rendering the WI-8 [InBookSearchScreenState] — an autofocus query field + Cancel,
 * grouped result rows (chapter header + count, snippet with the matched term bold), recents, the
 * Indexing hint, and the NoResults empty state. Tapping a hit calls `onJump(hit)`; the sheet dismisses
 * ONLY on `JumpResult.Succeeded` — a `Failed` jump keeps it open with NO invented error surface
 * (rule 51 §nav-error-presentation). Append-on-scroll fires `onLoadMore` when the last group nears the
 * viewport (gated by `moreAvailable`), NO Load-More disclosure row.
 *
 * Tests target [InBookSearchSheetContent] directly (the `TocContentsSheetContent` precedent — a
 * `ModalBottomSheet`'s content renders in a separate window instrumented clicks reach unreliably on a
 * loaded host; the content composable is the testable seam).
 */
@RunWith(AndroidJUnit4::class)
class InBookSearchSheetTest {
    @get:Rule val compose = createComposeRule()

    /** Matches any node whose test tag starts with `inbook-result-` (a hit row, not a group header). */
    private val isResultRow = SemanticsMatcher("testTag starts with inbook-result-") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("inbook-result-") == true
    }

    private fun locator(offset: Int): Locator =
        Locator(contentSHA256 = "a".repeat(64), fileByteCount = 1024, format = "txt", charOffsetUTF16 = offset)

    private fun hit(snippet: String, ranges: List<IntRange>, section: String?, offset: Int = 0): InBookHit =
        InBookHit(
            sectionTitle = section,
            canonicalLocator = locator(offset),
            readiumLocatorJson = null,
            snippet = snippet,
            matchRanges = ranges,
        )

    private val bingleyGroups = listOf(
        InBookGroup(
            title = "Chapter 1",
            hits = listOf(
                hit("Netherfield is taken by Bingley, a young man", listOf(IntRange(24, 30)), "Chapter 1", 100),
            ),
        ),
        InBookGroup(
            title = "Chapter 3",
            hits = listOf(
                hit("Mr. Bingley had soon made himself acquainted", listOf(IntRange(4, 10)), "Chapter 3", 200),
                hit("as Bingley had now been gone a week", listOf(IntRange(3, 9)), "Chapter 3", 300),
            ),
        ),
    )

    private fun resultsState(moreAvailable: Boolean = false): InBookSearchScreenState =
        InBookSearchScreenState(
            query = "bingley",
            recents = listOf("Mr. Darcy", "Pemberley"),
            content = InBookSearchContent.Results(bingleyGroups, moreAvailable = moreAvailable),
        )

    // ── the query field + Cancel ───────────────────────────────────────

    @Test fun renders_queryField_andCancel() {
        var dismissed = false
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = { dismissed = true },
            )
        }
        compose.onNodeWithTag("inbook-search-field", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("inbook-search-cancel", useUnmergedTree = true).performClick()
        assertTrue("tapping Cancel must call onDismiss", dismissed)
    }

    @Test fun typingInField_emitsOnQueryChange() {
        var typed: String? = null
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = InBookSearchScreenState(query = "", recents = emptyList(), content = InBookSearchContent.Idle),
                query = "",
                onQueryChange = { typed = it },
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.onNodeWithTag("inbook-search-field", useUnmergedTree = true).performTextInput("darcy")
        assertEquals("darcy", typed)
    }

    // ── grouped results ────────────────────────────────────────────────

    @Test fun rendersGroupedHeaders_withCounts() {
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        // Two chapter groups, three total hit rows.
        compose.onNodeWithText("Chapter 1", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Chapter 3", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isResultRow, useUnmergedTree = true).assertCountEquals(3)
        // Per-group counts: "1 match" and "2 matches".
        compose.onNodeWithText("1 match", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("2 matches", useUnmergedTree = true).assertExists()
        // The design's overall summary line above the groups.
        compose.onNodeWithText("3 matches in 2 chapters", useUnmergedTree = true).assertExists()
    }

    @Test fun snippetText_isRendered() {
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        // The full snippet text is present (the matched sub-span is bolded via an AnnotatedString span).
        compose.onNodeWithText("Netherfield is taken by Bingley, a young man", useUnmergedTree = true).assertExists()
    }

    @Test fun cjkSnippet_withMatchRanges_rendersWithoutCrash() {
        val cjkGroups = listOf(
            InBookGroup(
                title = "第一章",
                hits = listOf(hit("关于编程的书很有意思", listOf(IntRange(2, 3)), "第一章", 0)),
            ),
        )
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Dark,
                bookTitle = "道诡异仙",
                state = InBookSearchScreenState(query = "编程", recents = emptyList(), content = InBookSearchContent.Results(cjkGroups, false)),
                query = "编程",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.onNodeWithText("第一章", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isResultRow, useUnmergedTree = true).assertCountEquals(1)
    }

    // ── tap a hit → onJump ─────────────────────────────────────────────

    @Test fun tapHit_invokesOnJumpWithHit() {
        var jumped: InBookHit? = null
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { jumped = it; JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.onNodeWithTag("inbook-result-1-0", useUnmergedTree = true).performClick()
        // Group index 1, hit index 0 → the first hit of "Chapter 3".
        assertEquals(bingleyGroups[1].hits[0], jumped)
    }

    @Test fun successfulJump_dismissesSheet() {
        var dismissed = false
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = { dismissed = true },
            )
        }
        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertTrue("a successful jump (Succeeded) must dismiss the sheet", dismissed)
    }

    @Test fun failedJump_keepsSheetOpen_noErrorSurface() {
        var dismissed = false
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Failed },
                onLoadMore = {},
                onDismiss = { dismissed = true },
            )
        }
        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertFalse("a failed jump (Failed) must NOT dismiss the sheet", dismissed)
        // The rows are still present and NO invented error surface was rendered (rule 51).
        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("inbook-jump-error", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── append-on-scroll ───────────────────────────────────────────────

    @Test fun moreAvailable_firesOnLoadMore_whenLastGroupComposed() {
        var loadMoreCount = 0
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(moreAvailable = true),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = { loadMoreCount++ },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        // The last group is composed on screen (small fixture) → append-on-scroll fires exactly once,
        // NO Load-More disclosure row is rendered.
        assertTrue("onLoadMore must fire when the last group nears the viewport and moreAvailable", loadMoreCount >= 1)
        compose.onAllNodesWithTag("inbook-load-more", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun noMoreAvailable_neverFiresOnLoadMore() {
        var loadMoreCount = 0
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = resultsState(moreAvailable = false),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = { loadMoreCount++ },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        assertEquals("moreAvailable=false must never fire onLoadMore", 0, loadMoreCount)
    }

    @Test fun appendGrowingTheLastGroup_reArmsOnLoadMore() {
        // `loadMore()` coalesces adjacent same-section hits, so a new page can grow the CURRENT last group's
        // hit count WITHOUT adding a new group. The trigger must re-arm on `(lastGroupIndex, hitCount)` so the
        // next page is still requested (round-2 audit Medium). Drive a growing tail group and assert a second
        // fire.
        var loadMoreCount = 0
        val state = androidx.compose.runtime.mutableStateOf(
            InBookSearchScreenState(
                query = "bingley",
                recents = emptyList(),
                content = InBookSearchContent.Results(
                    listOf(InBookGroup("Chapter 1", listOf(hit("a Bingley aside", listOf(IntRange(2, 8)), "Chapter 1", 1)))),
                    moreAvailable = true,
                ),
            ),
        )
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = state.value,
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = { loadMoreCount++ },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        val firstFire = loadMoreCount
        assertTrue("initial tail should fire onLoadMore", firstFire >= 1)
        // A next page grows the SAME last group (no new group) — the trigger must re-arm.
        state.value = state.value.copy(
            content = InBookSearchContent.Results(
                listOf(
                    InBookGroup(
                        "Chapter 1",
                        listOf(
                            hit("a Bingley aside", listOf(IntRange(2, 8)), "Chapter 1", 1),
                            hit("more Bingley later", listOf(IntRange(5, 11)), "Chapter 1", 2),
                        ),
                    ),
                ),
                moreAvailable = true,
            ),
        )
        compose.waitForIdle()
        assertTrue("growing the last group must re-arm + re-fire onLoadMore", loadMoreCount > firstFire)
    }

    // ── Indexing ───────────────────────────────────────────────────────

    @Test fun indexingContent_showsIndexingHint() {
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = InBookSearchScreenState(query = "bingley", recents = emptyList(), content = InBookSearchContent.Indexing),
                query = "bingley",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.onNodeWithTag("inbook-indexing", useUnmergedTree = true).assertExists()
        // Indexing is NOT a false NoResults.
        compose.onAllNodesWithTag("inbook-no-results", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── NoResults ──────────────────────────────────────────────────────

    @Test fun noResultsContent_showsEmptyState() {
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = InBookSearchScreenState(query = "zzz", recents = emptyList(), content = InBookSearchContent.NoResults),
                query = "zzz",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.onNodeWithTag("inbook-no-results", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isResultRow, useUnmergedTree = true).assertCountEquals(0)
    }

    // ── recents (Idle) ─────────────────────────────────────────────────

    @Test fun idleContent_rendersRecents_tapFillsQuery() {
        var picked: String? = null
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = InBookSearchScreenState(query = "", recents = listOf("Mr. Darcy", "Pemberley"), content = InBookSearchContent.Idle),
                query = "",
                onQueryChange = {},
                onPickRecent = { picked = it },
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.onNodeWithText("Mr. Darcy", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("inbook-recent-1", useUnmergedTree = true).performClick()
        assertEquals("tapping a recent must call onPickRecent with its text", "Pemberley", picked)
    }

    @Test fun idleContent_noRecents_rendersNoRecentRows() {
        compose.setContent {
            InBookSearchSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = InBookSearchScreenState(query = "", recents = emptyList(), content = InBookSearchContent.Idle),
                query = "",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        // No recents → no recent rows and no invented "no recents" chrome (rule 51).
        compose.onAllNodesWithTag("inbook-recent-0", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── smoke: the ModalBottomSheet wrapper renders its content ────────

    @Test fun modalBottomSheetWrapper_rendersField() {
        compose.setContent {
            InBookSearchSheet(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                state = InBookSearchScreenState(query = "", recents = emptyList(), content = InBookSearchContent.Idle),
                query = "",
                onQueryChange = {},
                onPickRecent = {},
                onJump = { JumpResult.Succeeded },
                onLoadMore = {},
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.onNodeWithTag("inbook-search-field").assertExists()
    }
}
