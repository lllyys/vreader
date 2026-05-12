---
branch: fix/bugs-154-160-fixed-status
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-12
---

# Manual Audit — fix/bugs-154-160-fixed-status

Pure documentation tracker update: `docs/bugs.md` rows #154 and #160 status
changed from `PARTIALLY FIXED` to `FIXED`. No Swift code changed.

## Manual Audit Evidence

**Files read:**
- `docs/bugs.md` (rows #154 and #160)
- `vreader/Services/Locator/LocatorFactory.swift` (confirmed `txtChapterRange` present)
- `vreader/Views/Reader/TXTReaderContainerView.swift` (confirmed `makeLocatorForTXT` present)
- `dev-docs/plans/20260507-feature-48-txt-chapter-highlight.md` (confirmed WI-3 scope)

**Symbols verified:**
- `LocatorFactory.txtChapterRange(fingerprint:chapterLocalStart:chapterLocalEnd:chapterText:chapterGlobalStart:)` — present on main (commit a472a6d)
- `TXTReaderContainerView.makeLocatorForTXT` — present on main
- WI-1 (PR #553), WI-2 (PR #566), WI-3 (PR #570) — all merged to main as of 2026-05-12

**Claim verified:** Bugs #154 and #160 described chapter-mode highlight creation failures
(wrong global offsets due to missing chapter-local → global translation). Feature #48
WI-3 provides the translation layer. The code fix for the bugs' remaining sub-piece is
now on main.

**Edge cases checked:**
- Status flip from PARTIALLY FIXED → FIXED is semantically correct: all code pieces are on main
- GH issues #476 and #443 retain `awaiting-device-verification` label — close gate not yet met
- Notes columns already contain `GH: #476` and `GH: #443` — mirror hook satisfied

**Risks accepted:**
- None. Docs-only change.

## Summary Verdict

Documentation tracker flip only. No logic, no compilation, no test impact.

**Verdict: ship-as-is**
