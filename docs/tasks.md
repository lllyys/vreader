# Task Inbox

Describe issues in plain text below. The agent will triage them.

## Rules

> **Binding for this file.** The triage rules, classification policy, and record format below govern every change made to `docs/tasks.md`. AGENTS.md treats them as the authoritative inbox-triage workflow.

- **This file is an inbox, not a tracker.** Items stay here only until triaged.
- **User writes free-form descriptions** under the "New" section. No table, no formatting required.
- **Triage is classification only — not execution.** The agent does NOT fix bugs or implement features during triage. It only classifies and records.
- **Classification rules**:
  - Implemented but doesn't work correctly → **bug** → record in `docs/bugs.md`.
  - Never implemented → **feature** → record in `docs/features.md`.
  - Partially implemented + incorrect behavior → **bug** for the broken part; split off a separate **feature** for the missing capability. Link them.
  - Not a bug or feature (docs, config, chores, environment) → mark as `NO-ACTION` with reason.
  - Invalid or unclear → mark as `NEEDS-INFO` and ask the user.
- **Deduplication**: Before creating a new entry, search existing bugs and features. If a match exists:
  - Exact duplicate of an **open** bug (TODO/IN PROGRESS/REOPENED) → mark as `DUPLICATE OF bug #N` or `feature #N`.
  - Matches a **FIXED** bug → it's a regression, not a duplicate → mark as `REOPENED bug #N` and set that bug's status back to `REOPENED` in `docs/bugs.md`.
- **Agent workflow**: For each new item, the agent will:
  1. Read the description and investigate the codebase.
  2. Search `docs/bugs.md` and `docs/features.md` for existing matches.
  3. Classify per the rules above.
  4. Record based on classification:
     - **New bug/feature** → assign next available ID in the appropriate file. For bugs, also add an entry to `## Open Bug Details` in `docs/bugs.md` with the user's description (max 6 lines: repro, expected, actual).
     - **DUPLICATE** → no new ID; reference existing `bug #N` or `feature #N`.
     - **REOPENED** → no new ID; set existing bug's status to `REOPENED` in `docs/bugs.md`. Add/update `## Open Bug Details` entry with the new context.
     - **NO-ACTION / NEEDS-INFO** → no tracker entry; record only here.
  5. Move the description from "New" to "Triaged" with a one-line record:
     `YYYY-MM-DD | <bug #N / feature #N / DUPLICATE OF #N / REOPENED #N / NO-ACTION / NEEDS-INFO> | <reason>`
  6. If the result is **NO-ACTION** or **NEEDS-INFO**, prefix the line with `> ` (blockquote) so it stands out from resolved items.
  7. If the item is high-severity bug, release blocker, or major feature → also create a GitHub Issue (`gh issue create`) with appropriate labels. Add `GH: #123` to the tracker's Notes column.
- **NEEDS-INFO lifecycle**: If the user does not clarify within 7 days, the agent marks it `NO-ACTION (stale)` and moves on.
- **Never delete user content from New without explicit permission.** Items in New belong to the user. If an item matches an existing triage record, it is a re-report — the fix didn't work. REOPEN the bug and preserve the new information (crash logs, file paths, repro details). Do not treat re-reports as stale leftovers to clean up.

## New

<!-- Write issues here in plain text. One issue per line or paragraph. -->

