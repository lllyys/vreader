---
branch: feat/132-wi5-chrome-scaffold
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-5 (reader chrome scaffold + state)

## Auditor / method

Codex was unavailable (usage-limit / quota error: `RUN-CODEX RESULT: FAILED (codex exit 1)` —
"You've hit your usage limit"). Per rule 47 "Manual fallback when AI auditor unavailable" this is an
evidence-bearing manual audit by a fresh read of the changed files against the plan + collaborators.

### Files read (production + collaborators)

- `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt` (extended)
- `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt` (new)
- `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt` (new)
- `reader/chrome/ReaderTopChrome.kt` (WI-2, read-only — signature consumed)
- `reader/nav/TocContentsSheet.kt` + `reader/nav/TocEntry.kt` (WI-3/WI-1 — consumed)
- `annotations/AnnotationsReviewSheet.kt` + `AnnotationsSnapshot.kt` + `AnnotationItem.kt` (WI-4/WI-6b — consumed)
- `library/CollectionSheets.kt` (#127 `SheetRoute`/`SheetRouteSaver` — the Saver precedent mirrored)
- `identity/.../vreader/contracts/Locator.kt`, `annotations/Annotation.kt` (record/Locator shapes for tests)
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx` (design authority, toolbar block)

### Symbols / signatures verified against the live code

- `ReaderBottomChrome` #129 signature (theme, progress, displayPage, totalPages, onScrub, onOpenDisplay,
  modifier, extraSlot) — the two new params `onOpenContents`/`onOpenNotes` are `(() -> Unit)? = null`,
  inserted AFTER `modifier`; the existing `Display` slot + `extraSlot` are untouched. A Display-only
  caller compiles unchanged (the existing `ReaderBottomChromeUiTest` compiled clean under
  `:app:compileDebugAndroidTestKotlin`).
- `ReaderTopChrome(theme, title, onBack, onSearch?, onMore?, bookmarkSlot?, modifier)` — the scaffold
  wires each param correctly; `topBookmarkSlot` passes through null in #132 (#135 fills it).
- `TocContentsSheet(theme, bookTitle, entries, currentTocIndex, onJump, onDismiss, modifier)` — exact
  match; `testTag("toc-sheet")` asserted by the scaffold test.
- `AnnotationsReviewSheet(theme, snapshot, onShareAll, onJumpToAnnotation, onDismiss, modifier)` — exact
  match; `testTag("annotations-sheet")` asserted; `onJumpToAnnotation` nullable (capability gate).
- `AnnotationsSnapshot(highlights, notes)`, `TocEntry(title, depth, pageLabel, canonicalLocator,
  epubReadiumLocator)`, `Locator(contentSHA256, fileByteCount, format, ...)` — all confirmed for the
  test fixtures.
- `SheetRouteSaver: Saver<SheetRoute, String>` (#127) — `ReaderChromeStateSaver` mirrors it exactly
  (string-encode, total restore with else-fallback, never throws).

## Findings

### (1) ReaderBottomChrome extension is purely additive — PASS

Nullable-default `onOpenContents`/`onOpenNotes`; Contents renders only when `onOpenContents != null`,
Notes only when `onOpenNotes != null` (the #129 no-dead-controls rule). The `Display` slot and all prior
params are preserved verbatim; AI is still omitted. Back-compat is proven two ways: the compile of the
androidTest suite (which includes the #129 `ReaderBottomChromeUiTest` Display-only callers) succeeded,
and `ReaderBottomChromeSlotsTest.displayOnlyCaller_stillRenders_slotsAbsent_backCompat` asserts a
Display-only caller renders with Contents/Notes/AI absent. NOTE: #131's `onOpenBilingual` Translate slot
is NOT present in this baseline and was correctly NOT added (brief-mandated; the plan's mention of it is
a future-integration concern, not this baseline).

### (2) ReaderChromeStateSaver round-trip + total restore — PASS

`save` encodes `"<visible>|<sheet>"`; `restore` is total — `parts.size != 2` -> fallback
(chromeVisible=false, sheet=None); `toBooleanStrictOrNull() ?: false`; unknown sheet token ->
`ReaderSheet.None`. Never throws. 10 JVM tests green (round-trips of every visible×sheet combo + empty /
garbage / wrong-separator / unknown-sheet tokens + the default-state assertion). Mirrors #127 exactly.

### (3) ReaderChromeScaffold behavior — PASS

Contents control hidden when `tocEntries.isEmpty()` (scaffold passes a null open callback into the
bottom-chrome slot); center-tap on the body toggles `chromeVisible` (reads `chromeState.value` fresh);
`ReaderSheet.Toc` -> `TocContentsSheet`, `ReaderSheet.Notes` -> `AnnotationsReviewSheet`; dismiss returns
to `ReaderSheet.None`. NO bookmark route/params (correctly deferred to #135). The top/bottom bars hide
together with `chromeVisible`, so an open sheet is still reachable via its own dismiss.

### (4) rule-51 design fidelity — PASS

`vreader-reader.jsx` toolbar is `[Contents(TOC icon), Notes(Highlighter), Display(Aa), AI(Sparkle)]` in a
`space-around` row of icon-above-label buttons. The impl renders Contents (FormatListBulleted) ·
Notes (BorderColor/highlighter) · Display (Aa serif glyph, unchanged #129), AI omitted. Icon-over-label
column matches the design's `<b.icon/> + <span>`. No invented chrome; BorderColor is already the
project's highlighter glyph (SelectionPopover, AnnotationsReviewSheet empty state).

### (5) pure composables, state hoisted — PASS

`ReaderChromeScaffold` is a pure function of the hoisted `MutableState<ReaderChromeState>` + callbacks;
no `remember`-ed private state, no side effects. `ReaderBottomChrome`/`ToolbarIconButton` are pure.
`ReaderChromeState`/`ReaderSheet` are value types; the Saver is pure String logic. Files are 63 / 118 /
187 lines — well under 300.

## Audit-driven change (round 1)

Hardened the scaffold's sheet open/dismiss transitions to read `chromeState.value` FRESH via a local
`openSheet(sheet)` helper (was `state.copy(...)` off the composed-time snapshot), so a rapid
open/dismiss cannot clobber a concurrent visibility toggle. Behavior-preserving; the center-tap toggle
already used the fresh-read pattern. Test gate re-run green after the change
(`RUN-ANDROID-TESTS RESULT: SUCCEEDED`, Saver 10/10, androidTest compiles).

## Edge cases checked

Empty TOC (Contents hidden), empty annotations snapshot (Notes sheet renders its empty state),
garbage/empty/wrong-separator/unknown-sheet Saver tokens (fallback, never throws), Display-only
back-compat caller, AI never rendered, rapid sheet open/dismiss vs visibility toggle (fresh-read fix).

## Risks accepted

The two instrumented tests (`ReaderBottomChromeSlotsTest`, `ReaderChromeScaffoldTest`) COMPILE in this
lane but their live Compose run defers to WI-6's connected slice (the TXT host is the first to render the
scaffold — the #128 WI-7 precedent; a modal `ModalBottomSheet` renders in a separate window that
instrumented assertions reach reliably only from a full host). The pure-String Saver logic (the real
regression risk) is fully covered by the JVM suite that runs here.

## Verdict

**ship-as-is** — additive, design-faithful, state-hoisted, one audit-driven hardening applied and
re-tested. No open Critical/High/Medium findings.
