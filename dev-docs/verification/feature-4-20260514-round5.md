---
kind: feature
id: 4
status_target: VERIFIED
commit_sha: e66b15952b0248ba8d7dfb8416444cd1c4254984
app_version: 3.21.55 (build 332)
date: 2026-05-14
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #4 — Add notes/annotations to text — round-5 device verification

## Summary

Round-5 device verification against the merged-main build at v3.21.55
(commit `e66b1595`). Bug #188 fix (PR #662) restored the Add Note save
round-trip. Closes the last gating criterion (8c) from round-4 (which
failed with criterion 8 regression). Feature #4 is now fully verified
end-to-end.

## Acceptance criteria

| # | Criterion | Round | Observed | Result |
|---|---|---|---|---|
| 1 | Annotation entry-point in UITextView edit menu (`Add Note` action) | 1, 2, 3 | Custom 4-item menu (`Highlight \| Add Note \| Define \| ▶`) appears on long-press; `Add Note` is item 2 | pass |
| 2 | AnnotationListViewModel CRUD (4 sub-suites, 130 tests across 10 suites) | 1 | All slice tests pass against in-memory `ModelContainer` | pass |
| 3 | AnnotationAnchor round-trips (EPUB / PDF / TXT) + SHA stability | 1 | Slice tests pin behavior | pass |
| 4 | PDFAnnotationBridge highlight + restore | 1 | Slice tests | pass |
| 5 | AnnotationExporter (JSON + Markdown) | 1 | Slice tests | pass |
| 6 | VReaderAnnotationParser + AnnotationImporter end-to-end | 1 | Slice tests | pass |
| 7 | Bug #44 entry-menu lock (Add Note action wired into the custom UIMenu) | 1, 2 | Confirmed via feature #3 cross-ref + this round's gesture replay | pass |
| 8 | Long-press → `Add Note` → modal → empty-input gating → Save → modal dismiss → persisted note row in Notes tab (full save round-trip) | 2 (partial), 3 (pass at data layer), 4 (**REGRESSED to fail**), **5 (pass)** | Long-press `Lucca` (Ch1 line 1) → custom menu → `Add Note` → modal opens with `"Lucca"` attribution + empty SecureField + greyed Save → clipboard fast-path paste "Italian port city — Feature #4 round-5 verify against v3.21.55 (bug #188 fix on main)" → Save flips enabled → tap Save → modal dismisses → annotations panel → Notes tab shows row with `Lucca` chip + body + `May 14, 2026 at 21:51` timestamp. SQLite confirms BOTH records: `ZANNOTATIONNOTE` 1 row, `ZHIGHLIGHT` 1 row (selectedText=`Lucca`, color=`yellow`, note matches). `DebugBridge` snapshot `highlightCount: 1`. | **pass** |
| 8c | Visual yellow background on annotated text in chapter mode | 3, 4 (fail — bug #160 then bug #188), **5 (pass)** | After Save modal dismisses + selection handles dismissed (single tap to hide chrome), `"Lucca"` shows clear `UIColor.systemYellow.withAlphaComponent(0.4)` background in the rendered chapter-mode UITextView. Artifact: `feature-4-r5-clean-yellow-on-lucca-20260514.png`. The bug #181 fix's `coordinator.create(... note: trimmed)` call is now reached on every Save (was no-op at v3.21.53 due to bug #188 dismiss race); the chapter-mode rendering path (bug #160 fix from feature #48 WI-3) paints the yellow successfully. | **pass** |
| 9 | Long-press existing note row in Notes tab → Edit + Delete context menu | 3 | Closed in round-3 — context menu reveals Edit (default) + Delete (destructive-red) styles | pass |
| 10 | Export round-trip (Markdown / JSON) and Import round-trip via document picker | 1 | Slice tests + per-format renderer coverage | pass |

## Commands run

```bash
# 1. Confirm main HEAD + version
git rev-parse HEAD                          # e66b15952b0248ba8d7dfb8416444cd1c4254984
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml
# CURRENT_PROJECT_VERSION: 332
# MARKETING_VERSION: 3.21.55

# 2. Rebuild + install fresh from main
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcrun simctl terminate booted com.vreader.app
xcrun simctl install booted /Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl launch booted com.vreader.app

# 3. Reset + seed + open via DebugBridge
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl openurl booted "vreader-debug://open?bookId=txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"

# 4. Drive Add Note flow with computer-use
#    - tap Next to reach Chapter 1 prose (page 2/4)
#    - long-press on "Lucca" (mouse_down 0.9s)
#    - tap "Add Note" item in custom 4-item menu
#    - write_clipboard the note text + cmd+v paste
#    - tap Save (enabled)

# 5. Verify persistence
xcrun simctl openurl booted "vreader-debug://snapshot?dest=f4r5-postsave.json"
# → {"highlightCount": 1, "lastError": null, ...}

sqlite3 "$DATA/Library/Application Support/default.store" \
  "SELECT COUNT(*) FROM ZANNOTATIONNOTE; SELECT COUNT(*) FROM ZHIGHLIGHT;"
# → 1 / 1

sqlite3 "$DATA/Library/Application Support/default.store" \
  "SELECT ZSELECTEDTEXT, ZCOLOR, ZNOTE FROM ZHIGHLIGHT;"
# → Lucca|yellow|Italian port city — Feature #4 round-5 verify against v3.21.55 (bug #188 fix on main)

# 6. Verify Notes tab UI
#    - tap annotations toolbar icon → annotations panel opens on Contents tab
#    - tap "Notes" tab → row with "Lucca" chip + body + timestamp visible
```

## Observations

- **Bug #188 fix held under production sequence.** The Save-button
  closure now does `prepareAnnotationSave(state:, deps:)` synchronously
  before the AddNoteSheet's `dismiss()` clears `pendingAnnotationInfo`,
  then spawns the `Task` with the captured `AnnotationSaveRequest`
  value. The `handleAnnotationSave(info:, trimmed:, locator:, deps:,
  highlightCoordinator:)` body never reads `state` — pure dual-write
  of pre-captured args. The dismiss race that broke v3.21.53 (bug #188)
  is structurally impossible in the new signature.

- **Bug #181 fix held simultaneously.** Both records persist atomically
  — the annotation write throws-or-succeeds, and only on success does
  `highlightCoordinator.create` run. SQLite shows both rows; deletion
  of one without the other would imply a `ZANNOTATIONNOTE != ZHIGHLIGHT`
  count, which is not present.

- **Chapter-mode yellow paint (bug #160 fix from feature #48 WI-3)
  held.** war-and-peace.txt has 4 detected chapters (`Chapter 1/2/3` +
  cover); the body dispatches to `chapterReaderContent`. The yellow
  background renders on "Lucca" in the chapter-local glyph range
  after the `LocatorFactory.txtChapterRange` + `makeLocatorForTXT`
  translation runs through the bug #160 fix path.

- **Pre-FIXED Bug #188 verify (16:23 same day) reused.** The earlier
  same-session pre-merge verify used the exact same v3.21.55 / build
  332 binary against the war-and-peace fixture. Re-running here against
  the merged main commit `e66b1595` produces an identical positive
  signal — no merge-side drift.

- **Chrome auto-hide reveals yellow.** Save returns the user to the
  reader with selection handles still active. A single tap dismisses
  the handles AND collapses chrome to the minimum (only the page
  status bar remains); the yellow is clearly visible against the white
  TXT background.

## Artifacts

- `dev-docs/verification/artifacts/feature-4-r5-postsave-yellow-on-lucca-20260514.png`
  — immediately after Save dismiss (selection handles still active,
  yellow on "Lucca").
- `dev-docs/verification/artifacts/feature-4-r5-clean-yellow-on-lucca-20260514.png`
  — chrome restored, selection cleared, yellow plainly visible on
  "Lucca" in chapter mode.
- `dev-docs/verification/artifacts/feature-4-r5-notes-tab-lucca-row-20260514.png`
  — annotations panel → Notes tab showing the row with `Lucca` chip,
  body matching paste, `May 14, 2026 at 21:51` timestamp.

## Status transition

`docs/features.md` Feature #4 row: `DONE` → `VERIFIED`.

This also unblocks:
- Bug #181 (GH #616) close-gate device verification — the
  `coordinator.create(... note: trimmed)` call is now reached and
  produces the yellow paint on annotated text, confirming the original
  fix's behavior.
- Bug #188 (GH #659) close-gate device verification — round-5's
  full repro shows BOTH records persist + visual highlight rendered,
  the exact symptom from the bug body.
