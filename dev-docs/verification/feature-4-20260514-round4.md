---
kind: feature
id: 4
status_target: VERIFIED
commit_sha: 177e3e35f83ae59dc3bde859e871cf41a5849f15
app_version: 3.21.53 (build 330)
date: 2026-05-14
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (bundled war-and-peace.txt fixture, chapter mode)
result: fail
---

# Feature #4 — Add notes/annotations to text (round 4 — REGRESSION discovered)

## Context

Round-3 (2026-05-13, `feature-4-20260513.md`) closed the save round-trip
half of criterion 8 at v3.21.8 (`AnnotationRecord` persisted, Notes
tab row appeared with body + timestamp) and closed criterion 9 (Edit/
Delete context menu). Only criterion 8c (visual highlight on annotated
text) remained FAIL — gated on bug #160's chapter-mode visual-paint fix.

Bug #160's chapter-mode visual-paint fix landed via feature #48 WI-3
(PR #570, v3.20.0). Bug #181 (Add Note must also create a
`HighlightRecord` with the note attached) shipped earlier today at
v3.21.53 (PR #658, commit 177e3e35). Round 4 was set up to verify
criterion 8c is now PASS at v3.21.53.

## Acceptance criteria (per docs/features.md row #4)

| Sub-criterion | Observed | Pass? |
|---|---|---|
| Long-press text → custom menu shows Highlight \| Add Note \| Define | Tap-and-hold on word "Lucca" / "Genoa" / "family" in Chapter 1 → custom 4-item menu appears with `Highlight \| Add Note \| Define \| ▶` | **PASS** |
| Tap "Add Note" → AddNoteSheet presents | AddNoteSheet slides up with `Cancel \| Add Note \| Save (disabled)` toolbar, selected word as italic attribution (e.g. `"Lucca"`), empty TextEditor | **PASS** |
| Type / paste note text → Save enables | Pasted "Italian port city — bug #181 verify" via `mcp__computer-use__write_clipboard` + `Cmd+V` → text appears in TextEditor → Save button enables (no longer greyed out) | **PASS** |
| Tap Save → modal dismisses + AnnotationRecord persisted (Notes tab shows row) | Modal dismisses cleanly. Re-opening Annotations panel → Notes tab shows **"No Annotations"** empty state. SQLite `ZANNOTATIONNOTE` table: **0 rows**. | **FAIL** (regression from round-3 PASS) |
| Tap Save → HighlightRecord persisted (bug #181 fix) so yellow background appears on annotated text (criterion 8c) | `vreader-debug://snapshot` reports `highlightCount: 0`. SQLite `ZHIGHLIGHT` table: **0 rows**. No yellow paint on "Lucca" / "Genoa". | **FAIL** (bug #181 fix not working) |
| Long-press existing note row → Edit / Delete menu | Could not exercise — no notes exist to long-press on (above FAIL means nothing was persisted). | **N/A** |

**Overall: fail.** Both AnnotationRecord and HighlightRecord persistence are now broken on the Save path. This is a regression — round-3 verified the AnnotationRecord persistence was PASS at v3.21.8.

## Control test — Highlight path still works

To rule out a deeper locatorFactory / persistence regression, I ran the same long-press → tap "Highlight" (not "Add Note") on the word "family" in chapter 1, paragraph 1.

- Snapshot after: `highlightCount: 1`
- SQLite `ZHIGHLIGHT`: 1 row, `selectedText="family"`, `color="yellow"`, no note
- Visual: **yellow background visible on "family"** in the reader viewport

So the Highlight path (which routes through `ReaderNotificationHandlers.handleHighlightRequest` and NOT through `handleAnnotationSave`) is healthy. The locatorFactory IS returning valid locators in chapter mode. The PersistenceActor IS writing rows. Bug #160's chapter-mode visual paint IS working for `HighlightRecord` rows.

The failure is specifically in the **Add Note → Save** path that goes through `handleAnnotationSave`.

## Root cause analysis

Reading `vreader/Views/Annotations/AddNoteSheet.swift:45-48`:

```swift
Button("Save") {
    onSave()
    dismiss()
}
```

The Save button calls `onSave()` synchronously, then `dismiss()` synchronously.

`onSave` (after my bug #181 fix in `vreader/Views/Reader/ReaderNotificationModifier.swift:91-99`) is:

```swift
onSave: {
    Task {
        await ReaderNotificationHandlers.handleAnnotationSave(
            state: uiState,
            deps: deps,
            highlightCoordinator: highlightCoordinator
        )
    }
}
```

So the Save button action does:
1. Enqueue `Task { ... }` — Task body has NOT executed yet.
2. Call `dismiss()` — this triggers the parent `.sheet(isPresented:)` binding's `set: false` closure synchronously, which runs `uiState.pendingAnnotationInfo = nil`.
3. Return.
4. SwiftUI animates sheet dismiss.
5. *Eventually* MainActor runs the enqueued Task → calls `handleAnnotationSave`.
6. Handler reads `state.pendingAnnotationInfo` → **nil** (cleared in step 2).
7. Handler hits the first guard and returns early. **Nothing persists.**

Pre-bug-181 `onSave` (the original code) did the validation **synchronously inside the closure** and captured `info` / `trimmed` / `locator` into the Task's closure before the dismiss could clear `pendingAnnotationInfo`:

```swift
onSave: {
    guard let info = uiState.pendingAnnotationInfo else { ... }
    let trimmed = uiState.annotationNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { ... }
    guard let locator = deps.locatorFactory(...) else { ... }
    uiState.pendingAnnotationInfo = nil
    Task {
        try? await deps.annotationPersistence.addAnnotation(
            locator: locator,    // captured by value
            content: trimmed,    // captured by value
            toBookWithKey: deps.bookFingerprintKey
        )
    }
}
```

The captured values made the Task immune to the dismiss race. My refactor to delegate to `handleAnnotationSave(state:, deps:, highlightCoordinator:)` lost this property — the handler reads `state.pendingAnnotationInfo` AFTER the Task starts, by which time `dismiss()` has already cleared it.

## Bug filing

Filed as Bug #188 (regression of Bug #181 fix). See `docs/bugs.md` and GH issue.

## Commands run

```bash
SIM_ID="1FAB9493-B97E-48F0-96C7-44A8E5AAA21E"
BUILD_DIR="/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator"

xcrun simctl install "$SIM_ID" "$BUILD_DIR/vreader.app"
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
# (tap cover via computer-use)
# (long-press "Lucca" → Add Note → paste → Save → modal dismisses)
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=after-save.json"
# snapshot output: highlightCount: 0

# Inspect SwiftData store directly
APPDIR="/Users/ll/Library/Developer/CoreSimulator/Devices/.../912A7B5E-.../"
sqlite3 "$APPDIR/Library/Application Support/default.store" \
    "SELECT * FROM ZANNOTATIONNOTE;"  # 0 rows
sqlite3 "$APPDIR/Library/Application Support/default.store" \
    "SELECT Z_PK, ZSELECTEDTEXT, ZNOTE, ZCOLOR FROM ZHIGHLIGHT;"
# (After Highlight test on "family") → 8|family||yellow
```

## Observations

- Add Note Save in chapter-mode TXT (war-and-peace.txt) persists NOTHING at v3.21.53.
- Highlight gesture in the same chapter persists correctly AND renders yellow paint.
- Sheet dismissal vs. Task scheduling is the race window — `dismiss()` clears `pendingAnnotationInfo` before the spawned Task reads it.
- This is reproducible 100% (3/3 attempts: "Lucca", "Genoa", same chapter 1).

## Verdict

`fail` for round 4. Criterion 8 (save round-trip) regressed from PASS at v3.21.8 to FAIL at v3.21.53. Criterion 8c (visual highlight on annotated text) remains FAIL — not because bug #181 fix is wrong in principle, but because the Save handler is hitting an early-return before its `coordinator.create(...)` call runs.

Feature #4 stays at `DONE` (cannot flip to VERIFIED). Pending bug #188 (regression fix).

## Artifacts

- `dev-docs/verification/artifacts/feature-4-r4-01-chapter1-loaded-20260514.png` — chapter 1 paragraphs visible, no highlights yet.
- `dev-docs/verification/artifacts/feature-4-r4-02-highlight-family-paint-no-annotation-on-genoa-lucca-20260514.png` — control test: "family" highlighted via Highlight gesture renders yellow correctly; "Lucca" and "Genoa" (where Add Note Save was attempted) show no yellow paint.
