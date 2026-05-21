---
branch: docs/notes-delete-handoff
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-21
---

## Scope

Syncs the claude.ai/design "VReader Notes Delete Canvas" handoff
(chat10) into the `dev-docs/designs/vreader-fidelity-v1/` bundle and
unblocks Bug #249. Touches the design bundle + one tracker row
(`docs/bugs.md` Bug #249 design-landed note), plus `project.yml` /
`project.pbxproj` (version bump → 3.38.44/619 after rebasing onto
origin/main, which had advanced to 3.38.43/618 via the #250–#257
DebugBridge-harness work merged concurrently).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### What changed and why

Bundle sync (rsync, superset — nothing deleted): 3 new files —
`VReader Notes Delete Canvas.html`, `vreader-notes-delete.jsx`,
`notes-delete-canvas-artboards.jsx`; `chats/chat10.md` added;
`chats/chat9.md` gained a trailing `#1103` user message (appended by
the design tool); `README.md` chat count 9 → 10.

`docs/bugs.md` Bug #249's summary row gains a "Design landed
2026-05-21" note pointing at the committed canvas + naming the
canonical decision, marking the bug unblocked for implementation.

The handoff delivers the committed design for `needs-design` issue
**#1103** — the delete affordance in the `HighlightsSheet` (Notes
panel), the missing capability Bug #249 (GH #1080) flagged as a
feature #62 WI-5 regression.

### Canonical design (chat10)

Trailing `⋯` icon-button per card → `NotesActionMenu` (Edit · Copy ·
Delete); inline row-replacement confirm strip mirroring
`HPDeleteConfirm` from the highlight-popover design (#949); secondary
iOS left-swipe with the same destinations; Edit hands off to the
existing `HighlightActionCard` (highlights) / note editor
(standalones). Container stays `LazyVStack` — NOT a `List` reskin —
so the just-shipped v3 cards are untouched (avoids the visible
regression that shape (a) `List` + `.swipeActions` would force).

### Correctness checks

1. **#1103 is a real, open `needs-design` issue** — verified via
   `gh issue view 1103`: OPEN, labels `enhancement` +
   `needs-design`, title "Design needed: delete affordance in
   HighlightsSheet (Notes panel) for bug #249". Body references
   "Refs #1080 (Bug #249 …)".
2. **Issue → bug linkage** — #1103's body names Bug #249 / GH
   #1080. Bug #249's row is updated with the design-landed note so
   the markdown tracker reflects the unblock. Status stays `TODO`
   (implementation hasn't happened — design landing doesn't change
   the bug's fix status, only removes the needs-design block).
3. **Issue closure** — PR uses `Resolves #1103` so the
   `needs-design` issue auto-closes on merge (same precedent as PRs
   #1077 / #1060 / #1039 / #1037 / #972 / #956 / #930 / #869 /
   #848). Bug #249 (GH #1080) stays OPEN — only the design
   dependency closed; the code fix is still pending.
4. **No Swift implemented** — design-delivery + tracker-unblock
   only. Building the delete affordance is gated bug-#249 fix work
   (`/fix-issue #1080`), deliberately not in this PR.
5. **Bundle-diff sanity** — `diff -rq` against the incoming handoff
   matched exactly: README + chat9 (append) + chat10 (new) + 1 HTML
   + 2 JSX. No silent overwrites of existing canvases.
6. **Rule-51 satisfied** — the surface that was undesigned at
   triage time (Bug #249) now has a committed design bundle. The
   subsequent `/fix-issue` run can implement against it without
   inventing UI.
7. **Version bump** — 3.38.44 / build 619 (patch — docs /
   design-bundle sync; resolved after a merge with origin/main that
   had reached 3.38.43/618). `xcodegen generate` confirmed both
   files; `xcodebuild build` SUCCEEDED on iPhone 17 Pro Simulator
   (Debug). The `docs/bugs.md` merge took the union — origin's new
   rows #250–#257 plus this branch's Bug #249 design-landed note.

## Verdict

ship-as-is — design-bundle sync + tracker unblock + version bump.
No Swift logic. Manual fallback used because there is nothing to
send to Codex.