~~2026-05-15 (Feature #31 round-4 verify, ambiguous cause — triage needed)~~ **RESOLVED 2026-05-15 (same-day, verify-cron round-5):** root cause identified as **Bug #191** (GH #682, severity:high) — `AutoPageTurner.interval` didSet infinite recursion under `@Observable`. Reader-open path initializes AutoPageTurner with the pre-launch UserDefaults `readerAutoPageTurnInterval=3.0`, triggers ~23.7k-frame stack-guard fault, app dies silently. Two crash reports from this session's test runs (`vreader-2026-05-15-085142.ips`, `…-084749.ips`) confirmed the AutoPageTurner._interval.setter ↔ _interval.didSet recursion. Triage question is settled: it's option (a) — Debug-build silent abort in book-open path. Filed as Bug #191 → bugs.md row + GH #682 with fix direction (replace public stored `interval` with `_intervalRaw` + computed clamping setter). DebugBridge `open?bookId=...` `currentBookId: null` symptom is a downstream effect: book-open path crashes BEFORE DebugReaderRegistry.current is populated, so the snapshot probe genuinely has no reader to query.

2026-05-17 (feature-cron — discovered, needs triage) | Feature #42 (AZW3/KF8 + Foliate-js unified reader engine) tracker inconsistency. `docs/features.md` row #42 is **PLANNED** with no `dev-docs/plans/*-feature-42-*.md` doc, but its GitHub mirror **#113 is CLOSED with stateReason COMPLETED** (closed 2026-05-04 by lllyys). A PLANNED feature must have an open GH issue per the mechanical-mirror rule — so the two disagree. Rows #54 and #57 (both TODO, written ~2026-05-13/14) still cite "Feature #42 (Foliate-js, PLANNED)" as a live dependency, so recent tracker intent treats #42 as pending; the #113 closure (2-week-old) looks like the stale artifact — likely closed when the AZW3/MOBI Foliate *spike* (`FoliateSpikeView`) shipped, prematurely marking the broader "replace the EPUB bridge too" scope as done. The feature cron cannot resolve this autonomously: it can't tell whether (a) #113 should be reopened so #42's implementation plan can be drafted, or (b) #42's scope was narrowed/superseded and row #42 should be reconciled (DONE/partial + a follow-up feature for the EPUB-engine swap). This blocks the feature cron — #42 is the only PLANNED feature, so every iteration that reaches the pick step stalls here (`.claude/cron-logs/feature.log` shows 6 consecutive `blocked` entries on 2026-05-17). Recommendation: decide #42's true status; if still wanted, reopen #113 and the cron will draft the Gate-1 plan next run.


## Triaged

2026-06-08 | bug #331 (GH #1574) | EPUB chapter-start drop-cap absent in continuous-scroll — `body > p:first-of-type::first-letter` cannot match the `.vreader-chapter-content` wrapper inside the #71 stitch `<section data-vreader-spine-index>`. FIXED v3.59.25 via `:is(body, .vreader-chapter-content) > p:first-of-type::first-letter`; device-verified (eval + screenshot).

2026-05-31 | triage batch (#63-#69, reader symptoms) | bug #292 (EPUB paged direction, GH #1300) · bug #293 (EPUB paged within-chapter resume, GH #1301) · bug #294 (CJK EPUB font / flatten-list gap, GH #1302) · REOPEN #283 (AZW3 scroll jump at chapter boundary, GH #1260) · REOPEN #287 (highlight tap tolerance — Foliate left out, GH #1268) · bug #295 (highlight tap opens empty panel — overlapping resolution, GH #1303) · bug #296 (annotations list can't scroll, #249 regression, GH #1304).

> 2026-05-31 | NO-ACTION | "What's the diff between highlights and notes? the list shows All=10 but there are 7 highlights and 8 notes" — works-as-designed (OVERLAP, not dedup). The Highlights chip counts HighlightRecords (7); the Notes chip counts standalone annotations + highlights carrying a non-empty note (8); the two chips OVERLAP. All = highlights + standalone-annotations as a plain sum (no dedup — `AnnotationStreamBuilder`), so each highlight is counted once → 10. 7+8≠15 because the 5 noted-highlights are counted in BOTH chips, not because All de-dupes. No defect.

2026-05-03 | feature #46 | WebDAV restore leaves library empty — backup is metadata-only by design (`BackupDataCollector.swift:12` "Books that no longer exist on the restoring device are silently skipped"). Inspected the user's ZIP (`2026-05-03T08-07-21Z_cfaff06e.vreader.zip`): 8 JSON sections, `metadata.json` records `bookCount: 5`, `positions.json` has 5 entries keyed by fingerprint, but no book files. On a fresh / empty library, restoration finds no matching books and silently no-ops. New feature scope: include book bytes in the archive so restore reconstructs the library.

2026-05-03 | DUPLICATE OF bug #110 | WebDAV Tailscale URL — same ATS issue captured in screenshot. FIXED in v3.10.9 (PR #139); end-to-end verified 2026-05-03 against rclone-backed `vreader-webdav-host` over Tailscale on simulator (build 10) — connection succeeds once system HTTP-proxy bypass includes `*.ts.net`. GH #136 closed.

2026-05-03 | NO-ACTION | WebDAV localhost auth failed (earlier 401, then 502 over Tailscale) — root cause was a system HTTP proxy on the Mac (`127.0.0.1:7897`, ClashX/Surge-style) whose bypass list excluded `*.ts.net`. iOS Simulator inherits the Mac's proxy → URLSession funnelled Tailscale traffic through the proxy → 502 Bad Gateway. Localhost worked because it was already in the bypass list. Not a vreader bug — user-side network config. Resolution: add `*.ts.net` and `100.64.0.0/10` to the proxy bypass list. Stale Docker WebDAV container (`bytemark/webdav` on port 8080) was also masking the rclone server's creds — removed in same session.

2026-04-12 | bug #109 | TXT chapter mode progress bar shows book progress (GH #31) — implemented but broken; fix landed in bfd8345 but never recorded in tracker. Status FIXED, GH issue still OPEN (needs closure).

2026-03-22 | bug #102 | EPUB fails to load chapter content — chapter navigation or content rendering broken

2026-03-21 | bug #101 | Imported 2000+ book sources but list empty and search button grey — BookSource records may not persist or UI not refreshing after import

2026-03-21 | bug #92 | AI only reads book title, not selected section — AIContextExtractor may not receive current locator or loaded text
2026-03-21 | bug #93 | Chat sessions not persisted — multi-turn history lost on panel dismiss or book close
2026-03-21 | bug #94 | Keyboard cannot be dismissed while chatting — AIChatView input field missing dismiss gesture
2026-03-21 | bug #95 | "Translate" opens AI Summarize panel instead of translation — wrong tab/view presented from readerTranslateRequested
2026-03-21 | bug #96 | TTS produces no sound and no error indication — AVSpeechSynthesizer may fail silently (no audio route, empty text, or system error)
2026-03-21 | bug #97 | TTS control bar overlaps bottom bar — TTSControlBar z-order or spacing conflict with reader bottom overlay

> 2026-03-21 | NEEDS-INFO | "Does TTS work for all languages?" — System TTS supports languages installed on device. HTTP TTS depends on provider. Which language failed?
> 2026-03-21 | feature #40 | TTS sentence highlighting — highlight current sentence/word while TTS reads. Not implemented
> 2026-03-21 | feature #41 | TTS auto-scroll/paginate — scroll content to follow TTS reading position. Not implemented
> 2026-03-21 | DUPLICATE OF bug #89 | Books still slow to open — already tracked
> 2026-03-21 | bug #98 | Text Transforms (simp/trad or replacement rules) fail — transform not applied or crashes
> 2026-03-21 | bug #99 | Search results not highlighted in some TXT files — highlight navigation may fail for specific encoding/chunking edge cases
> 2026-03-21 | bug #100 | Book source cannot be saved — BookSource persistence or UI save action broken

> 2026-03-21 | DUPLICATE OF bug #72 | Library nav bar appears during loading — already tracked and FIXED
> 2026-03-21 | bug #87 | PDF highlights still visible after deletion — readerHighlightRemoved handler missing in PDFReaderContainerView
> 2026-03-21 | NEEDS-INFO | "Is it normal for annotations to be exported as JSON?" — Yes, JSON is one of two export formats (Markdown + JSON). Is there a specific issue?
> 2026-03-21 | bug #88 | Exported annotations not highlighted when imported — import restores DB records but doesn't refresh visual highlights in reader
> 2026-03-21 | bug #89 | Books still slow to open — may be regression or remaining startup overhead after bug #64 fix
> 2026-03-21 | bug #90 | AI buttons visible when consent is off — AIReaderAvailability doesn't check consent; buttons should hide or show consent prompt
> 2026-03-21 | bug #91 | Blank panel when tapping Translate without AI configured — no guard for missing API key/consent before opening AI panel

2026-03-21 | bug #85 | Cannot add books to collections — no UI to assign books to a collection. CollectionSidebar can create/delete but not add books
2026-03-21 | bug #86 | Tags never shown — LibraryView passes allTags:[] to CollectionSidebar. No UI to add tags to books. PersistenceActor.addTag exists but unwired

2026-03-21 | bug #79 | Search panel still slow to open — deferred setup (bug #64) adds visible delay when search sheet opens
2026-03-21 | bug #80 | Cannot set custom book cover — PhotosPicker in context menu not working
2026-03-21 | bug #81 | Tap zones do nothing in native mode — center/left/right taps unresponsive after TapZoneOverlay removal (#70)

> 2026-03-21 | feature #39 | Custom background image for reader — never implemented, only solid colors/themes exist
> 2026-03-21 | DUPLICATE OF feature #37 | Per-book font size affects all books — per-book settings not implemented
> 2026-03-21 | DUPLICATE OF feature #12 | TXT files without TOC — TXT TOC generation never implemented

2026-03-21 | bug #77 | Cannot add highlight in native EPUB — regression of feature #11 (EPUB highlighting)
2026-03-21 | bug #78 | Highlight visual persists after deletion — removal doesn't clear rendered highlight

2026-03-21 | bug #76 | Annotations panel tab order — Contents (TOC) should be first, before Bookmarks

2026-03-21 | bug #75 | Sort preference not remembered across restarts — regression of feature #6 (PreferenceStore)

> 2026-03-21 | DUPLICATE OF feature #12 | TXT TOC not recognised — TXT TOC generation never implemented (forTXT returns empty)
> 2026-03-21 | bug #74 | EPUB TOC shows "Section XXX" instead of real chapter titles — uses spine items instead of nav/NCX document
> 2026-03-21 | feature #38 | Hierarchical/tree TOC display — currently flat list, user wants nested indented view

> 2026-03-21 | DUPLICATE OF feature #21 | Paged mode still scrolls — paginated reading never implemented, setting is a placeholder

2026-03-21 | bug #73 | Reader top bar hidden behind Dynamic Island — safe area inset zeroed by parent's ignoresSafeArea

2026-03-21 | bug #71 | Reader top bar (ReaderChromeBar) looks ugly — buttons too small, styling inconsistent with bottom bar
2026-03-21 | bug #72 | Library navigation bar still visible during reader loading transition

2026-03-21 | REOPENED bug #62 | Content still shifts down when top bar reappears — v2 fix (constant ignoresSafeArea) didn't resolve it

2026-03-21 | REOPENED bug #62 | Content shifts down when top bar appears — user re-reports after previous fix
2026-03-21 | bug #70 | Cannot scroll content in native mode, all formats — TapZoneModifier overlay likely blocking scroll gestures

2026-03-18 | bug #64 | All files and all formats are slow to load — V2 coordinator chain initialization adds overhead on every reader open
2026-03-18 | bug #62 | Content shifts down when top bar reappears — layout reflow from toggling `.ignoresSafeArea(.top)` with `isChromeVisible`
2026-03-18 | bug #63 | Progress bar unresponsive in Native mode — gesture conflict prevents scrubber drag and bar toggle

> 2026-03-15 | bug #56 | PDF crash after adding highlight and reopening — WI-008 restore flow may crash on reopen. Needs repro + crash log
> 2026-03-15 | bug #57 | EPUB and TXT font sizes render differently at same setting value — font size settings implemented but inconsistent cross-format
> 2026-03-15 | bug #58 | EPUB reading position only chapter-level, not intra-chapter — position save exists but loses scroll offset within chapter on reopen
> 2026-03-15 | bug #59 | Gap between progress bar (WI-004) and bottom bar — layout/spacing UI bug
> 2026-03-15 | feature #21 | Paginated reading mode with turnable pages — never implemented, currently scroll-only
> 2026-03-15 | REOPENED bug #43 + feature #22 | "No highlighting in search results" — Two issues: (a) highlight at destination not working in TXT/EPUB/PDF = regression of bug #43; (b) search result list doesn't highlight matching text = new feature #22

> 2026-03-15 | DUPLICATE OF feature #6 (DONE) | Library display format/sorting not remembered — Feature #6 implemented in WI-001 with PreferenceStore. If still broken after latest build, this is a regression — please retest
> 2026-03-15 | DUPLICATE OF feature #12 (DONE, MD only) | TXT TOC generation — D3 decision: TXT TOC deferred indefinitely (no reliable heading structure). MD TOC works via WI-005

2026-03-10 | feature #17 + DUPLICATE OF features #11, #13, #14 | EPUB/PDF text-like display — EPUB: highlighting/notes = feature #11 (TODO), theme/font = already works (bug #9), search = works, AI = features #13/#14 (TODO). PDF: highlighting/notes/theming = NEW feature #17 (PDFKit is read-only). Search = works
2026-03-10 | feature #18 | AI-powered contextual translation with bilingual view — never implemented. AIService.translate() exists but not wired. Needs translation UI, bilingual layout, toggle switch, API integration (claude -p or DeepL)
2026-03-10 | DUPLICATE OF feature #6 (expanded) | Library view persistence — sort order + display mode (grid/list) both covered by feature #6 (updated to include both)
2026-03-10 | feature #20 | Sort order reset/revert — never implemented. No reset option in sort picker menu

2026-03-10 | feature #12 | Auto-generate TOC for TXT/MD — TOCBuilder exists but forTXT()/forMD() return empty. Need heading extraction (MD) and heuristic chapter detection (TXT)
2026-03-10 | feature #13 | AI book/chapter summarization — full AIService pipeline exists and is functional but not wired to reader UI. Feature flag OFF
2026-03-10 | feature #14 | AI chat — talk to the book — single-question askQuestion() works. Missing multi-turn chat UI (message list, input field, history)
2026-03-10 | feature #15 | AI chat interface — general AI chat beyond book context. Overlaps with #14 but broader scope
2026-03-10 | feature #16 | Remote server integration (claude CLI) — no remote server code exists. Needs protocol design, networking, auth, UI
2026-03-10 | REOPENED bug #47 → FIXED v12 | Crash at frame #6 in setHighlightedText (textStorage.setAttributedString still crashes with active selection). Fixed: HighlightingLayoutManager.drawBackground() — zero text storage mutation for highlights. Applied to both TXTTextViewBridge and TXTChunkedReaderBridge.
2026-03-10 | REOPENED bug #47 → FIXED v11 | Crash at frame #45 in setHighlightedText (attributedText setter UIKit accessibility traversal with active selection). Fixed: textStorage.setAttributedString() + clear selection + isReplacingText guard. Audit applied: content-based persisted highlight comparison, removed unsafe attributedText fallback branches.
2026-03-10 | REOPENED bug #45 | "Last Read" sort resets on refresh/restart, only tracks last-opened book — v4 in-memory fix doesn't survive loadBooks(). Details updated in Open Bug Details in bugs.md
2026-03-10 | REOPENED bug #47 | Crash on highlight in test魔头.txt persists after v3 DispatchQueue.main.async fix. Details updated in Open Bug Details in bugs.md
2026-03-10 | bug #55 | Highlights not visible when file is reopened — no code to load persisted AnnotationRecords on file open. Details added to Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #45 | "Last Read" sort still stale after v3 in-memory fix — user re-reports with 3 test files. Details moved to Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #47 | Crash persists when highlighting in test魔头.txt — _os_unfair_lock_unowned_abort crash log preserved in Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #54 | Highlights still disappear in large CJK TXT after a few seconds — details moved to Open Bug Details in bugs.md
2026-03-09 | REOPENED bug #47 | App crashes when highlighting in test魔头.txt — user reports crash persists after previous fix
2026-03-09 | REOPENED bug #45 | Library sorting by "Last Read" still does not work — user reports issue persists after v2 event-driven fix
2026-03-09 | bug #54 | Highlight disappears in large CJK TXT after selecting other text — chunked reader cell reuse wipes highlight attributes + no persistent rendering
2026-03-08 | DUPLICATE OF bug #45 (FIXED) | "Last Read" sort — already fixed; stats recomputed on reader close + .onAppear refresh
2026-03-08 | feature #5 | Search highlight auto-dismiss — new behavior, never implemented
2026-03-08 | bug #46 | Manual highlight saves record but content not highlighted — implemented but broken
2026-03-09 | REOPENED bug #45 | Library still doesn't refresh sort after closing book — .onAppear fix insufficient
2026-03-09 | feature #6 | Sort preference persistence — never implemented, defaults to .title on every launch
2026-03-09 | bug #47 | App crashes after search/bookmark navigation + tap — implemented but crashes
2026-03-09 | bug #48 | Highlight/note edit menu missing in large TXT files — chunked reader lacks editMenuForTextIn
2026-03-09 | bug #49 | Note input box too narrow — TextField used instead of TextEditor
2026-03-09 | bug #50 | Highlight/annotation navigation fails — LocatorFactory.txtRange doesn't set charOffsetUTF16
2026-03-09 | bug #51 | Notes don't show original annotated text — AnnotationRecord missing selectedText field
2026-03-09 | bug #47 | App crashes on bookmark + double tap — same root cause as item 3 (merged into bug #47)
2026-03-09 | feature #7 | No visual feedback when adding bookmark — never implemented
2026-03-09 | feature #8 | Reading position scrubber/progress bar for large books — never implemented
2026-03-09 | feature #9 | Comprehensive book context menu — only "Delete" exists, needs info/share/rename
2026-03-09 | feature #10 | iCloud backup and restore — never implemented
2026-03-09 | REOPENED bug #45 | "Last Read" sort still stale after closing book — force refresh + 300ms delay still not working
2026-03-09 | DUPLICATE OF bug #47 (FIXED) | App crashed when highlighting TXT — same applyHighlight integer underflow crash path
2026-03-09 | feature #11 | EPUB cannot highlight text or add notes — never implemented for EPUB (WKWebView needs JS-based approach)
2026-03-09 | bug #52 | Large CJK TXT annotation panel navigation fails — chunkedReaderContent() doesn't pass scrollToOffset to bridge
2026-03-09 | bug #53 | Highlight visual not applied in large CJK TXT — chunkedReaderContent() doesn't pass highlightRange to bridge
