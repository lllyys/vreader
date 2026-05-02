#  Feature Tracker

Track features to be implemented here. Must be planned before implementation.

## Rules

- **Bugs vs features**: If something was implemented but doesn't work correctly, it is a **bug** — track it in `docs/bugs.md`. If something was never implemented, it is a **feature** — track it here. Never mix them.
- **Partial implementations**: If something is partially implemented, the broken part is a bug in `docs/bugs.md`; the missing capability is a feature here. Link them.
- **Cross-links**: When a bug fix resolves a feature, update the feature status to `DONE` with note `Resolved by bug #N`. When a feature depends on a bug fix, use `TODO` status with note `Blocked by bug #N`.
- **Plan before implementation**: Every feature must be planned before any code is written. Status must reach `PLANNED` before moving to `IN PROGRESS`. A plan requires the fields listed in the "Plan Template" section below.
- **Exception — resolved by bug fix**: If a bug fix incidentally delivers a feature, the feature may be set to `DONE` with `Resolved by bug #N` without a full plan. The bug's own cause/solution/lesson records serve as documentation.

## How to use

1. Add features as you identify them (fill in Summary and Area at minimum)
2. Plan the feature (fill in required plan fields above) → set status to `PLANNED`
3. Tell the agent: "implement feature #N" to start implementation
4. Agent updates Status when done

- **GitHub Issue closure** (post-merge finalizer — see `AGENTS.md` for full policy):
  - If the feature has a `GH: #N` in Notes, close the GitHub Issue only after:
    1. All acceptance criteria met and status is DONE in this file.
    2. Implementation is merged to `main`.
    3. Closure comment posted with commit SHA and acceptance result.
  - Partial delivery: keep GitHub Issue open; use checklist or split follow-ups.
  - PRs use `Refs #N`, not `Fixes #N` (prevents premature auto-close).

## Statuses

- `TODO` — not started
- `PLANNED` — plan complete (problem, scope, edge cases, tests, acceptance criteria), ready to implement
- `IN PROGRESS` — being worked on
- `DONE` — implemented; correctness not yet verified end-to-end
- `VERIFIED` — covered by an automated end-to-end test (XCUITest + DebugBridge) or by an explicit on-device manual verification log
- `DEFERRED` — postponed to a later milestone
- `WONT DO` — out of scope or rejected

## Plan Template

Before setting a feature to `PLANNED`, fill in these fields in a sub-section under the feature table (e.g., `### Feature #1 — Plan`):

- **Problem**: What user need does this address?
- **Scope**: What is included and excluded?
- **Edge cases**: Empty input, nil, boundary values, concurrent access, format-specific behavior.
- **Test plan**: What tests will verify the feature?
- **Acceptance criteria**: How do we know it's done?

## Features

