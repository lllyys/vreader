---
branch: docs/triage-bug-249-notes-panel-no-delete
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Docs-only triage filing. Adds one new summary row + one
Open-Bug-Details entry to `docs/bugs.md` for Bug #249
(HighlightsSheet has no delete affordance — feature #62 WI-5
regression). Touches `docs/bugs.md` only, plus `project.yml` /
`project.pbxproj` (version bump 3.38.20/595 → 3.38.21/596).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### Investigation done at triage time

1. Read `vreader/Views/Reader/Annotations/HighlightsSheet.swift` —
   confirmed container is `ScrollView { LazyVStack { ... } }` at
   lines 84 + 222. No `.swipeActions`, no `.onDelete`, no
   `List`, no `.contextMenu`.
2. Read `vreader/Views/Reader/Annotations/HighlightAnnotationCard.swift`
   — confirmed both card kinds (`HighlightRecord`,
   `AnnotationRecord`) have a single `Button { onJump(...) }` body
   at line 92. No trash button, no `⋯` menu, no long-press menu.
3. Grep'd entire `vreader/Views/Reader/Annotations/` for
   `delete|onDelete|swipe|trash|removeAnnotation|removeHighlight`
   — zero matches in any sheet/card file.
4. `git log --all --oneline -- "**/AnnotationListView*.swift"`
   confirmed the legacy view was deleted by commit `d17f6dfd`
   (feature #62 WI-5).
5. `git show d17f6dfd^:vreader/Views/Annotations/AnnotationListView.swift`
   confirmed the legacy view had:
   - Purpose comment: *"Supports swipe-to-delete, tap to navigate,
     and edit via sheet."*
   - `.onDelete(perform: deleteAnnotations)` calling
     `viewModel.removeAnnotation(annotationId: ...)`.
6. Confirmed `AnnotationListViewModel.removeAnnotation` still
   exists in production (data layer intact).
7. Read `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx`
   and `design-notes/needs-design-issues.md` — confirmed the
   committed design covers Highlight + Standalone-Note cards,
   filter chip set, and empty states, but does NOT depict any
   destructive row action in the HighlightsSheet review surface.
   The note-preview design note (`#865`) says *"Destructive
   actions live elsewhere"* — that's about the tap-on-annotated-
   text presenter, not the review sheet.

### Correctness checks

1. **Bug-vs-feature distinction** — swipe-to-delete WAS
   implemented (legacy `AnnotationListView` with `.onDelete`) and
   was lost in the feature #62 WI-5 migration. Implemented-
   then-regressed = bug.
2. **No open duplicate** — no existing row covers "Notes panel
   delete affordance missing". Bug #248 is the sibling regression
   for TOC auto-scroll; same root cause class but different
   surface.
3. **GH mirror** — issue #1080 created with `bug` +
   `severity:high` labels. `GH: #1080` stamped in Notes column.
4. **Bug ID** — max ID on `main` (post-pull, after #248) was
   248. Next free is 249. No collision.
5. **Rule-51 constraint correctly flagged** — the entry's fix
   direction explicitly notes the design-bundle gap and that the
   `/fix-issue` run must file a `Design needed:` issue before
   shipping any UI. Does NOT preemptively file the
   `Design needed:` issue at triage time (that's a fix-flow
   concern, not a triage one).
6. **No fix attempted** — triage is classification only.
7. **Version bump** — 3.38.21 / build 596 (patch — docs / tracker
   triage). `xcodegen generate` confirmed; `xcodebuild build`
   SUCCEEDED on iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — documentation only, one bug filing, no code risk.
Manual fallback used because there is nothing to send to Codex.
