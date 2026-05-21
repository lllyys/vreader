---
branch: docs/triage-feature-71-epub-continuous-scroll
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-21
---

## Scope

Docs-only triage filing. Adds one new summary row to `docs/features.md`
for Feature #71 (EPUB scroll-mode continuous cross-chapter scroll),
split out of Bug #165's deferred §2.3. Touches `docs/features.md`
only, plus `project.yml` / `project.pbxproj` (version bump
3.39.3/624 → 3.39.4/625).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### Investigation done at triage time

1. Read Bug #165's tracker row — status **FIXED v3.38.36**. The
   FIXED note states the fix delivered design **§2.2 (paged-mode
   chapter wrap)** via `EPUBChapterNavigationRouter` +
   `EPUBChapterWrapPendingTarget` + `EPUBReaderContainerView+ChapterWrap`,
   and that **§2.3 (continuous cross-chapter scroll) was explicitly
   deferred to a follow-up feature — "architectural rewrite of
   `EPUBWebViewBridge`'s single-chapter-per-load model."**
2. Searched `docs/features.md` for any existing row covering EPUB
   continuous / cross-chapter scroll — none exists. The deferral was
   noted in #165 but never filed as a feature row.
3. Confirmed the sibling cross-chapter-scroll bugs are FIXED and were
   bug-class (contained): Bug #180 (TXT, RE-SCOPED then FIXED), Bug
   #235 (AZW3/MOBI Foliate paginator, FIXED). The architectural
   difference (EPUBWebViewBridge = one spine item per WKWebView load)
   is why EPUB is feature-class while TXT/AZW3 were bugs.
4. Confirmed design §2.3 exists in
   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md`
   — so the eventual plan is not design-blocked.

### Correctness checks

1. **Bug-vs-feature distinction** — the continuous cross-chapter
   scroll capability for EPUB scroll mode was **never built**
   (EPUBWebViewBridge loads one chapter per WebView load). Bug #165's
   own FIXED note classifies the remaining §2.3 as feature-class
   ("architectural rewrite"). Per AGENTS.md (broken implementation →
   bug; never implemented → feature), this is correctly a **feature**,
   recorded in `docs/features.md` — NOT a bug, and NOT a reopen of
   #165 (which correctly shipped its §2.2 scope).
2. **No duplicate** — no existing feature row covers EPUB continuous
   cross-chapter scroll; no open bug covers it (the only related bug,
   #165, is FIXED for its delivered scope).
3. **Not a reopen** — #165 delivered exactly what it scoped (§2.2).
   Reopening would conflate delivered paged work with deferred scroll
   work. Filing the follow-up feature with a cross-reference is the
   correct lineage per #165's own deferral note.
4. **GH mirror timing** — status is `TODO`. Per AGENTS.md
   mechanical-mirror, features are mirrored to GH at `PLANNED`, not
   `TODO`. So **no GH issue is created at triage** — the row's Notes
   say so explicitly. (Contrast: bugs are mirrored on any new row.)
5. **Feature ID** — max feature ID was 70; 71 is the next free. No
   collision.
6. **No planning done** — triage records the summary row with a
   problem statement + scope/edge-case/acceptance sketches for the
   eventual planner; it does NOT produce the full Gate-1 plan (that's
   `/feature-workflow`'s job).
7. **Version bump** — 3.39.4 / build 625 (patch — docs / tracker
   triage). `xcodegen generate` + `xcodebuild build` SUCCEEDED on
   iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — documentation only, one feature filing, no code risk.
Manual fallback used because there is nothing to send to Codex.