| #  | Summary                                                       | Area          | Priority | Status    | Notes                                                                                                                                                                            |
| -- | ------------------------------------------------------------- | ------------- | -------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | Edit and delete bookmarks                                     | Reader/*     | High     | DONE      | Rename via context menu (bug #42), delete via swipe + context menu. BookmarkListView has full CRUD UI                                                                            |
| 2  | Highlight search result at destination                        | Search/*     | Medium   | DONE      | Resolved by bug #43 — yellow background highlight, auto-clears after 3s                                                                                                          |
| 3  | Manual text highlighting                                      | Reader/*     | High     | DONE      | Resolved by bug #44 — Highlight action added to UITextView edit menu                                                                                                             |
| 4  | Add notes/annotations to text                                 | Reader/*     | Medium   | DONE      | Resolved by bug #44 — Add Note action added to UITextView edit menu                                                                                                              |
| 5  | Search highlight auto-dismiss on next action                  | Search/*     | Low      | TODO      | WI-003 code committed. Unchecked on device                                                                                                                                       |
| 6  | Persist library view preferences across app restarts          | Library/*    | Medium   | DONE      | WI-001. PreferenceStore + UserDefaults. 10 tests                                                                                                                                 |
| 7  | Visual feedback when adding a bookmark                        | Reader/*     | Low      | DONE      | WI-002. UIImpactFeedbackGenerator(.light). 5 tests                                                                                                                               |
| 8  | Reading position scrubber/progress bar                        | Reader/*     | Medium   | DONE      | WI-004a-d. ReadingProgressBar + per-format wiring (TXT/MD/PDF/EPUB). 108 tests                                                                                                   |
| 9  | Comprehensive book context menu in library                    | Library/*    | Medium   | DONE      | WI-006. Info/Share/Delete + BookInfoSheet. 24 tests                                                                                                                              |
| 10 | iCloud backup and restore                                     | Settings/*   | —        | WONT DO   | Not needed. WebDAV (#29) covers backup needs.                                                                                                                                    |
| 11 | EPUB text highlighting and note-taking                        | EPUB/*       | High     | DONE      | WI-C00 → WI-007. Bug #77 FIXED (JS buffering). Needs device verification                                                                                                         |
| 12 | Auto-generate TOC for MD files                                | Reader/*     | Medium   | DONE      | WI-005. Regex heading extraction, fenced code block skip, correct UTF-16 offsets. 25 tests                                                                                       |
| 13 | AI book/chapter summarization                                 | AI/*         | High     | DONE      | WI-D00 → WI-009 → WI-010. Bug #92 FIXED (encoding). Device verified: non-UTF-8 TXT → AI summarize shows real content                                                            |
| 14 | AI chat — talk to the book                                    | AI/*         | High     | DONE      | WI-D00 → WI-009 → WI-010 → WI-011. Multi-turn chat with book context via AIChatViewModel. Chat tab in AIReaderPanel                                                              |
| 15 | AI chat interface (general)                                   | AI/*         | Medium   | DONE      | WI-013. General chat (nil bookFingerprint). Entry point in LibraryView toolbar. 8 tests                                                                                          |
| 16 | Remote server integration (claude CLI / directory management) | Server/*     | High     | DEFERRED  | WI-014 (design only). Design doc at docs/codex-plans/remote-server-design.md                                                                                                     |
| 17 | PDF text highlighting, annotation, and theming                | PDF/*        | High     | DONE      | WI-C00 → WI-008. PDFAnnotationBridge + selection detection + persist/restore. 44 tests                                                                                           |
| 18 | AI-powered contextual translation with bilingual view         | AI/*         | High     | DONE      | WI-012. Bug #95 FIXED (initialTab). Device verified: Select word → Translate → opens Translate tab                                                                                |
| 19 | ~~Merged into feature #6~~                                    | Library/*    | —        | DUPLICATE | Display mode persistence merged into feature #6 (library view preferences)                                                                                                       |
| 20 | Sort order reset/revert to default                            | Library/*    | Low      | DONE      | WI-001 (bundled with #6). "Default" option in sort picker                                                                                                                        |
| 21 | Paginated reading mode with turnable pages                    | Reader/*     | High     | DONE      | B04-B13. Bug #82 FIXED (preserve navigator). Needs device verification                                                                                                           |
| 22 | Highlight matching text in search result list                 | Search/*     | Medium   | DONE      | Bold/highlight query term in search result row snippets                                                                                                                          |
| 23 | Auto-generate TOC for TXT files                               | Reader/*     | Medium   | DONE      | B01. Bug #83 FIXED (14/25 rules enabled). Needs device verification                                                                                                              |
| 24 | Book source scraping (web novels)                             | BookSource/* | High     | DONE      | D01-D07. Bugs #100, #101 FIXED (modelContext.save + SchemaV4). Device verified: Import JSON → sources visible → search works                                                     |
| 25 | Configurable tap zones                                        | Reader/*     | High     | DONE      | A03. TapZone section in ReaderSettingsPanel — 3 Pickers (left/center/right → TapAction). TapZoneStore wired through settings sheet                                               |
| 26 | Text-to-Speech read aloud                                     | Reader/*     | High     | DONE      | B03+E06. Bugs #96, #97 FIXED. Needs device verification                                                                                                                          |
| 27 | Content replacement rules                                     | Reader/*     | Low      | DONE      | E03. Bug #98 FIXED (sourceText + didSet re-apply). Needs device verification                                                                                                     |
| 28 | Simplified/Traditional Chinese conversion                     | Reader/*     | Medium   | DONE      | E04. Bug #98 FIXED (sourceText + didSet re-apply). Needs device verification                                                                                                     |
| 29 | WebDAV backup and restore                                     | Settings/*   | Medium   | TODO      | E01 code committed. Not verified on device                                                                                                                                       |
| 30 | Custom book covers                                            | Library/*    | Medium   | DONE      | A01. CustomCoverStore + PhotosPicker in context menu                                                                                                                             |
| 31 | Auto page turning                                             | Reader/*     | Low      | DONE      | B10. Unblocked by bug #82 fix. Needs device verification                                                                                                                         |
| 32 | Reading theme backgrounds                                     | Reader/*     | Medium   | DONE      | A04. PhotosPicker + opacity slider + remove button in ReaderSettingsPanel. ThemeBackgroundStore saves/loads per-theme. Needs device verification                                  |
| 33 | Dictionary / define / translate-on-select                     | Reader/*     | High     | DONE      | B02. DictionaryLookup + UIReferenceLibraryViewController + AI translate                                                                                                          |
| 34 | Collections / tags / series organization                      | Library/*    | Medium   | DONE      | C01. Bugs #85, #86 FIXED. Needs device verification                                                                                                                              |
| 35 | Export / import annotations                                   | Reader/*     | Medium   | DONE      | C02+C03. Bug #88 FIXED (import highlight refresh). Needs device verification                                                                                                     |
| 36 | OPDS catalog support                                          | BookSource/* | Medium   | TODO      | C04 code committed. Not verified on device                                                                                                                                       |
| 37 | Per-book reading settings                                     | Reader/*     | Low      | DONE      | A05. Bug #84 FIXED (applyResolvedSettings + suppressPersistence). Needs device verification                                                                                      |
| 38 | Hierarchical/tree TOC display                                 | Reader/*     | Low      | DONE      | TOCListView indents by entry.level. PDF/MD builders populate nonzero levels. Not a disclosure tree but visual nesting works                                                      |
| 39 | ~~Merged into feature #32~~                                   | Reader/*     | —        | DUPLICATE | Same gap: background image picker UI needed. Merged into #32                                                                                                                     |
| 40 | TTS sentence highlighting                                     | Reader/*     | Medium   | DONE      | TTSHighlightCoordinator: NLTokenizer sentences → binary search → uiState.highlightRange. TXT/MD wired via onChange(ttsService). Needs device verification                        |
| 41 | TTS auto-scroll/paginate                                      | Reader/*     | Medium   | DONE      | TTSHighlightCoordinator sets uiState.scrollToOffset from sentence start. TXT/MD only via same onChange wiring. Needs device verification                                         |
| 42 | AZW3/KF8 + Foliate-js unified reader engine                   | Reader/*     | High     | PLANNED   | Replace EPUB bridge with Foliate-js `<foliate-view>`. EPUB+AZW3/MOBI via one engine. PDF/TXT unchanged. GH: #113                                                                |
| 43 | Extract and display cover images from EPUB/AZW3               | Library/*    | Medium   | DONE      | EPUB OPF + AZW3 MOBI header parsing. 46 tests. Bug #107 for white-edge padding. GH: #121                                                                                        |
| 44 | DebugBridge — debug-only URL scheme + state dumper for autonomous testing | DevTools/*  | High | DONE | DEBUG-only `vreader-debug://` handler with 7 commands (reset/seed/theme/open/settle/snapshot/eval). Active-reader registry, fixture catalog, stable error codes, release-gate script. 93 unit tests. Doc at `dev-docs/debug-bridge.md`. Future: per-format settle hooks, real WKWebView evaluator on EPUB/AZW3, selection probe field. |
| 45 | Verification harness sweep — retire the "Needs device verification" backlog | DevTools/* | High | PLANNED | XCUITest + DebugBridge recipes for 13 of 15 simulator-automatable backlog items. Adds VERIFIED status. Depends on #44. See plan below. |

### Feature #44 — DebugBridge — Plan

- **Problem**: Autonomous AI debug loop and XCUITest regression suite both need cheap, deterministic state setup and ground-truth state inspection. Currently every repro requires manual UI-driving (open library → tap book → scroll → set theme → ...). For WKWebView-heavy bugs (Foliate-js highlights, EPUB rendering, page navigation) there is no external way to read what the webview actually rendered. Vision-only inspection is too flaky for the hard bugs, which is the class that piles up in `docs/bugs.md`.

- **Scope**:
  - **Included**: A `#if DEBUG`-gated `DebugBridge` that handles the `vreader-debug://` URL scheme via `.onOpenURL` on `VReaderApp`. Commands: `reset`, `seed?fixture=<name>`, `open?bookId=<uuid>&cfi=<x>` (plus equivalent for TXT/MD/PDF positions), `theme?mode=<dark|light>&fontSize=<n>`, `settle?token=<id>` (writes ready-sentinel after Foliate `relocate` + native layout settles), `snapshot?dest=<file>` (semantic state JSON to app container), `eval?bridge=foliate&js=<base64>` (active WKWebView JS eval, result to container). Bundle a small set of fixture books in `vreader/Resources/DebugFixtures/` (alice.epub, war-and-peace.txt, sample.azw3, sample.pdf). Document one repro recipe per existing open bug (#107, #108, plus a few of the "Needs device verification" features) in `dev-docs/debug-bridge.md`.
  - **Excluded**: No release-build code path. No remote control over network. No authentication (device-local only, DEBUG-only). No fixture *editing* in the bridge — fixtures are read-only bundle resources. No replacement of XCUITest — DebugBridge is a state-setup peer, not a test runner. No screenshot capture from inside the bridge — caller uses `xcrun simctl io booted screenshot`. No mutation of SwiftData beyond the `reset` and `seed` commands.
  - **Out of scope, deferred**: Recording-and-replay of user gestures. Mocking the network layer. AI Genie state injection.

- **Edge cases**:
  - URL scheme called in non-DEBUG build → ignore silently (handler not registered).
  - `seed` called twice with the same fixture → idempotent (no duplicate library row).
  - `open` with unknown `bookId` → write error JSON to `lastError.json`, do not crash.
  - `eval` JS that throws → capture exception in result JSON; do not propagate to app.
  - `eval` called when no webview is active → return `{ "error": "no active webview" }`.
  - `settle` called when render never completes (e.g., corrupt EPUB) → timeout sentinel after 30s with `{ "error": "settle timeout", "phase": "<lastPhase>" }`.
  - Concurrent `vreader-debug://` calls → serialize via `MainActor` queue; later calls wait.
  - Snapshot during in-flight TTS or AI streaming → state JSON includes a `transientOps` array so caller can decide whether to retry.
  - Filesystem write failures on `Caches/` → log and continue; do not block app.
  - `reset` while a book is open → close reader first, dismiss sheets, then wipe.
  - Build configuration with `DEBUG` undefined but URL scheme registered (e.g., archive build): URL scheme registration also `#if DEBUG`-gated in Info.plist via Active Compilation Conditions check at build phase. Verify no `vreader-debug` entry leaks into Release.app.
  - `snapshot` JSON must exclude PII (no fingerprinting hashes of book content beyond what's already in SwiftData).

- **Test plan**:
  - Unit: `DebugBridgeRouterTests` — URL parsing for each command, error paths (malformed URL, missing required params, unknown command).
  - Unit: `DebugStateSnapshotterTests` — JSON shape stability against a fixed model (golden JSON), nil/optional handling, `transientOps` array population.
  - Unit: `DebugFixtureLoaderTests` — idempotent `seed`, missing fixture name → error, fixture path resolution.
  - Integration: `DebugBridgeIntegrationTests` (XCUITest) — launch with `vreader-debug://reset` then `seed` then `open` then `snapshot`, read back container JSON, assert state matches expected.
  - Integration: `DebugBridgeFoliateEvalTests` — open EPUB fixture, `eval` returns `document.querySelectorAll('.foliate-highlight').length` correctly after creating a highlight.
  - Build gate: a CI step asserts `vreader-debug` is **not** present in the Release bundle's Info.plist. Fail the build if found.
  - Manual verification: one repro recipe in `dev-docs/debug-bridge.md` exercised end-to-end against current open bugs.

- **Acceptance criteria**:
  - DEBUG build registers `vreader-debug://` and handles all six commands above with correct success/error JSON in the app container.
  - Release build has zero `vreader-debug` references (verified by CI grep + Info.plist check).
  - `xcrun simctl openurl booted vreader-debug://snapshot?dest=state.json` followed by `simctl get_app_container booted <bundle-id> data` produces a valid JSON file with the documented schema (currentBookId, format, cfi/page, theme, fontSize, selection, highlightCount, renderPhase, lastError).
  - `settle` reliably blocks until the Foliate `relocate` event has fired and a frame has been committed (no mid-frame screenshots in the documented happy-path repro).
  - All unit + integration tests pass under `xcodebuild test -only-testing:vreaderTests` and `-only-testing:vreaderUITests`.
  - `dev-docs/debug-bridge.md` documents the URL grammar, JSON schema, fixture catalogue, and one worked repro per currently-open bug.
  - LOC under ~300 across new files (router, snapshotter, fixture loader, Foliate eval adapter); no file exceeds the project's 300-line guideline.

### Feature #45 — Verification harness sweep — Plan

- **Problem**: 15 features in `docs/features.md` and many bugs in `docs/bugs.md` are marked "Needs device verification" or "Not verified on device". This backlog grows monotonically because every release adds new entries faster than humans can verify the old ones, and the verification work is repetitive UI-driving that humans hate. Result: tracker statuses lie (`DONE` actually means "code shipped, untested"), regressions ride to release, and pre-release manual passes balloon. Currently 16 occurrences in `docs/features.md` alone.
- **Scope**:
  - **Included**:
    - Add `VERIFIED` status to `docs/features.md` statuses (already done in this commit).
    - Build a verification harness in `vreaderUITests/Verification/` with one XCUITest file per backlog item, sharing helpers in `vreaderUITests/Verification/Helpers/` (DebugBridge URL builder, container JSON reader, settle-token waiter, fixture catalog).
    - Implement automated verifications for 13 simulator-automatable backlog items: features #11, #21, #23, #27, #28, #29 (with local WebDAV container), #31, #34, #35, #36 (with local OPDS feed fixture), #37, #40, #41.
    - Three proving-ground items implemented first to crystallize the pattern: **#37 Per-book reading settings** (simple UI-state assertion), **#34 Collections / tags** (SwiftData + UI), **#11 EPUB highlighting** (webview + race condition; previously bug #77).
    - For each item: at least one happy-path test plus the *specific* edge case that the original bug fix addressed (e.g., #11 must exercise the JS buffering race that bug #77 fixed; #28 must exercise the `didSet` re-apply path that bug #98 fixed).
    - Update `docs/manual-test-checklist.md`: each verified item is marked "Auto-verified by `<test-name>`" and removed from the human checklist.
    - CI: add a `xcodebuild test -only-testing:vreaderUITests/Verification` job to the existing test gate. Target completion under 8 min on CI hardware.
    - A short residual manual checklist (`docs/manual-test-checklist.md` "Real-device only" section) for the irreducible items: #26 TTS audio quality and any flow that requires real iCloud / real haptics / real Apple ID.
  - **Excluded**:
    - Verifying #26 audible TTS output (no programmatic way to QA voice quality on simulator).
    - Real iCloud sync paths, real Apple ID flows, real-device haptics — those stay manual.
    - Visual regression / snapshot diffing — separate concern, separate feature if/when it arrives.
    - Performance / load testing — separate concern.
    - Replacing existing unit tests in `vreaderTests/` — those continue to gate at the unit level; this harness is layered on top, not a replacement.
    - Full test fixture authoring tools (the harness uses fixed bundle resources from #44; new fixtures get added there, not here).
  - **Out of scope, deferred**:
    - Cross-device-type matrix runs (iPad layouts, multiple iOS versions).
    - Localization sweep across all supported languages — verifications run in the default locale.
    - Stress / fuzz testing of the bridge surface itself.
- **Edge cases**:
  - **Flaky tests**: Foliate render and SwiftData async save have inherent timing. The harness must use `settle` from #44 — never `sleep`. Any test that needs `sleep` to pass is rejected from merge.
  - **Fixture pollution**: each test runs `vreader-debug://reset` in `setUp` so the SwiftData container is fresh; tests that depend on a prior test's state are forbidden.
  - **WebDAV / OPDS containers**: tests that need a live server run *only* when the server is up; if it isn't, the test is skipped (not failed) with a clear log line. CI starts the containers as a job step before the test phase.
  - **Race conditions in concurrency-sensitive flows**: bug #77 (highlight buffering), bug #82 (paginate navigator preserve), bug #88 (highlight refresh on import) — each must have a verification that *would have caught the original bug* if run before the fix, not just a happy-path smoke. Verified by reverting the fix locally and confirming the test fails (RED check, then re-apply).
  - **Locale / dynamic type / dark mode**: verifications use a fixed default. A separate "appearance variations" sweep is out of scope.
  - **TTS callbacks without audio**: TTS verification asserts on `AVSpeechSynthesizerDelegate` callback events surfaced via DebugBridge `snapshot` — never requires audible output. Sentence boundary count + fired-callback count is the assertion.
  - **OPDS / WebDAV server flake**: harness uses local fixtures (a static OPDS XML feed served from the test bundle, a local WebDAV root in `/tmp`) to avoid external network dependence. CI never reaches the public internet.
  - **PhotosPicker (#32 theme backgrounds)**: simulator's photo library may be empty; the test seeds a known image into the simulator's Photos via `xcrun simctl addmedia` in setUp.
  - **DocumentPicker (import/export #35)**: handled via `vreader-debug://` import command that bypasses the OS picker (file path passed directly), since the picker is OS chrome and not vreader's responsibility. The test verifies *what happens after import succeeds*, not the picker UI.
  - **Test-name collisions**: each verification is named `verify_feature_<NN>_<short_name>` so they're greppable and the failure → tracker mapping is mechanical.
  - **Tracker drift**: when a verification passes, status moves to `VERIFIED`. When it later starts failing, it moves back to `DONE` and a bug is filed. CI prints a one-line status summary so the tracker can be updated mechanically.
- **Test plan**:
  - The deliverable *is* tests. The plan is what they cover and how they're structured.
  - **Helper unit tests** in `vreaderTests/Verification/`:
    - `DebugBridgeURLBuilderTests` — URL escaping, command serialization, fixture name validation.
    - `ContainerJSONReaderTests` — parses `simctl get_app_container` output, handles missing files, malformed JSON.
    - `SettleTokenWaiterTests` — timeout, success path, never returns false-positive.
    - `FixtureCatalogTests` — fixtures listed in catalog actually exist in the bundle.
  - **Verification tests** in `vreaderUITests/Verification/` — one file per feature in the 13-item list. Each file contains:
    1. A happy-path `verify_feature_<NN>_<name>` test.
    2. One regression test per linked bug (e.g., feature #11 has a test specifically targeting the bug #77 race).
  - **CI integration**: `verification` test plan added to the Xcode scheme; new CI step runs it after the unit-test phase. Failure of any verification → red CI.
- **Acceptance criteria**:
  - 13 of the 15 backlog items reach `VERIFIED` status, with each entry's Notes column citing the test name.
  - The 2 items that stay manual (#26 audio, anything real-device) are explicitly listed in `docs/manual-test-checklist.md` under a "Real-device only" section, and *removed* from the auto-verifiable list — the manual checklist for these gets shorter, not longer.
  - `xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 and completes in under 8 minutes on the CI runner.
  - Each regression test, when run against the pre-fix commit of its linked bug, fails (RED proof) — recorded once in `dev-docs/verification-red-checks.md`.
  - `docs/manual-test-checklist.md` reflects the new state: items moved to "Auto-verified by `<test-name>`" or "Real-device only".
  - CI prints a summary line per verification (`PASS feature_11_epub_highlighting in 4.2s`) so tracker updates are mechanical.
  - No verification test uses `sleep` or `Thread.sleep` for synchronization — `settle` and explicit waiters only.
  - Total LOC for harness helpers under 500; per-feature tests average ~80 LOC. Files under 300-line guideline.

