---
branch: docs/triage-bug-248-toc-no-scroll-to-current
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Docs-only triage filing. Adds one new summary row + one
Open-Bug-Details entry to `docs/bugs.md` for Bug #248 (TOC sheet
doesn't auto-scroll to current chapter, regression from feature
#62 WI-5). Touches `docs/bugs.md` only, plus `project.yml` /
`project.pbxproj` (version bump 3.38.19/594 → 3.38.20/595).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### Investigation done at triage time

1. Read `vreader/Views/Reader/Annotations/TOCSheet.swift` and
   confirmed `tocEntryList` (lines 213-230) is a bare `LazyVStack`
   inside an outer scroll container — no `ScrollViewReader`, no
   `proxy.scrollTo`, no `.onAppear` calling scroll.
2. Read `vreader/Views/Reader/Annotations/TOCSheet+Support.swift`
   and confirmed `activeEntryIndex` (lines 99-104) +
   `matchedEntryIndex(for:)` (lines 74-97) match logic IS lifted
   from the legacy `TOCListView` — so the data layer is intact.
3. Read `vreader/Views/Reader/Annotations/TOCSheetRows.swift` and
   confirmed `TOCContentsRow` accepts `isCurrent: Bool` and styles
   accent background + bold when true (lines 34-67).
4. Read `vreader/Views/Reader/ReaderContainerView+Sheets.swift`
   line 420 and confirmed `currentLocator` IS passed to
   `TOCSheet(currentLocator: currentLocator, ...)`.
5. Verified `TXTReaderViewModel.swift:745` still posts
   `.readerPositionDidChange` so `currentLocator` is updated.
6. Confirmed via git archaeology that the legacy `TOCListView`
   had auto-scroll wired by commits `9499a04a` (2026-03-22, "feat:
   TOC scrolls to current chapter on open") and `edc550d0`
   (long-list retry hardening).
7. Confirmed via `git log --oneline -- "**/TOCListView*"` that
   commit `d17f6dfd` (feature #62 WI-5, 2026-05-19) deleted
   `TOCListView.swift` and migrated to `TOCSheet`. Diff confirms
   the `ScrollViewReader { proxy in ... onAppear { proxy.scrollTo
   (activeEntry.id) } }` wrapping was NOT lifted.

### Correctness checks

1. **Bug-vs-feature distinction** — auto-scroll WAS implemented
   (commits `9499a04a` + `edc550d0`) and now isn't. Implemented-
   but-broken-by-migration = bug. Correct classification.
2. **No open duplicate** — no existing bug or feature row covers
   "TOC sheet doesn't auto-scroll to current chapter". Feature
   #38 (Hierarchical TOC) is VERIFIED and covers a different
   axis. Feature #62 WI-5 was VERIFIED 2026-05-19 with this gap
   unobserved.
3. **GH mirror** — issue #1078 created with `bug` +
   `severity:medium` labels. `GH: #1078` stamped in Notes column
   per mechanical-mirror rule.
4. **Bug ID** — max ID on `main` (post-pull) was 247; next free
   is 248. No collision.
5. **No fix attempted** — triage is classification only; the
   entry captures symptom, repro, regression source, fix
   direction, and the highlight-not-visible sub-question that
   needs in-sim verification. The fix will go through
   `/fix-issue #1078`.
6. **Highlight sub-question kept open** — user reported BOTH
   "doesn't jump" AND "highline the title" not working. Code
   read confirms auto-scroll is genuinely missing, but highlight
   logic IS present. The bug entry frames this honestly: file
   the unambiguous regression (auto-scroll), note the
   highlight-not-visible report as a sub-question for the fix
   run to verify in-sim. Don't over-claim either way.
7. **Version bump** — 3.38.20 / build 595 (patch — docs / tracker
   triage). `xcodegen generate` confirmed; `xcodebuild build`
   SUCCEEDED on iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — documentation only, one bug filing, no code risk.
Manual fallback used because there is nothing to send to Codex.
